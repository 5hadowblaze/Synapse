/**
 * Reconstructing what the phone's fade detector was doing, from the 30 s epochs it wrote.
 *
 * The session doc carries the frozen baseline (mean + σ of the composite score) but not the
 * HR anchor, the arousal statistics, or which channels survived calibration — those live and
 * die inside `FocusFadeDetector`. Everything here is therefore an estimate off the epoch
 * stream, computed with the detector's own rules and labelled as an estimate wherever it is
 * shown. The device scores every 8 s; an epoch is a 30 s snapshot of that, so these numbers
 * land close to the phone's without ever being claimed as identical.
 */
import { FADE } from './focusFadeModel.js'
import type { FocusEpoch } from '../types/session'

export type ChannelKey = 'hr' | 'arousal' | 'motion'

/**
 * How a channel was contributing to the composite score.
 *
 * `dropped` and a contribution of zero are different claims: the detector renormalises the
 * remaining weights around a dropped channel, so it contributed nothing *and was not asked
 * to*, whereas a live channel reading 0.000 is actively reporting "no fade here".
 */
export type ChannelState = 'live' | 'intermittent' | 'absent' | 'belowNoiseFloor'

export interface FocusChannel {
  key: ChannelKey
  /** Weight the detector assigns when every channel is live. */
  nominalWeight: number
  /** Weight after renormalising across surviving channels — null when dropped out. */
  weight: number | null
  state: ChannelState
  /** Share of epochs that carry this channel's field. */
  coverage: number
  /** Why the channel is in this state, in the detector's own terms. */
  note: string
}

export interface FocusModel {
  /** Median-derived HR reference the drift term measures against (tracks downward). */
  hrAnchor: number | null
  arousalBaselineMean: number | null
  arousalBaselineStd: number | null
  /** Epochs treated as the calibration window (~the detector's 2.4 min). */
  baselineEpochs: number
  channels: Record<ChannelKey, FocusChannel>
  /** True when at least one channel dropped out, so the weights are not 45/40/15. */
  hasDroppedChannel: boolean
}

export interface ChannelTerm {
  /** 0…1 fade term, except HR which may sit slightly negative (down to hrFloorTerm). */
  term: number | null
  /** term × renormalised weight, or null when the channel is dropped or has no sample. */
  contribution: number | null
}

const EMPTY_TERM: ChannelTerm = { term: null, contribution: null }

function clamp(value: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, value))
}

