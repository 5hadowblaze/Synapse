/** Shared Firestore session schema — keep in sync with docs/SCHEMA.md */

export type SessionStatus = 'active' | 'complete'

/** Test-battery module written by the phone SessionWriter. */
export type SessionModule = 'kineticClock' | 'visionPvt'

export interface Session {
  id: string
  athleteId: string
  module: SessionModule
  startedAt: number
  status: SessionStatus
  clockOffsetMs: number
  clockRttMs: number
  baselineGapMs: number | null
  baselineStdMs: number | null
  breakPointTrial: number | null
}

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

export interface SessionSnapshot {
  session: Session
  trials: TrialWithGaze[]
}

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

export function isKineticModule(module: SessionModule): boolean {
  return module === 'kineticClock'
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
