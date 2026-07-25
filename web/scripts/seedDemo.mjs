/**
 * One-shot seed: node --env-file=.env scripts/seedDemo.mjs
 * Writes sessions/demo-session-001 + trials (+ gaze) for live dashboard smoke tests.
 */
import { initializeApp } from 'firebase/app'
import { doc, getFirestore, setDoc } from 'firebase/firestore'

const config = {
  apiKey: process.env.VITE_FIREBASE_API_KEY,
  authDomain: process.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: process.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.VITE_FIREBASE_APP_ID,
}

const SESSION_ID = process.env.VITE_DEFAULT_SESSION_ID || 'demo-session-001'

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
      dt,
      x: tx * ease + drift + noise,
      y: ty * ease - drift * 0.6 + noise * 0.5,
      z: 0.9 - ease * 0.05,
    })
  }
  return { t0Ms: 0, samples }
}

const app = initializeApp(config)
const db = getFirestore(app)

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
  trials.push({ trial, gaze: makeGaze(targetCell, i + 1, fatigue) })
}

const mean = baselineGaps.reduce((a, b) => a + b, 0) / baselineGaps.length
const variance = baselineGaps.reduce((a, b) => a + (b - mean) ** 2, 0) / baselineGaps.length
const std = Math.sqrt(variance)

await setDoc(doc(db, 'sessions', SESSION_ID), {
  athleteId: 'athlete-demo',
  startedAt: Date.now() - 55_000,
  status: 'active',
  clockOffsetMs: 12.4,
  clockRttMs: 38,
  baselineGapMs: Math.round(mean * 10) / 10,
  baselineStdMs: Math.round(std * 10) / 10,
  breakPointTrial: 14,
})

for (const { trial, gaze } of trials) {
  const id = String(trial.index)
  await setDoc(doc(db, 'sessions', SESSION_ID, 'trials', id), trial)
  await setDoc(doc(db, 'sessions', SESSION_ID, 'trials', id, 'gaze', 'window'), gaze)
}

console.log(`Seeded sessions/${SESSION_ID} with ${trials.length} trials`)
process.exit(0)
