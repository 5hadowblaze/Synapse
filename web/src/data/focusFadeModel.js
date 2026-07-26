/**
 * Executable mirror of the phone's fade detector, so demo sessions behave the way a real
 * block does rather than approximating the shape of one.
 *
 * Source of truth: `Sources/iOS/Session/FocusFadeDetector.swift` and `RollingBaseline.swift`.
 * Plain JS on purpose — `scripts/seedDemoRest.mjs` (node) and `src/data/demoSession.ts`
 * (vite) both import this file, so the offline demo and the seeded session cannot drift.
 *
 * Behaviour mirrored here, all of which shapes what the dashboard sees:
 * - every term rests at 0 and only approaches 1 when genuinely faded;
 * - the HR term is anchored on the median of the calibration window and may read negative
 *   down to `hrFloorTerm`;
 * - the arousal term is z-scored against that face's own `eyeWide` baseline, and drops out
 *   entirely when the calibration σ is below the noise floor;
 * - calibration is deferred while HR is still settling (capped at one extra window);
 * - the window is rescored once the final statistics exist, so baseline-period scores sit
 *   on the same scale as live ones;
 * - a fade needs two consecutive threshold exceedances, then a 90 s cooldown.
 */

export const FADE = {
  sampleIntervalSeconds: 8,
  /** ~2.4 min of 8 s samples. */
  baselineSamples: 18,
  cooldownSeconds: 90,
  /** RollingBaseline floor on σ — the trip line is never tighter than mean + 0.10. */
  minStd: 0.05,
  sigmaMultiplier: 2,
  samplesToFire: 2,
  hrSpanBpm: 20,
  /** How far below the anchor the HR term may read before flooring (≈5 bpm under). */
  hrFloorTerm: -0.25,
  /** σ(eyeWide) below which the arousal channel is quantisation noise, not signal. */
  arousalNoiseFloor: 0.01,
  arousalSigmaSpan: 2,
  /** HR gap between window halves above which the user is still settling. */
  stationaryBandBpm: 3,
  weights: { hr: 0.45, arousal: 0.4, motion: 0.15 },
  /** FocusEngine writes one epoch per 30 s, first one 30 s into the block. */
  epochIntervalSeconds: 30,
}

function mean(values) {
  if (values.length === 0) return null
  return values.reduce((a, b) => a + b, 0) / values.length
}

