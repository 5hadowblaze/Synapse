import { useEffect, useRef, useState } from 'react'

function prefersReducedMotion(): boolean {
  if (typeof window === 'undefined') return false
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/**
 * Animates a number toward `target`. Remounts from 0 when `replayKey` changes
 * (page / module switch). Soft-lerps on subsequent target changes (hover scrub).
 */
export function useCountUp(
  target: number | null,
  replayKey: string,
  options?: { decimals?: number; durationMs?: number },
): string | null {
  const decimals = options?.decimals ?? 0
  const durationMs = options?.durationMs ?? 700
  const [display, setDisplay] = useState<number | null>(target)
  const displayRef = useRef<number | null>(target)
  const rafRef = useRef<number | null>(null)
  const prevKey = useRef(replayKey)

  useEffect(() => {
    if (target == null || !Number.isFinite(target)) {
      displayRef.current = null
      setDisplay(null)
      return
    }

    if (prefersReducedMotion()) {
      displayRef.current = target
      setDisplay(target)
      prevKey.current = replayKey
      return
    }

    const keyChanged = prevKey.current !== replayKey
    prevKey.current = replayKey

    const from = keyChanged || displayRef.current == null ? 0 : displayRef.current
    const to = target
    const ms = keyChanged ? durationMs : Math.min(220, durationMs * 0.35)

    if (rafRef.current != null) cancelAnimationFrame(rafRef.current)
    const start = performance.now()

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / ms)
      // Strong ease-out
      const eased = 1 - Math.pow(1 - t, 3)
      const next = from + (to - from) * eased
      displayRef.current = next
      setDisplay(next)
      if (t < 1) rafRef.current = requestAnimationFrame(tick)
      else {
        displayRef.current = to
        setDisplay(to)
      }
    }

    rafRef.current = requestAnimationFrame(tick)
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current)
    }
  }, [target, replayKey, durationMs])

  if (display == null) return null
  return display.toFixed(decimals)
}