function median(values: number[]): number | null {
  if (values.length === 0) return null
  const sorted = [...values].sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

function meanOf(values: number[]): number | null {
  if (values.length === 0) return null
  return values.reduce((a, b) => a + b, 0) / values.length
}

function stdevOf(values: number[]): number | null {
  if (values.length < 2) return null
  const m = meanOf(values) as number
  return Math.sqrt(values.reduce((a, v) => a + (v - m) ** 2, 0) / values.length)
}

/** The engine only scores while focusing or while a break suggestion is open. */
export function isScoredPhase(epoch: FocusEpoch): boolean {
  return epoch.phase === 'focus' || epoch.phase === 'fade'
}

/**
 * Epochs standing in for the detector's calibration window.
 *
 * The real window is 18 × 8 s and can be deferred while HR settles, so this is deliberately
 * a rough read: about 2.4 min of epochs, never more than a third of a short session.
 */
export function baselineEpochCount(epochs: FocusEpoch[]): number {
  const nominal = Math.ceil(
    (FADE.baselineSamples * FADE.sampleIntervalSeconds) / FADE.epochIntervalSeconds,
  )
  return Math.max(2, Math.min(nominal, Math.floor(epochs.length / 3)))
}

/**
 * HR anchor estimate: median of the calibration window, then tracked downward the way
 * `trackAnchorDownward` does, so a warm start does not leave the anchor stranded high.
 */
function estimateHrAnchor(epochs: FocusEpoch[], windowSize: number): number | null {
  const scored = epochs.filter(isScoredPhase)
  const hrs = scored.map((e) => e.hrBpm).filter((v): v is number => v != null)
  if (hrs.length === 0) return null

  let anchor = median(hrs.slice(0, windowSize))
  if (anchor == null) return null
  for (let i = windowSize; i < hrs.length; i++) {
    const rolling = median(hrs.slice(i - windowSize + 1, i + 1))
    if (rolling != null && rolling < anchor) anchor = rolling
  }
  return anchor
}

function channelState(
  values: Array<number | null>,
): { state: ChannelState; coverage: number } {
  const present = values.filter((v) => v != null).length
  const coverage = values.length === 0 ? 0 : present / values.length
  if (present === 0) return { state: 'absent', coverage }
  if (coverage < 0.9) return { state: 'intermittent', coverage }
  return { state: 'live', coverage }
}

export function buildFocusModel(epochs: FocusEpoch[]): FocusModel {
  const windowSize = baselineEpochCount(epochs)
  const window = epochs.slice(0, windowSize)

  const hr = channelState(epochs.map((e) => e.hrBpm))
  const arousal = channelState(epochs.map((e) => e.arousalIndex))
  const motion = channelState(epochs.map((e) => e.motionEnergy))

  const eyeWindow = window.map((e) => e.arousalIndex).filter((v): v is number => v != null)
  const arousalBaselineMean = meanOf(eyeWindow)
  const arousalBaselineStd = stdevOf(eyeWindow)

  // Same test the detector applies at calibration: too little spread in `eyeWide` and
  // z-scoring would just amplify blendshape jitter, so the channel is dropped instead.
  let arousalState = arousal.state
  if (
    arousalState !== 'absent' &&
    arousalBaselineStd != null &&
    arousalBaselineStd < FADE.arousalNoiseFloor
  ) {
    arousalState = 'belowNoiseFloor'
  }

  const dropped: Record<ChannelKey, boolean> = {
    hr: hr.state === 'absent',
    arousal: arousalState === 'absent' || arousalState === 'belowNoiseFloor',
    motion: motion.state === 'absent',
  }

  const liveWeight =
    (dropped.hr ? 0 : FADE.weights.hr) +
    (dropped.arousal ? 0 : FADE.weights.arousal) +
    (dropped.motion ? 0 : FADE.weights.motion)

  const renormalise = (nominal: number, isDropped: boolean): number | null => {
    if (isDropped || liveWeight <= 0) return null
    return nominal / liveWeight
  }

  const channels: Record<ChannelKey, FocusChannel> = {
    hr: {
      key: 'hr',
      nominalWeight: FADE.weights.hr,
      weight: renormalise(FADE.weights.hr, dropped.hr),
      state: hr.state,
      coverage: hr.coverage,
      note:
        hr.state === 'absent'
          ? 'no Watch heart rate reached the phone — channel dropped out'
          : hr.state === 'intermittent'
            ? 'Watch samples missing on some epochs'
            : `drift over ${FADE.hrSpanBpm} bpm above the session anchor`,
    },
    arousal: {
      key: 'arousal',
      nominalWeight: FADE.weights.arousal,
      weight: renormalise(FADE.weights.arousal, dropped.arousal),
      state: arousalState,
      coverage: arousal.coverage,
      note:
        arousalState === 'absent'
          ? 'face never tracked — channel dropped out'
          : arousalState === 'belowNoiseFloor'
            ? `baseline σ under the ${FADE.arousalNoiseFloor.toFixed(3)} noise floor — channel dropped out`
            : arousalState === 'intermittent'
              ? 'face lost on some epochs, so those samples score without it'
              : `σ below this face's own baseline, full scale at ${FADE.arousalSigmaSpan}σ`,
    },
    motion: {
      key: 'motion',
      nominalWeight: FADE.weights.motion,
      weight: renormalise(FADE.weights.motion, dropped.motion),
      state: motion.state,
      coverage: motion.coverage,
      note:
        motion.state === 'absent'
          ? 'no Watch stillness stream — channel dropped out'
          : motion.state === 'intermittent'
            ? 'stillness stream missing on some epochs'
            : 'wrist motion energy, 0…1',
    },
  }

  return {
    hrAnchor: estimateHrAnchor(epochs, windowSize),
    arousalBaselineMean: dropped.arousal ? null : arousalBaselineMean,
    arousalBaselineStd: dropped.arousal ? null : arousalBaselineStd,
    baselineEpochs: windowSize,
    channels,
    hasDroppedChannel: dropped.hr || dropped.arousal || dropped.motion,
  }
}

const NICE_STEPS = [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5, 0.6, 0.75, 1]

function niceCeil(value: number): number {
  return NICE_STEPS.find((step) => step >= value) ?? 1
}

export interface FadeScoreDomain {
  lo: number
  hi: number
  ticks: number[]
}

/**
 * Axis for the fade-score track.
 *
 * Every term now rests at 0, so a calm block lives between about 0 and 0.1 and only a real
 * fade approaches 1 — a fixed 0…1 axis would press the whole trace onto the floor. The HR
 * term is also allowed to read negative (down to `hrFloorTerm`, ≈5 bpm under the anchor), so
 * the axis has to make room below zero when a session actually goes there.
 */
export function fadeScoreDomain(
  epochs: FocusEpoch[],
  threshold: number | null,
): FadeScoreDomain {
  const values = epochs.map((e) => e.fadeScore).filter((v): v is number => v != null)
  const highest = Math.max(threshold ?? 0, ...values, 0.08)
  const lowest = Math.min(0, ...values)
  const hi = niceCeil(highest * 1.12)
  const lo = lowest < 0 ? -niceCeil(-lowest * 1.35) : 0

  // Labelled from the top down, dropping any tick that would crowd the one above it —
  // with a shallow negative floor, 0.00 and −0.05 would otherwise collide.
  const ticks: number[] = []
  for (const tick of [hi, (lo + hi) / 2, 0, lo]) {
    if (tick > hi || tick < lo) continue
    const previous = ticks[ticks.length - 1]
    if (previous != null && previous - tick < (hi - lo) * 0.12) continue
    ticks.push(tick)
  }
  return { lo, hi, ticks }
}

/** Rebuild one epoch's share of the composite score, channel by channel. */
export function epochTerms(
  epoch: FocusEpoch | null,
  model: FocusModel,
): Record<ChannelKey, ChannelTerm> {
  if (!epoch) return { hr: EMPTY_TERM, arousal: EMPTY_TERM, motion: EMPTY_TERM }

  const hrWeight = model.channels.hr.weight
  const hrTerm =
    hrWeight != null && epoch.hrBpm != null && model.hrAnchor != null
      ? clamp((epoch.hrBpm - model.hrAnchor) / FADE.hrSpanBpm, FADE.hrFloorTerm, 1)
      : null

  const arousalWeight = model.channels.arousal.weight
  const arousalTerm =
    arousalWeight != null &&
    epoch.arousalIndex != null &&
    model.arousalBaselineMean != null &&
    model.arousalBaselineStd != null &&
    model.arousalBaselineStd > 0
      ? clamp(
          (model.arousalBaselineMean - epoch.arousalIndex) /
            model.arousalBaselineStd /
            FADE.arousalSigmaSpan,
          0,
          1,
        )
      : null

  const motionWeight = model.channels.motion.weight
  const motionTerm =
    motionWeight != null && epoch.motionEnergy != null ? clamp(epoch.motionEnergy, 0, 1) : null

  const pair = (term: number | null, weight: number | null): ChannelTerm => ({
    term,
    contribution: term != null && weight != null ? term * weight : null,
  })

  return {
    hr: pair(hrTerm, hrWeight),
    arousal: pair(arousalTerm, arousalWeight),
    motion: pair(motionTerm, motionWeight),
  }
}
