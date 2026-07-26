import { AlertBannerShell } from '../motion/AlertBannerShell'
import type { FocusEpoch } from '../../types/session'
import { elapsedLabel } from './focusTime'

interface FocusFadeBannerProps {
  epoch: FocusEpoch | null
  hrAnchor: number | null
}

/** Live "we caught you fading" strip — the nudge, not an alarm. */
export function FocusFadeBanner({ epoch, hrAnchor }: FocusFadeBannerProps) {
  const drift =
    epoch != null && epoch.hrBpm != null && hrAnchor != null
      ? epoch.hrBpm - hrAnchor
      : null

  return (
    <AlertBannerShell
      show={epoch != null}
      bannerKey={epoch ? `fade-${epoch.index}` : 'fade-none'}
      tone="amber"
      role="status"
    >
      <div className="mx-auto flex max-w-[1600px] items-center justify-between gap-4 px-5 py-3">
        <div className="font-display text-lg font-semibold uppercase tracking-wide md:text-2xl">
          Fade caught — break suggested
          {epoch ? ` at ${elapsedLabel(epoch.index)}` : ''}
        </div>
        <div className="hidden font-mono text-xs uppercase tracking-[0.15em] sm:block">
          {epoch?.fadeScore != null ? `fade ${epoch.fadeScore.toFixed(2)}` : 'fade score pending'}
          {drift != null ? ` · HR ${drift >= 0 ? '+' : ''}${drift.toFixed(0)} bpm` : ''}
        </div>
      </div>
    </AlertBannerShell>
  )
}
