import { useEffect, useRef } from 'react'
import { AlertBannerShell } from './motion/AlertBannerShell'

interface BreakPointBannerProps {
  breakPointTrial: number | null
}

function playAlertTone() {
  try {
    const ctx = new AudioContext()
    const now = ctx.currentTime
    const gain = ctx.createGain()
    gain.connect(ctx.destination)
    gain.gain.setValueAtTime(0.0001, now)
    gain.gain.exponentialRampToValueAtTime(0.22, now + 0.02)
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.55)

    ;[440, 554, 660].forEach((freq, i) => {
      const osc = ctx.createOscillator()
      osc.type = 'sawtooth'
      osc.frequency.value = freq
      osc.connect(gain)
      osc.start(now + i * 0.06)
      osc.stop(now + 0.55)
    })

    window.setTimeout(() => void ctx.close(), 800)
  } catch {
    // Audio may be blocked until user gesture — banner still shows.
  }
}

export function BreakPointBanner({ breakPointTrial }: BreakPointBannerProps) {
  const prevRef = useRef<number | null>(null)

  useEffect(() => {
    if (breakPointTrial != null && breakPointTrial !== prevRef.current) {
      playAlertTone()
    }
    prevRef.current = breakPointTrial
  }, [breakPointTrial])

  return (
    <AlertBannerShell
      show={breakPointTrial != null}
      bannerKey={
        breakPointTrial != null ? `bp-${breakPointTrial}` : 'bp-none'
      }
      tone="alert"
      role="alert"
    >
      <div className="mx-auto flex max-w-[1600px] items-center justify-between gap-4 px-5 py-3">
        <div className="font-display text-lg font-semibold tracking-wide uppercase md:text-2xl">
          Break-point detected — Trial {breakPointTrial}
        </div>
        <div className="hidden font-mono text-xs tracking-[0.15em] uppercase sm:block">
          Gap exceeded baseline + 2σ
        </div>
      </div>
    </AlertBannerShell>
  )
}
