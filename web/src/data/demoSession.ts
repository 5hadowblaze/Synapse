import {
  type FocusEpoch,
  type FocusPhase,
  type GazeWindow,
  type Session,
  type SessionModule,
  type SessionSnapshot,
  type Trial,
  type TrialWithGaze,
} from '../types/session'
import { simulateFocusDemo } from './focusFadeModel.js'

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
    moduleRaw: module,
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
    lastHeartRateHkStart: null,
    lastHeartRateHkEnd: null,
    lastHeartRateReceivedAtMs: null,
    lastEpochIndex: null,
    lastEpochAtMs: null,
    lastEpochPhase: null,
    focusFocusedSeconds: null,
    focusBreakSeconds: null,
    focusFadeCount: null,
    focusMeanHrBpm: null,
    focusExtendedOnce: null,
    focusBaselineReady: null,
    pvtPreMedianMs: null,
    pvtPreLapses: null,
    pvtPreValidTrials: null,
    pvtPostMedianMs: null,
    pvtPostLapses: null,
    pvtPostValidTrials: null,
    pvtMedianDeltaMs: null,
    pvtPercentChange: null,
    pvtLapseDelta: null,
    pvtDirection: null,
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
    epochs: [],
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
    epochs: [],
  }
}

// MARK: - Focus desk demo

/**
 * Focus desk demo — a warm start the detector waits out, one long slide the detector catches,
 * a nudge the athlete waves off, then a second catch they take the break on.
 *
 * None of that is drawn by hand: `simulateFocusDemo` runs the canned desk signals through a
 * mirror of the real `FocusFadeDetector`, so the baseline, the trip line, the two-sample
 * debounce and the 90 s cooldown all land where the phone would put them. The seed script
 * runs the same simulation, so `/demo/focus` and the seeded session are the same block.
 */
export function buildFocusDemoSnapshot(): SessionSnapshot {
  const { epochs: rows, summary } = simulateFocusDemo()

  const epochs: FocusEpoch[] = rows.map((row) => ({
    id: String(row.index),
    index: row.index,
    phase: row.phase as FocusPhase,
    phaseRaw: row.phase,
    remainingMs: row.remainingMs,
    fadeScore: row.fadeScore,
    hrBpm: row.hrBpm,
    arousalIndex: row.arousalIndex,
    motionEnergy: row.motionEnergy,
    fadeSuggested: row.fadeSuggested,
  }))

  return {
    session: baseSession('demo-focus-001', 'focusDesk', {
      startedAt: Date.now() - summary.totalSeconds * 1000,
      status: 'complete',
      clockOffsetMs: 9.6,
      clockRttMs: 31,
      // Raw window mean and σ, exactly as SessionWriter.writeBaseline sends them.
      baselineGapMs: round3(summary.baselineMean),
      baselineStdMs: round3(summary.baselineStd),
      lastHeartRateBpm: summary.lastHrBpm == null ? null : Math.round(summary.lastHrBpm),
      lastHeartRateSource: 'workoutBuilder',
      focusFocusedSeconds: summary.focusedSeconds,
      focusBreakSeconds: summary.breakSeconds,
      focusFadeCount: summary.fadeCount,
      focusMeanHrBpm: Math.round(summary.meanHrBpm * 10) / 10,
      focusExtendedOnce: false,
      focusBaselineReady: summary.baselineReady,
    }),
    trials: [],
    epochs,
  }
}

function round3(value: number | null): number | null {
  return value == null ? null : Math.round(value * 1000) / 1000
}

/** Default canned session for pitch fallback — Focus is the lead product. */
export function buildDemoSnapshot(module: SessionModule = 'focusDesk'): SessionSnapshot {
  switch (module) {
    case 'kineticClock':
      return buildKineticDemoSnapshot()
    case 'visionPvt':
      return buildVisionDemoSnapshot()
    default:
      return buildFocusDemoSnapshot()
  }
}

export const DEMO_SESSION_JSON = buildDemoSnapshot()
