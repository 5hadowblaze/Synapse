/** Shared Firestore session schema — keep in sync with docs/SCHEMA.md */

export type SessionStatus = 'active' | 'complete'

/** Module written by the phone SessionWriter (`module` on the session doc). */
export type SessionModule = 'kineticClock' | 'visionPvt' | 'focusDesk'

/**
 * A module we parsed off a session doc. `unknown` means the writer sent a value
 * this dashboard cannot render — surfaced to the operator instead of guessed at.
 */
export type ParsedModule = SessionModule | 'unknown'

export interface Session {
  id: string
  athleteId: string
  module: ParsedModule
  /** Raw `module` string as written, kept so an unknown value can be reported. */
  moduleRaw: string | null
  startedAt: number
  status: SessionStatus
  clockOffsetMs: number
  clockRttMs: number
  /** focusDesk reuses these for the fade-score baseline window. */
  baselineGapMs: number | null
  baselineStdMs: number | null
  breakPointTrial: number | null
  /** Discrete Watch workout HR — not frame-locked to camera. */
  lastHeartRateBpm: number | null
  /** Uptime-domain (Cristian) — fusion math only; do not use for wall freshness. */
  lastHeartRatePhoneMs: number | null
  lastHeartRateWatchMs: number | null
  lastHeartRateSource: string | null
  /** HealthKit sample window (timeIntervalSinceReferenceDate). */
  lastHeartRateHkStart: number | null
  lastHeartRateHkEnd: number | null
  /** Wall-clock ms when the phone wrote the latest HR sample. */
  lastHeartRateReceivedAtMs: number | null
  /** Denormalised from the latest focus epoch write. */
  lastEpochIndex: number | null
  lastEpochAtMs: number | null
  lastEpochPhase: string | null
  /** focusDesk recap (SessionWriter.writeFocusRecap) — null on lab modules. */
  focusFocusedSeconds: number | null
  focusBreakSeconds: number | null
  focusFadeCount: number | null
  focusMeanHrBpm: number | null
  focusExtendedOnce: boolean | null
  focusBaselineReady: boolean | null
  /**
   * Tap PVT-B bookend summaries (SessionWriter.writeTapPVT / writeTapPVTComparison).
   * Live Focus HUD does not render these; the pacing report may, with plain-language copy.
   */
  pvtPreMedianMs: number | null
  pvtPreLapses: number | null
  pvtPreValidTrials: number | null
  pvtPostMedianMs: number | null
  pvtPostLapses: number | null
  pvtPostValidTrials: number | null
  pvtMedianDeltaMs: number | null
  pvtPercentChange: number | null
  pvtLapseDelta: number | null
  pvtDirection: PvtDirection | null
}

/** Pre/post reaction-check direction written by the phone. */
export type PvtDirection = 'slower' | 'faster' | 'steady'

export interface Trial {
  id: string
  index: number
  /** Legacy 3×3 pad index; prefer targetOctant for kineticClock. */
  targetCell: number | null
  targetOctant: number | null
  detectedOctant: number | null
  spatialMatch: boolean | null
  targetOnsetMs: number
  saccadeOnsetMs: number | null
  gazeSettleMs: number | null
  strikeMs: number | null
  visualRtMs: number | null
  motorRtMs: number | null
  /** Fusion-only: strikeMs - saccadeOnsetMs */
  cognitiveMotorGapMs: number | null
  peakG: number | null
  arousalIndex: number | null
  valid: boolean
}

export interface GazeSample {
  /** ms relative to t0Ms */
  dt: number
  x: number
  y: number
  z: number
}

/** Packed gaze window for one trial (−200ms … +800ms around target) */
export interface GazeWindow {
  t0Ms: number
  samples: GazeSample[]
}

export interface TrialWithGaze extends Trial {
  gaze: GazeWindow | null
}

/** FocusEngine.phaseLabel lowercased, as written to `epochs/{index}.phase`. */
export type FocusPhase = 'idle' | 'focus' | 'fade' | 'break' | 'done' | 'unknown'

