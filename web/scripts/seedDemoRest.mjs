/**
 * Seed via Firestore REST + gcloud user token (bypasses client security rules).
 * Usage: node scripts/seedDemoRest.mjs
 */
import { execSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

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
const SESSION_ID = env.VITE_DEFAULT_SESSION_ID || 'demo-session-001'
const TOKEN = execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim()
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`

function rand(seed) {
  const x = Math.sin(seed * 12.9898) * 43758.5453
  return x - Math.floor(x)
}

function makeGaze(targetCell, seed, fatigue) {
  const col = targetCell % 3
  const row = Math.floor(targetCell / 3)
  const tx = (col - 1) * 0.35
  const ty = (1 - row) * 0.35
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
          x: { doubleValue: tx * ease + drift + noise },
          y: { doubleValue: ty * ease - drift * 0.6 + noise * 0.5 },
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

const baselineGaps = []
const trials = []

for (let i = 0; i < 24; i++) {
  const fatigue = i < 10 ? 0 : (i - 9) * 0.35
  const visualRtMs = 95 + rand(i * 3) * 35 + fatigue * 4
  const gapBase = 118 + rand(i * 7) * 22
  const cognitiveMotorGapMs =
    i < 10
      ? gapBase
      : gapBase + fatigue * 28 + (i === 14 ? 95 : i > 14 ? 40 + (i - 14) * 12 : 0)
  const motorRtMs = visualRtMs + cognitiveMotorGapMs
  const targetCell = Math.floor(rand(i * 11) * 9)
  const targetOnsetMs = i * 2200 + 400
  const trial = {
    index: i,
    targetCell,
    targetOnsetMs,
    saccadeOnsetMs: targetOnsetMs + visualRtMs,
    gazeSettleMs: targetOnsetMs + visualRtMs + 40 + rand(i) * 30,
    strikeMs: targetOnsetMs + motorRtMs,
    visualRtMs: Math.round(visualRtMs),
    motorRtMs: Math.round(motorRtMs),
    cognitiveMotorGapMs: Math.round(cognitiveMotorGapMs),
    peakG: 3.2 + rand(i * 5) * 2.4,
    arousalIndex: 0.55 + rand(i * 13) * 0.35 - fatigue * 0.04,
    valid: true,
  }
  if (i < 10) baselineGaps.push(trial.cognitiveMotorGapMs)
  trials.push(trial)
}

const mean = baselineGaps.reduce((a, b) => a + b, 0) / baselineGaps.length
const variance = baselineGaps.reduce((a, b) => a + (b - mean) ** 2, 0) / baselineGaps.length
const std = Math.sqrt(variance)

await patch(`sessions/${SESSION_ID}`, {
  fields: {
    athleteId: { stringValue: 'athlete-demo' },
    startedAt: { integerValue: String(Date.now() - 55_000) },
    status: { stringValue: 'active' },
    clockOffsetMs: { doubleValue: 12.4 },
    clockRttMs: { doubleValue: 38 },
    baselineGapMs: { doubleValue: Math.round(mean * 10) / 10 },
    baselineStdMs: { doubleValue: Math.round(std * 10) / 10 },
    breakPointTrial: { integerValue: '14' },
  },
})

for (const trial of trials) {
  const id = String(trial.index)
  const fatigue = trial.index < 10 ? 0 : (trial.index - 9) * 0.35
  await patch(`sessions/${SESSION_ID}/trials/${id}`, {
    fields: {
      index: { integerValue: String(trial.index) },
      targetCell: { integerValue: String(trial.targetCell) },
      targetOnsetMs: { doubleValue: trial.targetOnsetMs },
      saccadeOnsetMs: { doubleValue: trial.saccadeOnsetMs },
      gazeSettleMs: { doubleValue: trial.gazeSettleMs },
      strikeMs: { doubleValue: trial.strikeMs },
      visualRtMs: { doubleValue: trial.visualRtMs },
      motorRtMs: { doubleValue: trial.motorRtMs },
      cognitiveMotorGapMs: { doubleValue: trial.cognitiveMotorGapMs },
      peakG: { doubleValue: trial.peakG },
      arousalIndex: { doubleValue: trial.arousalIndex },
      valid: { booleanValue: true },
    },
  })
  await patch(
    `sessions/${SESSION_ID}/trials/${id}/gaze/window`,
    makeGaze(trial.targetCell, trial.index + 1, fatigue),
  )
}

console.log(`Seeded sessions/${SESSION_ID} with ${trials.length} trials via REST`)
