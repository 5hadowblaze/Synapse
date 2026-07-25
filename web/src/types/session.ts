/** Shared Firestore session schema — keep in sync with docs/SCHEMA.md */

export type SessionStatus = 'active' | 'complete'

export interface Session {
  id: string
  athleteId: string
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
  targetCell: number
  targetOnsetMs: number
  saccadeOnsetMs: number
  gazeSettleMs: number
  strikeMs: number
  visualRtMs: number
  motorRtMs: number
  /** Hero metric: strikeMs - saccadeOnsetMs */
  cognitiveMotorGapMs: number
  peakG: number
  arousalIndex: number
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
