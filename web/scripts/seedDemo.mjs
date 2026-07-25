/**
 * One-shot seed: node --env-file=.env scripts/seedDemo.mjs
 * Writes vision + kinetic demo sessions for live dashboard smoke tests.
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

const DEFAULT_ID = process.env.VITE_DEFAULT_SESSION_ID || 'demo-vision-001'
const VISION_ID = process.env.VITE_VISION_SESSION_ID || DEFAULT_ID
const KINETIC_ID = process.env.VITE_KINETIC_SESSION_ID || 'demo-kinetic-001'

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
      dt,
      x: offsetX * ease + drift + noise,
      y: offsetY * ease - drift * 0.6 + noise * 0.5,
      z: 0.9 - ease * 0.05,
    })
  }
  return { t0Ms: 0, samples }
}

const app = initializeApp(config)
const db = getFirestore(app)

async function seedVision(sessionId) {
  const baselineVisual = []
  const trials = []

  for (let i = 0; i < 24; i++) {
    const fatigue = i < 10 ? 0 : (i - 9) * 0.35
    const visualRtMs = 95 + rand(i * 3) * 35 + fatigue * 4 + (i === 14 ? 55 : 0)
    const targetOnsetMs = i * 2200 + 400
    const flashX = (rand(i * 17) - 0.5) * 0.4
    const flashY = (rand(i * 19) - 0.5) * 0.4
    const trial = {
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
    if (i < 10) baselineVisual.push(trial.visualRtMs)
    trials.push({ trial, gaze: makeGaze(i + 1, fatigue, flashX, flashY) })
  }

  const mean = baselineVisual.reduce((a, b) => a + b, 0) / baselineVisual.length
  const variance =
    baselineVisual.reduce((a, b) => a + (b - mean) ** 2, 0) / baselineVisual.length
  const std = Math.sqrt(variance)

  await setDoc(doc(db, 'sessions', sessionId), {
    athleteId: 'athlete-demo',
    module: 'visionPvt',
    startedAt: Date.now() - 55_000,
    status: 'active',
    clockOffsetMs: 0,
    clockRttMs: 0,
    baselineGapMs: Math.round(mean * 10) / 10,
    baselineStdMs: Math.round(std * 10) / 10,
    breakPointTrial: 14,
  })

  for (const { trial, gaze } of trials) {
    const id = String(trial.index)
    await setDoc(doc(db, 'sessions', sessionId, 'trials', id), trial)
    await setDoc(doc(db, 'sessions', sessionId, 'trials', id, 'gaze', 'window'), gaze)
  }

  console.log(`Seeded sessions/${sessionId} (visionPvt) with ${trials.length} trials`)
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
    if (i < 8) baselineMotor.push(trial.motorRtMs)
    trials.push(trial)
  }

  const mean = baselineMotor.reduce((a, b) => a + b, 0) / baselineMotor.length
  const variance =
    baselineMotor.reduce((a, b) => a + (b - mean) ** 2, 0) / baselineMotor.length
  const std = Math.sqrt(variance)

  await setDoc(doc(db, 'sessions', sessionId), {
    athleteId: 'athlete-demo',
    module: 'kineticClock',
    startedAt: Date.now() - 45_000,
    status: 'active',
    clockOffsetMs: 12.4,
    clockRttMs: 38,
    baselineGapMs: Math.round(mean * 10) / 10,
    baselineStdMs: Math.round(std * 10) / 10,
    breakPointTrial: 11,
  })

  for (const trial of trials) {
    await setDoc(doc(db, 'sessions', sessionId, 'trials', String(trial.index)), trial)
  }

  console.log(`Seeded sessions/${sessionId} (kineticClock) with ${trials.length} trials`)
}

await seedVision(VISION_ID)
await seedKinetic(KINETIC_ID)
process.exit(0)