function median(values) {
  if (values.length === 0) return null
  const sorted = [...values].sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

/** Population σ, null under two samples — matches `FocusFadeDetector.standardDeviation`. */
function stdevOrNull(values) {
  if (values.length < 2) return null
  const m = /** @type {number} */ (mean(values))
  return Math.sqrt(values.reduce((a, v) => a + (v - m) ** 2, 0) / values.length)
}

function clamp(value, lo, hi) {
  return Math.min(hi, Math.max(lo, value))
}

/** Mirror of `RollingBaseline` — collects `capacity` samples, freezes, then only compares. */
class RollingBaseline {
  constructor(capacity) {
    this.capacity = capacity
    this.samples = []
    this.mean = null
    this.std = null
  }

  get isReady() {
    return this.mean != null && this.std != null
  }

  get threshold() {
    if (this.mean == null || this.std == null) return null
    return this.mean + FADE.sigmaMultiplier * Math.max(this.std, FADE.minStd)
  }

  reseed(values) {
    this.samples = values.slice(-this.capacity)
    if (this.samples.length === this.capacity) this.recompute()
    else {
      this.mean = null
      this.std = null
    }
  }

  ingest(value) {
    if (this.samples.length < this.capacity) {
      this.samples.push(value)
      if (this.samples.length === this.capacity) this.recompute()
      return false
    }
    const threshold = this.threshold
    return threshold == null ? false : value > threshold
  }

  recompute() {
    const m = /** @type {number} */ (mean(this.samples))
    this.mean = m
    this.std = Math.sqrt(
      this.samples.reduce((a, v) => a + (v - m) ** 2, 0) / this.samples.length,
    )
  }
}

/**
 * @typedef {Object} FadeSample
 * @property {number|null} [hrBpm]
 * @property {number|null} [eyeWide] Raw lid-aperture blendshape, written as `arousalIndex`.
 * @property {number|null} [motionEnergy]
 */

/** Mirror of `FocusFadeDetector`. Feed it samples; it answers when a fade fires. */
export class FadeDetector {
  constructor({ baselineSamples = FADE.baselineSamples } = {}) {
    this.baseline = new RollingBaseline(baselineSamples)
    this.lastScore = null
    this.fadeCount = 0
    this.lastFadeAt = null
    this.lastSampleAt = null
    this.pending = []
    this.isCalibrated = false
    this.deferredSamples = 0
    this.consecutiveExceedances = 0
    this.hrAnchor = null
    this.recentHr = []
    this.arousalBaselineMean = null
    this.arousalBaselineStd = null
    this.arousalBaselineSpread = null
    this.isArousalChannelActive = null
    this.calibratedAt = null
  }

  get isBaselineReady() {
    return this.baseline.isReady
  }

  get fadeThreshold() {
    return this.baseline.threshold
  }

  /** @param {number} now @param {FadeSample} sample @returns {boolean} fade fired */
  ingest(now, sample) {
    if (this.lastSampleAt != null && now - this.lastSampleAt < FADE.sampleIntervalSeconds) {
      return false
    }
    this.lastSampleAt = now

    if (!this.isCalibrated) {
      this.collect(sample, now)
      return false
    }

    this.trackAnchorDownward(sample.hrBpm)
    const score = this.compositeScore(sample)
    this.lastScore = score

    const exceeded = this.baseline.ingest(score)
    this.consecutiveExceedances = exceeded ? this.consecutiveExceedances + 1 : 0
    if (this.consecutiveExceedances < FADE.samplesToFire) return false
    if (this.lastFadeAt != null && now - this.lastFadeAt < FADE.cooldownSeconds) return false

    this.lastFadeAt = now
    this.fadeCount += 1
    this.consecutiveExceedances = 0
    return true
  }

  collect(sample, now) {
    this.pending.push(sample)
    if (this.pending.length > this.baseline.capacity) {
      this.pending = this.pending.slice(-this.baseline.capacity)
    }
    this.lastScore = this.compositeScore(sample)

    if (this.pending.length < this.baseline.capacity) return
    if (!this.isHrSettled() && this.deferredSamples < this.baseline.capacity) {
      this.deferredSamples += 1
      return
    }
    this.calibrate(now)
  }

  /** A warm start is not a baseline — hold while the window's HR is still trending down. */
  isHrSettled() {
    const hrs = this.pending.map((s) => s.hrBpm).filter((v) => v != null)
    if (hrs.length < 4) return true
    const half = Math.floor(hrs.length / 2)
    const early = median(hrs.slice(0, half))
    const late = median(hrs.slice(half))
    if (early == null || late == null) return true
    return early - late <= FADE.stationaryBandBpm
  }

  calibrate(now) {
    const hrValues = this.pending.map((s) => s.hrBpm).filter((v) => v != null)
    const hrMedian = median(hrValues)
    if (hrMedian != null) {
      this.hrAnchor = hrMedian
      this.recentHr = hrValues
    }

    const eyeValues = this.pending.map((s) => s.eyeWide).filter((v) => v != null)
    const spread = stdevOrNull(eyeValues)
    const eyeMean = mean(eyeValues)
    this.arousalBaselineSpread = spread
    if (spread != null && spread >= FADE.arousalNoiseFloor && eyeMean != null) {
      this.arousalBaselineMean = eyeMean
      this.arousalBaselineStd = spread
      this.isArousalChannelActive = true
    } else {
      this.arousalBaselineMean = null
      this.arousalBaselineStd = null
      this.isArousalChannelActive = false
    }

    // Rescore the window with the anchor and arousal statistics it produced, so the frozen
    // mean/σ sit on the same scale as every score compared against them later.
    this.baseline.reseed(this.pending.map((s) => this.compositeScore(s)))
    this.isCalibrated = true
    this.calibratedAt = now
    this.lastScore = this.baseline.samples[this.baseline.samples.length - 1] ?? null
  }

  /** The anchor only ever descends: restoring headroom, never claiming more fade. */
  trackAnchorDownward(hrBpm) {
    if (hrBpm == null || this.hrAnchor == null) return
    this.recentHr.push(hrBpm)
    if (this.recentHr.length > this.baseline.capacity) {
      this.recentHr = this.recentHr.slice(-this.baseline.capacity)
    }
    if (this.recentHr.length < this.baseline.capacity) return
    const rolling = median(this.recentHr)
    if (rolling != null && rolling < this.hrAnchor) this.hrAnchor = rolling
  }

  /** @param {FadeSample} sample */
  compositeScore(sample) {
    let total = 0
    let weightSum = 0

    if (sample.hrBpm != null && this.hrAnchor != null) {
      const term = clamp((sample.hrBpm - this.hrAnchor) / FADE.hrSpanBpm, FADE.hrFloorTerm, 1)
      total += FADE.weights.hr * term
      weightSum += FADE.weights.hr
    }

    if (
      this.isArousalChannelActive === true &&
      sample.eyeWide != null &&
      this.arousalBaselineMean != null &&
      this.arousalBaselineStd != null &&
      this.arousalBaselineStd > 0
    ) {
      const sigmasBelow = (this.arousalBaselineMean - sample.eyeWide) / this.arousalBaselineStd
      total += FADE.weights.arousal * clamp(sigmasBelow / FADE.arousalSigmaSpan, 0, 1)
      weightSum += FADE.weights.arousal
    }

    if (sample.motionEnergy != null) {
      total += FADE.weights.motion * clamp(sample.motionEnergy, 0, 1)
      weightSum += FADE.weights.motion
    }

    return total / Math.max(0.001, weightSum)
  }
}

// MARK: - Demo session

/** Linear-in-seconds keyframes with a smoothstep between them. */
function curve(keys, t) {
  if (t <= keys[0][0]) return keys[0][1]
  const last = keys[keys.length - 1]
  if (t >= last[0]) return last[1]
  for (let k = 1; k < keys.length; k++) {
    const [x1, y1] = keys[k]
    const [x0, y0] = keys[k - 1]
    if (t <= x1) {
      const p = (t - x0) / (x1 - x0)
      return y0 + (y1 - y0) * (p * p * (3 - 2 * p))
    }
  }
  return last[1]
}

/**
 * Bounded jitter in ±`amplitude`, uncorrelated between samples.
 *
 * Uncorrelated matters: the arousal term is z-scored against this same spread, so the
 * calibration σ and the jitter are the same size by construction and a single trough can
 * always look like a fade. What a trough cannot do is repeat — which is exactly the gap
 * the detector's two-sample debounce lives in.
 */
function jitter(t, salt, amplitude) {
  const x = Math.sin((t + 1) * 12.9898 + salt * 78.233) * 43758.5453
  return ((x - Math.floor(x)) * 2 - 1) * amplitude
}

/** Slow drift for heart rate, which does not step between samples the way a blendshape does. */
function drift(t, salt, amplitude) {
  return amplitude * (0.6 * Math.sin(t * 0.021 + salt) + 0.4 * Math.sin(t * 0.077 + salt * 1.7))
}

const HR_KEYS = [
  [0, 78],
  [50, 75.4],
  [110, 72.2],
  [170, 70.1],
  [250, 69.1],
  [340, 68.5],
  [430, 68.3],
  [510, 69.4],
  [560, 70.8],
  [600, 71.6],
  [640, 70.5],
  [690, 71.4],
  [730, 73.6],
  [760, 74.4],
  [820, 72.6],
  [900, 70.2],
  [1000, 68.6],
  [1080, 68.0],
]

const EYE_KEYS = [
  [0, 0.163],
  [200, 0.161],
  [380, 0.157],
  [470, 0.146],
  [545, 0.129],
  [600, 0.122],
  [625, 0.168],
  [665, 0.159],
  [710, 0.136],
  [745, 0.118],
  [770, 0.126],
  [820, 0.164],
  [900, 0.176],
  [1080, 0.181],
]

const MOTION_KEYS = [
  [0, 0.06],
  [200, 0.045],
  [430, 0.05],
  [560, 0.08],
  [600, 0.1],
  [625, 0.3],
  [670, 0.08],
  [730, 0.12],
  [755, 0.42],
  [820, 0.28],
  [900, 0.2],
  [1080, 0.17],
]

/**
 * Lid aperture moves more while someone is still settling in — adjusting the chair, looking
 * around the desk — than it does once they are working. The calibration window therefore
 * sees a wider `eyeWide` spread (σ ≈ 0.02, comfortably above the 0.010 noise floor) than the
 * quiet middle of the block, which is what gives a genuine droop room to read as several σ.
 */
const EYE_JITTER_KEYS = [
  [0, 0.035],
  [180, 0.031],
  [320, 0.013],
  [1080, 0.011],
]

/** Desk signals for the canned block: a warm start, one long slide, one recovery, one more. */
function demoSignals(t) {
  return {
    hrBpm: curve(HR_KEYS, t) + drift(t, 1.7, 0.55),
    eyeWide: Math.max(0.02, curve(EYE_KEYS, t) + jitter(t, 0.4, curve(EYE_JITTER_KEYS, t))),
    motionEnergy: Math.max(0.01, curve(MOTION_KEYS, t) + jitter(t, 2.9, 0.014)),
  }
}

const FOCUS_MINUTES = 15
const BREAK_MINUTES = 5
/** Seconds the athlete spends looking at the nudge before waving it off. */
const DISMISS_AFTER = 40
/** Seconds between the second nudge and actually standing up. */
const ACCEPT_AFTER = 38

function round(value, places) {
  const f = 10 ** places
  return Math.round(value * f) / f
}

/**
 * @typedef {Object} DemoEpoch
 * @property {number} index
 * @property {'focus'|'fade'|'break'|'done'|'idle'} phase
 * @property {number} remainingMs
 * @property {number|null} fadeScore
 * @property {number|null} hrBpm
 * @property {number|null} arousalIndex
 * @property {number|null} motionEnergy
 * @property {boolean} fadeSuggested
 */

/**
 * Run the canned desk block through the real detector, one 8 s sample at a time, and
 * collect the 30 s epochs the phone would have written.
 *
 * Nothing about the trace is authored directly: the catches land where the detector puts
 * them, the baseline is whatever the deferred window turns out to be, and the score during
 * the break is frozen because the engine stops scoring once you are on a break.
 */
export function simulateFocusDemo() {
  const focusSeconds = FOCUS_MINUTES * 60
  const breakSeconds = BREAK_MINUTES * 60
  const detector = new FadeDetector()

  /** @type {DemoEpoch[]} */
  const epochs = []
  /** @type {number[]} */
  const fadeFiredAt = []
  const hrSamples = []

  let phase = /** @type {'focus'|'fade'|'break'|'done'} */ ('focus')
  let fadeSuggested = false
  let suggestedAt = null
  let breakStartedAt = null
  let focusedSeconds = null
  let endsAt = Infinity
  let epochIndex = 0
  let nextEpochAt = FADE.epochIntervalSeconds
  let last = demoSignals(0)

  for (let t = 0; t <= 3600; t += 1) {
    last = demoSignals(t)
    if (t % 5 === 0) hrSamples.push(last.hrBpm)

    // The engine only scores while focusing or while a suggestion is open; on a break the
    // last score simply stands, which is why the trace goes flat there.
    if (phase === 'focus' || phase === 'fade') {
      const fired = detector.ingest(t, {
        hrBpm: last.hrBpm,
        eyeWide: last.eyeWide,
        motionEnergy: last.motionEnergy,
      })
      if (fired && phase === 'focus') {
        phase = 'fade'
        fadeSuggested = true
        suggestedAt = t
        fadeFiredAt.push(t)
      }
    }

    if (phase === 'fade' && suggestedAt != null) {
      const first = fadeFiredAt.length === 1
      if (first && t >= suggestedAt + DISMISS_AFTER) {
        phase = 'focus'
        fadeSuggested = false
        suggestedAt = null
      } else if (!first && t >= suggestedAt + ACCEPT_AFTER) {
        phase = 'break'
        fadeSuggested = false
        suggestedAt = null
        breakStartedAt = t
        focusedSeconds = t
        endsAt = t + breakSeconds
      }
    }

    // Nobody accepted a break, so the block runs its clock out.
    if (phase === 'focus' && t >= focusSeconds && breakStartedAt == null) {
      phase = 'break'
      breakStartedAt = t
      focusedSeconds = t
      endsAt = t + breakSeconds
    }

    if (t >= endsAt) break

    if (t === nextEpochAt) {
      const remainingSeconds =
        breakStartedAt != null
          ? Math.max(0, breakSeconds - (t - breakStartedAt))
          : Math.max(0, focusSeconds - t)
      epochs.push({
        index: epochIndex,
        phase,
        remainingMs: remainingSeconds * 1000,
        fadeScore: detector.lastScore == null ? null : round(detector.lastScore, 4),
        hrBpm: round(last.hrBpm, 1),
        arousalIndex: round(last.eyeWide, 4),
        motionEnergy: round(last.motionEnergy, 3),
        fadeSuggested,
      })
      epochIndex += 1
      nextEpochAt += FADE.epochIntervalSeconds
    }
  }

  const meanHrBpm = /** @type {number} */ (mean(hrSamples))

  return {
    epochs,
    summary: {
      /** Raw window mean/σ, exactly as `writeBaseline` sends them (σ is not floored). */
      baselineMean: detector.baseline.mean,
      baselineStd: detector.baseline.std,
      threshold: detector.fadeThreshold,
      fadeCount: detector.fadeCount,
      fadeFiredAt,
      meanHrBpm,
      lastHrBpm: epochs[epochs.length - 1]?.hrBpm ?? null,
      focusedSeconds: focusedSeconds ?? focusSeconds,
      breakSeconds: breakStartedAt == null ? 0 : breakSeconds,
      totalSeconds: (focusedSeconds ?? focusSeconds) + breakSeconds,
      hrAnchor: detector.hrAnchor,
      calibratedAt: detector.calibratedAt,
      deferredSamples: detector.deferredSamples,
      arousalActive: detector.isArousalChannelActive,
      arousalBaselineMean: detector.arousalBaselineMean,
      arousalBaselineSpread: detector.arousalBaselineSpread,
      baselineReady: detector.isBaselineReady,
    },
  }
}
