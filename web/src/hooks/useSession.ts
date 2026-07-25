import { useCallback, useEffect, useRef, useState } from 'react'
import {
  collection,
  doc,
  getDocs,
  onSnapshot,
  orderBy,
  query,
  type Unsubscribe,
} from 'firebase/firestore'
import { buildDemoSnapshot } from '../data/demoSession'
import { DEFAULT_SESSION_ID, getDb, isFirebaseConfigured } from '../lib/firebase'
import type {
  GazeWindow,
  Session,
  SessionModule,
  SessionSnapshot,
  Trial,
  TrialWithGaze,
} from '../types/session'

export type DataMode = 'live' | 'demo' | 'connecting' | 'error'

function asNumber(value: unknown, fallback = 0): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function asNullableNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function asNullableBool(value: unknown): boolean | null {
  return typeof value === 'boolean' ? value : null
}

function parseModule(data: Record<string, unknown>): SessionModule {
  if (data.module === 'kineticClock' || data.module === 'visionPvt') {
    return data.module
  }
  // Infer from trial-shaped hints on the session doc, else default vision.
  if (data.module === 'kinetic' || data.module === 'clock') return 'kineticClock'
  return 'visionPvt'
}

function parseSession(id: string, data: Record<string, unknown>): Session {
  const startedAtRaw = data.startedAt
  let startedAt = Date.now()
  if (typeof startedAtRaw === 'number') {
    startedAt = startedAtRaw
  } else if (
    startedAtRaw &&
    typeof startedAtRaw === 'object' &&
    'toMillis' in startedAtRaw &&
    typeof (startedAtRaw as { toMillis: () => number }).toMillis === 'function'
  ) {
    startedAt = (startedAtRaw as { toMillis: () => number }).toMillis()
  }

  return {
    id,
    athleteId: typeof data.athleteId === 'string' ? data.athleteId : 'unknown',
    module: parseModule(data),
    startedAt,
    status: data.status === 'complete' ? 'complete' : 'active',
    clockOffsetMs: asNumber(data.clockOffsetMs),
    clockRttMs: asNumber(data.clockRttMs),
    baselineGapMs: asNullableNumber(data.baselineGapMs),
    baselineStdMs: asNullableNumber(data.baselineStdMs),
    breakPointTrial: asNullableNumber(data.breakPointTrial),
    lastHeartRateBpm: asNullableNumber(data.lastHeartRateBpm),
    lastHeartRatePhoneMs: asNullableNumber(data.lastHeartRatePhoneMs),
    lastHeartRateWatchMs: asNullableNumber(data.lastHeartRateWatchMs),
    lastHeartRateSource:
      typeof data.lastHeartRateSource === 'string'
        ? data.lastHeartRateSource
        : null,
  }
}

function parseTrial(id: string, data: Record<string, unknown>): Trial {
  const index = asNumber(data.index, Number.parseInt(id, 10) || 0)
  return {
    id,
    index,
    targetCell: asNullableNumber(data.targetCell),
    targetOctant: asNullableNumber(data.targetOctant),
    detectedOctant: asNullableNumber(data.detectedOctant),
    spatialMatch: asNullableBool(data.spatialMatch),
    targetOnsetMs: asNumber(data.targetOnsetMs),
    saccadeOnsetMs: asNullableNumber(data.saccadeOnsetMs),
    gazeSettleMs: asNullableNumber(data.gazeSettleMs),
    strikeMs: asNullableNumber(data.strikeMs),
    visualRtMs: asNullableNumber(data.visualRtMs),
    motorRtMs: asNullableNumber(data.motorRtMs),
    cognitiveMotorGapMs: asNullableNumber(data.cognitiveMotorGapMs),
    peakG: asNullableNumber(data.peakG),
    arousalIndex: asNullableNumber(data.arousalIndex),
    valid: data.valid !== false,
  }
}

function parseGaze(data: Record<string, unknown>): GazeWindow | null {
  const samplesRaw = data.samples
  if (!Array.isArray(samplesRaw)) return null
  const samples = samplesRaw
    .map((s) => {
      if (!s || typeof s !== 'object') return null
      const row = s as Record<string, unknown>
      return {
        dt: asNumber(row.dt),
        x: asNumber(row.x),
        y: asNumber(row.y),
        z: asNumber(row.z),
      }
    })
    .filter((s): s is NonNullable<typeof s> => s !== null)
  if (samples.length === 0) return null
  return { t0Ms: asNumber(data.t0Ms), samples }
}

async function loadGazeForTrial(
  sessionId: string,
  trialId: string,
): Promise<GazeWindow | null> {
  const db = getDb()
  if (!db) return null
  try {
    const snap = await getDocs(collection(db, 'sessions', sessionId, 'trials', trialId, 'gaze'))
    if (snap.empty) return null
    const preferred =
      snap.docs.find((d) => d.id === 'window') ??
      snap.docs[0]
    return parseGaze(preferred.data() as Record<string, unknown>)
  } catch {
    return null
  }
}

