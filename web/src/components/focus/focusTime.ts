import { FOCUS_EPOCH_INTERVAL_MS } from '../../types/session'

/**
 * mm:ss elapsed from block start.
 *
 * The epoch writer sleeps first and then emits, so epoch 0 is written 30 s in — index i
 * lands at (i + 1) × 30 s, not i × 30 s.
 */
export function elapsedLabel(index: number): string {
  const totalSeconds = Math.round(((index + 1) * FOCUS_EPOCH_INTERVAL_MS) / 1000)
  const m = Math.floor(totalSeconds / 60)
  const s = totalSeconds % 60
  return `${m}:${String(s).padStart(2, '0')}`
}
