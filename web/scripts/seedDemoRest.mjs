/**
 * Seed via Firestore REST + gcloud user token (bypasses client security rules).
 * Usage: node scripts/seedDemoRest.mjs
 * Seeds focusDesk, visionPvt and kineticClock demo sessions.
 *
 * The focusDesk block comes from src/data/focusFadeModel.js — the same simulation the
 * offline demo runs — so the seeded session and /demo/focus cannot drift apart.
 */
import { execSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { simulateFocusDemo } from '../src/data/focusFadeModel.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const envPath = resolve(__dirname, '../.env')
const env = Object.fromEntries(
  readFileSync(envPath, 'utf8')
    .split('\n')
    .filter((l) => l && !l.startsWith('#') && l.includes('='))
    .map((l) => {
      const i = l.indexOf('=')
      return [l.slice(0, i), l.slice(i + 1)]
    }),
)

const PROJECT = env.VITE_FIREBASE_PROJECT_ID || 'synapse-clinical-hz'
const VISION_ID = env.VITE_VISION_SESSION_ID || env.VITE_DEFAULT_SESSION_ID || 'demo-vision-001'
const KINETIC_ID = env.VITE_KINETIC_SESSION_ID || 'demo-kinetic-001'
const FOCUS_ID = env.VITE_FOCUS_SESSION_ID || 'demo-focus-001'
const TOKEN = execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim()
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`

function rand(seed) {
  const x = Math.sin(seed * 12.9898) * 43758.5453
  return x - Math.floor(x)
}

function makeGaze(seed, fatigue, offsetX = 0, offsetY = 0) {
  const samples = []
  for (let i = 0; i < 60; i++) {
    const dt = -200 + i * (1000 / 59)
    const progress = Math.max(0, Math.min(1, (dt - 40) / 180))
    const ease = progress * progress * (3 - 2 * progress)
    const drift = fatigue * 0.08 * Math.sin(i * 0.35 + seed)
    const noise = (rand(seed + i) - 0.5) * 0.02
    samples.push({
      mapValue: {
        fields: {
          dt: { doubleValue: dt },
          x: { doubleValue: offsetX * ease + drift + noise },
          y: { doubleValue: offsetY * ease - drift * 0.6 + noise * 0.5 },
          z: { doubleValue: 0.9 - ease * 0.05 },
        },
      },
    })
  }
  return {
    fields: {
      t0Ms: { doubleValue: 0 },
      samples: { arrayValue: { values: samples } },
    },
  }
}

function nullValue() {
  return { nullValue: null }
}

async function patch(path, body) {
  const res = await fetch(`${BASE}/${path}`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    throw new Error(`${path}: ${res.status} ${await res.text()}`)
  }
}

async function seedVision(sessionId) {
  const baselineVisual = []
  const trials = []

  for (let i = 0; i < 24; i++) {
    const fatigue = i < 10 ? 0 : (i - 9) * 0.35
    const visualRtMs = 95 + rand(i * 3) * 35 + fatigue * 4 + (i === 14 ? 55 : 0)
    const targetOnsetMs = i * 2200 + 400
    const trial = {
      index: i,
      targetOnsetMs,
      saccadeOnsetMs: targetOnsetMs + visualRtMs,
      gazeSettleMs: targetOnsetMs + visualRtMs + 40 + rand(i) * 30,
      visualRtMs: Math.round(visualRtMs),
      arousalIndex: 0.55 + rand(i * 13) * 0.35 - fatigue * 0.04,
      flashX: (rand(i * 17) - 0.5) * 0.4,
      flashY: (rand(i * 19) - 0.5) * 0.4,
    }
    if (i < 10) baselineVisual.push(trial.visualRtMs)
    trials.push(trial)
  }

  const mean = baselineVisual.reduce((a, b) => a + b, 0) / baselineVisual.length
  const variance =
    baselineVisual.reduce((a, b) => a + (b - mean) ** 2, 0) / baselineVisual.length
  const std = Math.sqrt(variance)

  await patch(`sessions/${sessionId}`, {
    fields: {
      athleteId: { stringValue: 'athlete-demo' },
      module: { stringValue: 'visionPvt' },
      startedAt: { integerValue: String(Date.now() - 55_000) },
      status: { stringValue: 'active' },
      clockOffsetMs: { doubleValue: 0 },
      clockRttMs: { doubleValue: 0 },
      baselineGapMs: { doubleValue: Math.round(mean * 10) / 10 },
      baselineStdMs: { doubleValue: Math.round(std * 10) / 10 },
      breakPointTrial: { integerValue: '14' },
    },
  })

  for (const trial of trials) {
    const id = String(trial.index)
    const fatigue = trial.index < 10 ? 0 : (trial.index - 9) * 0.35
    await patch(`sessions/${sessionId}/trials/${id}`, {
      fields: {
        index: { integerValue: String(trial.index) },
        targetCell: nullValue(),
        targetOctant: nullValue(),
        detectedOctant: nullValue(),
        spatialMatch: nullValue(),
        targetOnsetMs: { doubleValue: trial.targetOnsetMs },
        saccadeOnsetMs: { doubleValue: trial.saccadeOnsetMs },
        gazeSettleMs: { doubleValue: trial.gazeSettleMs },
        strikeMs: nullValue(),
        visualRtMs: { doubleValue: trial.visualRtMs },
        motorRtMs: nullValue(),
        cognitiveMotorGapMs: nullValue(),
        peakG: nullValue(),
        arousalIndex: { doubleValue: trial.arousalIndex },
        valid: { booleanValue: true },
      },
    })
    await patch(
      `sessions/${sessionId}/trials/${id}/gaze/window`,
      makeGaze(trial.index + 1, fatigue, trial.flashX, trial.flashY),
    )
  }

  console.log(`Seeded sessions/${sessionId} (visionPvt) with ${trials.length} trials via REST`)
}

async function seedKinetic(sessionId) {
  const baselineMotor = []
  const trials = []

  for (let i = 0; i < 16; i++) {
    const fatigue = i < 8 ? 0 : (i - 7) * 0.4
    const targetOctant = i % 8
    const missRoll = rand(i * 23)
    const missRate = i < 8 ? 0.12 : 0.12 + fatigue * 0.08
    const spatialMatch = missRoll >= missRate
    const detectedOctant = spatialMatch
      ? targetOctant
      : (targetOctant + 1 + Math.floor(rand(i * 29) * 3)) % 8
    const motorRtMs = 210 + rand(i * 7) * 45 + fatigue * 18 + (i === 11 ? 90 : 0)
    const targetOnsetMs = i * 2400 + 500
    const trial = {
      index: i,
      targetOctant,
      detectedOctant,
      spatialMatch,
      targetOnsetMs,
      strikeMs: targetOnsetMs + motorRtMs,
      motorRtMs: Math.round(motorRtMs),
      peakG: 3.2 + rand(i * 5) * 2.4,
    }
    if (i < 8) baselineMotor.push(trial.motorRtMs)
    trials.push(trial)
  }

  const mean = baselineMotor.reduce((a, b) => a + b, 0) / baselineMotor.length
  const variance =
    baselineMotor.reduce((a, b) => a + (b - mean) ** 2, 0) / baselineMotor.length
  const std = Math.sqrt(variance)

  await patch(`sessions/${sessionId}`, {
    fields: {
      athleteId: { stringValue: 'athlete-demo' },
      module: { stringValue: 'kineticClock' },
      startedAt: { integerValue: String(Date.now() - 45_000) },
      status: { stringValue: 'active' },
      clockOffsetMs: { doubleValue: 12.4 },
      clockRttMs: { doubleValue: 38 },
      baselineGapMs: { doubleValue: Math.round(mean * 10) / 10 },
      baselineStdMs: { doubleValue: Math.round(std * 10) / 10 },
      breakPointTrial: { integerValue: '11' },
    },
  })

  for (const trial of trials) {
    const id = String(trial.index)
    await patch(`sessions/${sessionId}/trials/${id}`, {
      fields: {
        index: { integerValue: String(trial.index) },
        targetCell: nullValue(),
        targetOctant: { integerValue: String(trial.targetOctant) },
        detectedOctant: { integerValue: String(trial.detectedOctant) },
        spatialMatch: { booleanValue: trial.spatialMatch },
        targetOnsetMs: { doubleValue: trial.targetOnsetMs },
        saccadeOnsetMs: nullValue(),
        gazeSettleMs: nullValue(),
        strikeMs: { doubleValue: trial.strikeMs },
        visualRtMs: nullValue(),
        motorRtMs: { doubleValue: trial.motorRtMs },
        cognitiveMotorGapMs: nullValue(),
        peakG: { doubleValue: trial.peakG },
        arousalIndex: nullValue(),
        valid: { booleanValue: true },
      },
    })
  }

  console.log(`Seeded sessions/${sessionId} (kineticClock) with ${trials.length} trials via REST`)
}

// MARK: - focusDesk

/**
 * The Focus block is not authored here: `simulateFocusDemo` runs canned desk signals through
 * a mirror of the real `FocusFadeDetector`, so this seeds exactly the session `/demo/focus`
 * renders offline — same baseline, same debounce, same catches.
 */
async function seedFocus(sessionId) {
  const { epochs, summary } = simulateFocusDemo()

  await patch(`sessions/${sessionId}`, {
    fields: {
      athleteId: { stringValue: 'athlete-demo' },
      module: { stringValue: 'focusDesk' },
      startedAt: { integerValue: String(Date.now() - summary.totalSeconds * 1000) },
      status: { stringValue: 'complete' },
      clockOffsetMs: { doubleValue: 9.6 },
      clockRttMs: { doubleValue: 31 },
      // Raw window mean and σ, as SessionWriter.writeBaseline sends them (σ is not floored).
      baselineGapMs: { doubleValue: Math.round(summary.baselineMean * 1000) / 1000 },
      baselineStdMs: { doubleValue: Math.round(summary.baselineStd * 1000) / 1000 },
      breakPointTrial: nullValue(),
      lastHeartRateBpm: { doubleValue: Math.round(summary.lastHrBpm) },
      lastHeartRateSource: { stringValue: 'workoutBuilder' },
      focusFocusedSeconds: { doubleValue: summary.focusedSeconds },
      focusBreakSeconds: { doubleValue: summary.breakSeconds },
      focusFadeCount: { integerValue: String(summary.fadeCount) },
      focusMeanHrBpm: { doubleValue: Math.round(summary.meanHrBpm * 10) / 10 },
      focusExtendedOnce: { booleanValue: false },
      focusBaselineReady: { booleanValue: summary.baselineReady },
    },
  })

  for (const epoch of epochs) {
    await patch(`sessions/${sessionId}/epochs/${epoch.index}`, {
      fields: {
        index: { integerValue: String(epoch.index) },
        phase: { stringValue: epoch.phase },
        remainingMs: { doubleValue: epoch.remainingMs },
        fadeScore: { doubleValue: epoch.fadeScore },
        hrBpm: { doubleValue: epoch.hrBpm },
        arousalIndex: { doubleValue: epoch.arousalIndex },
        motionEnergy: { doubleValue: epoch.motionEnergy },
        fadeSuggested: { booleanValue: epoch.fadeSuggested },
      },
    })
  }

  const mmss = (s) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, '0')}`
  console.log(
    `Seeded sessions/${sessionId} (focusDesk): ${epochs.length} epochs, ` +
      `trip ${summary.threshold.toFixed(3)}, ${summary.fadeCount} catches at ` +
      `${summary.fadeFiredAt.map(mmss).join(' and ')} via REST`,
  )
}

/**
 * Older seeds ran longer, so a shorter re-seed would leave stale epochs on the tail of the
 * document and the dashboard would render a block that never happened.
 */
async function pruneEpochs(sessionId, keepCount) {
  for (let index = keepCount; index < keepCount + 12; index++) {
    await fetch(`${BASE}/sessions/${sessionId}/epochs/${index}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${TOKEN}` },
    })
  }
}

const focusEpochCount = simulateFocusDemo().epochs.length
await seedFocus(FOCUS_ID)
await pruneEpochs(FOCUS_ID, focusEpochCount)
await seedVision(VISION_ID)
await seedKinetic(KINETIC_ID)