export interface UseSessionResult {
  mode: DataMode
  sessionId: string
  setSessionId: (id: string) => void
  snapshot: SessionSnapshot | null
  error: string | null
  forceDemo: (module?: SessionModule) => void
  exitDemo: () => void
  isDemoForced: boolean
}

export function useSession(initialId = DEFAULT_SESSION_ID): UseSessionResult {
  const [sessionId, setSessionId] = useState(initialId)
  const [snapshot, setSnapshot] = useState<SessionSnapshot | null>(null)
  const [mode, setMode] = useState<DataMode>('connecting')
  const [error, setError] = useState<string | null>(null)
  const [isDemoForced, setIsDemoForced] = useState(false)
  const trialsRef = useRef<Map<string, TrialWithGaze>>(new Map())
  const sessionRef = useRef<Session | null>(null)
  const unsubRef = useRef<Unsubscribe[]>([])

  const publish = useCallback(() => {
    if (!sessionRef.current) return
    const trials = [...trialsRef.current.values()].sort((a, b) => a.index - b.index)
    setSnapshot({ session: sessionRef.current, trials })
  }, [])

  const forceDemo = useCallback((module: SessionModule = 'visionPvt') => {
    setIsDemoForced(true)
    setError(null)
    setMode('demo')
    setSnapshot(buildDemoSnapshot(module))
  }, [])

  const exitDemo = useCallback(() => {
    setIsDemoForced(false)
  }, [])

  useEffect(() => {
    if (isDemoForced) return

    unsubRef.current.forEach((u) => u())
    unsubRef.current = []
    trialsRef.current = new Map()
    sessionRef.current = null
    setSnapshot(null)
    setError(null)

    if (!isFirebaseConfigured()) {
      setMode('demo')
      setSnapshot(buildDemoSnapshot())
      setError('Firebase env not configured — running demo session.')
      return
    }

    const db = getDb()
    if (!db) {
      setMode('demo')
      setSnapshot(buildDemoSnapshot())
      setError('Firestore unavailable — running demo session.')
      return
    }

    setMode('connecting')
    let cancelled = false
    let gotSession = false

    const fallbackTimer = window.setTimeout(() => {
      if (!cancelled && !gotSession) {
        setMode('demo')
        setSnapshot(buildDemoSnapshot())
        setError('No live session yet — showing canned demo data.')
      }
    }, 4000)

    const sessionUnsub = onSnapshot(
      doc(db, 'sessions', sessionId),
      (docSnap) => {
        if (cancelled) return
        if (!docSnap.exists()) {
          setError(`Session "${sessionId}" not found — demo mode available.`)
          if (!gotSession) {
            setMode('demo')
            setSnapshot(buildDemoSnapshot())
          }
          return
        }
        gotSession = true
        window.clearTimeout(fallbackTimer)
        sessionRef.current = parseSession(docSnap.id, docSnap.data() as Record<string, unknown>)
        setMode('live')
        setError(null)
        publish()
      },
      (err) => {
        if (cancelled) return
        setError(err.message)
        setMode('demo')
        setSnapshot(buildDemoSnapshot())
      },
    )

    const trialsUnsub = onSnapshot(
      query(collection(db, 'sessions', sessionId, 'trials'), orderBy('index', 'asc')),
      async (qs) => {
        if (cancelled) return
        const next = new Map<string, TrialWithGaze>()
        const loads: Promise<void>[] = []

        for (const d of qs.docs) {
          const trial = parseTrial(d.id, d.data() as Record<string, unknown>)
          const prev = trialsRef.current.get(d.id)
          if (prev?.gaze) {
            next.set(d.id, { ...trial, gaze: prev.gaze })
          } else {
            next.set(d.id, { ...trial, gaze: null })
            loads.push(
              loadGazeForTrial(sessionId, d.id).then((gaze) => {
                const current = next.get(d.id)
                if (current) next.set(d.id, { ...current, gaze })
              }),
            )
          }
        }

        await Promise.all(loads)
        if (cancelled) return
        trialsRef.current = next
        if (sessionRef.current) {
          setMode('live')
          publish()
        }
      },
      (err) => {
        if (cancelled) return
        setError(err.message)
      },
    )

    unsubRef.current = [sessionUnsub, trialsUnsub]

    return () => {
      cancelled = true
      window.clearTimeout(fallbackTimer)
      unsubRef.current.forEach((u) => u())
      unsubRef.current = []
    }
  }, [sessionId, isDemoForced, publish])

  return {
    mode,
    sessionId,
    setSessionId,
    snapshot,
    error,
    forceDemo,
    exitDemo,
    isDemoForced,
  }
}
