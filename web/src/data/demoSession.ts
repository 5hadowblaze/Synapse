import type {
  GazeWindow,
  Session,
  SessionModule,
  SessionSnapshot,
  Trial,
  TrialWithGaze,
} from '../types/session'

function rand(seed: number): number {
  const x = Math.sin(seed * 12.9898) * 43758.5453
  return x - Math.floor(x)
}

function makeGaze(seed: number, fatigue: number, offsetX = 0, offsetY = 0): GazeWindow {
  const samples = []
  for (let i = 0; i < 60; i++) {
    const dt = -200 + i * (1000 / 59)
    const progress = Math.max(0, Math.min(1, (dt - 40) / 180))
    const ease = progress * progress * (3 - 2 * progress)
    const drift = fatigue * 0.08 * Math.sin(i * 0.35 + seed)
    const noise = (rand(seed + i) - 0.5) * 0.02
    samples.push({
      dt,
      x: offsetX * ease + drift + noise,
      y: offsetY * ease - drift * 0.6 + noise * 0.5,
      z: 0.9 - ease * 0.05,
    })
  }
  return { t0Ms: 0, samples }
}

function baseSession(
  id: string,
  module: SessionModule,
  extras: Partial<Session>,
): Session {
  return {
    id,
    athleteId: 'athlete-demo',
    module,
    startedAt: Date.now() - 55_000,
    status: 'active',
    clockOffsetMs: 12.4,
    clockRttMs: 38,
    baselineGapMs: null,
    baselineStdMs: null,
    breakPointTrial: null,
    lastHeartRateBpm: 72,
    lastHeartRatePhoneMs: null,
    lastHeartRateWatchMs: null,
    lastHeartRateSource: 'demo',
    ...extras,
  }
}

/** Vision PVT demo — saccade / arousal, no punch board. */
export function buildVisionDemoSnapshot(): SessionSnapshot {
  const trials: TrialWithGaze[] = []
  const baselineVisual: number[] = []

  for (let i = 0; i < 24; i++) {
    const fatigue = i < 10 ? 0 : (i - 9) * 0.35
    const visualRtMs = 95 + rand(i * 3) * 35 + fatigue * 4 + (i === 14 ? 55 : 0)
    const targetOnsetMs = i * 2200 + 400
    const flashX = (rand(i * 17) - 0.5) * 0.4
    const flashY = (rand(i * 19) - 0.5) * 0.4
    const trial: Trial = {
      id: String(i),
      index: i,
      targetCell: null,
      targetOctant: null,
      detectedOctant: null,
      spatialMatch: null,
      targetOnsetMs,
      saccadeOnsetMs: targetOnsetMs + visualRtMs,
      gazeSettleMs: targetOnsetMs + visualRtMs + 40 + rand(i) * 30,
      strikeMs: null,
      visualRtMs: Math.round(visualRtMs),
      motorRtMs: null,
      cognitiveMotorGapMs: null,
      peakG: null,
      arousalIndex: 0.55 + rand(i * 13) * 0.35 - fatigue * 0.04,
      valid: true,
    }
    if (i < 10) baselineVisual.push(trial.visualRtMs!)
    trials.push({ ...trial, gaze: makeGaze(i + 1, fatigue, flashX, flashY) })
  }

  const mean = baselineVisual.reduce((a, b) => a + b, 0) / baselineVisual.length
  const variance =
    baselineVisual.reduce((a, b) => a + (b - mean) ** 2, 0) / baselineVisual.length
  const std = Math.sqrt(variance)

  return {
    session: baseSession('demo-vision-001', 'visionPvt', {
      baselineGapMs: Math.round(mean * 10) / 10,
      baselineStdMs: Math.round(std * 10) / 10,
      breakPointTrial: 14,
      clockOffsetMs: 0,
      clockRttMs: 0,
    }),
    trials,
  }
}

/** Kinetic Clock demo — motor RT + spatialMatch across 8 octants. */
export function buildKineticDemoSnapshot(): SessionSnapshot {
  const trials: TrialWithGaze[] = []
  const baselineMotor: number[] = []

  for (let i = 0; i < 16; i++) {
    const fatigue = i < 8 ? 0 : (i - 7) * 0.4
    const targetOctant = i % 8
    // ~85% spatial accuracy early, drops with fatigue
    const missRoll = rand(i * 23)
    const missRate = i < 8 ? 0.12 : 0.12 + fatigue * 0.08
    const spatialMatch = missRoll >= missRate
    const detectedOctant = spatialMatch
      ? targetOctant
      : (targetOctant + 1 + Math.floor(rand(i * 29) * 3)) % 8
    const motorRtMs = 210 + rand(i * 7) * 45 + fatigue * 18 + (i === 11 ? 90 : 0)
    const targetOnsetMs = i * 2400 + 500
    const trial: Trial = {
      id: String(i),
      index: i,
      targetCell: null,
      targetOctant,
      detectedOctant,
      spatialMatch,
      targetOnsetMs,
      saccadeOnsetMs: null,
      gazeSettleMs: null,
      strikeMs: targetOnsetMs + motorRtMs,
      visualRtMs: null,
      motorRtMs: Math.round(motorRtMs),
      cognitiveMotorGapMs: null,
      peakG: 3.2 + rand(i * 5) * 2.4,
      arousalIndex: null,
      valid: true,
    }
    if (i < 8) baselineMotor.push(trial.motorRtMs!)
    trials.push({ ...trial, gaze: null })
  }

  const mean = baselineMotor.reduce((a, b) => a + b, 0) / baselineMotor.length
  const variance =
    baselineMotor.reduce((a, b) => a + (b - mean) ** 2, 0) / baselineMotor.length
  const std = Math.sqrt(variance)

  return {
    session: baseSession('demo-kinetic-001', 'kineticClock', {
      baselineGapMs: Math.round(mean * 10) / 10,
      baselineStdMs: Math.round(std * 10) / 10,
      breakPointTrial: 11,
    }),
    trials,
  }
}

/** Default canned session for pitch fallback (Vision PVT). */
export function buildDemoSnapshot(module: SessionModule = 'visionPvt'): SessionSnapshot {
  return module === 'kineticClock'
    ? buildKineticDemoSnapshot()
    : buildVisionDemoSnapshot()
}

export const DEMO_SESSION_JSON = buildDemoSnapshot()