/** One `sessions/{id}/epochs/{index}` doc — emitted every 30s during a Focus block. */
export interface FocusEpoch {
  id: string
  index: number
  phase: FocusPhase
  phaseRaw: string | null
  remainingMs: number | null
  /**
   * Composite fade score. Every term rests at 0 and only approaches 1 when genuinely faded,
   * so a calm block sits near zero; the HR term's small negative allowance can take the
   * whole score slightly below zero when heart rate drops under the session anchor.
   */
  fadeScore: number | null
  hrBpm: number | null
  /** Raw `eyeWide` blendshape — the arousal channel z-scores it against its own baseline. */
  arousalIndex: number | null
  motionEnergy: number | null
  fadeSuggested: boolean
}

export interface SessionSnapshot {
  session: Session
  trials: TrialWithGaze[]
  epochs: FocusEpoch[]
}

/** FocusEngine writes one epoch every 30 s (startEpochWriter). */
export const FOCUS_EPOCH_INTERVAL_MS = 30_000

/** RollingBaseline sigma multiplier used by FocusFadeDetector. */
export const FOCUS_FADE_SIGMA = 2

/**
 * RollingBaseline's σ floor. `writeBaseline` sends the raw window σ, but the phone compares
 * against `mean + 2 · max(σ, 0.05)`, so the trip line here has to apply the same floor or it
 * would sit below the one that actually fired the nudges.
 */
export const FOCUS_FADE_MIN_STD = 0.05

export const OCTANT_LABELS = [
  '12',
  '1:30',
  '3',
  '4:30',
  '6',
  '7:30',
  '9',
  '10:30',
] as const

export function octantLabel(octant: number | null | undefined): string {
  if (octant == null || octant < 0 || octant > 7) return '—'
  return OCTANT_LABELS[octant] ?? '—'
}

export function isKineticModule(module: ParsedModule): boolean {
  return module === 'kineticClock'
}

export function isFocusModule(module: ParsedModule): boolean {
  return module === 'focusDesk'
}

const MODULE_LABELS: Record<ParsedModule, string> = {
  focusDesk: 'Focus Desk',
  kineticClock: 'Kinetic Clock',
  visionPvt: 'Vision PVT',
  unknown: 'Unknown module',
}

export function moduleLabel(module: ParsedModule): string {
  return MODULE_LABELS[module]
}

export function spatialAccuracyPct(trials: Trial[]): number | null {
  const scored = trials.filter((t) => t.valid && t.spatialMatch != null)
  if (scored.length === 0) return null
  const hits = scored.filter((t) => t.spatialMatch === true).length
  return (hits / scored.length) * 100
}

export function meanFinite(
  values: Array<number | null | undefined>,
): number | null {
  const nums = values.filter((v): v is number => typeof v === 'number' && Number.isFinite(v))
  if (nums.length === 0) return null
  return nums.reduce((a, b) => a + b, 0) / nums.length
}

/** Epoch elapsed time from the start of the block (index × 30 s). */
export function epochElapsedMs(epoch: FocusEpoch): number {
  return epoch.index * FOCUS_EPOCH_INTERVAL_MS
}

/**
 * Rising edges of `fadeSuggested` — one entry per "you're fading" catch.
 * The engine holds the flag until the block resumes, so only edges are events.
 * `focusFadeCount` on the recap stays authoritative for the session total; this
 * is what can be placed on a timeline.
 */
export function focusFadeEvents(epochs: FocusEpoch[]): FocusEpoch[] {
  const events: FocusEpoch[] = []
  let armed = true
  for (const epoch of epochs) {
    if (epoch.fadeSuggested && armed) {
      events.push(epoch)
      armed = false
    } else if (!epoch.fadeSuggested) {
      armed = true
    }
  }
  return events
}

/** Fade trip line: baseline mean + 2 · max(σ, minStd) of the fade-score window. */
export function focusFadeThreshold(session: Session): number | null {
  if (session.baselineGapMs == null || session.baselineStdMs == null) return null
  return (
    session.baselineGapMs +
    FOCUS_FADE_SIGMA * Math.max(session.baselineStdMs, FOCUS_FADE_MIN_STD)
  )
}

/** "24m 30s" / "45s" — matches FocusRecap.focusedMinutesLabel on iOS. */
export function formatDurationSeconds(seconds: number | null | undefined): string {
  if (seconds == null || !Number.isFinite(seconds)) return '—'
  const total = Math.max(0, Math.round(seconds))
  const m = Math.floor(total / 60)
  const s = total % 60
  return m > 0 ? `${m}m ${s}s` : `${s}s`
}
