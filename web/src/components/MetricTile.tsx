import { motion } from 'motion/react'
import { useCountUp } from '../hooks/useCountUp'
import { duration, easeOut } from '../motion/tokens'

interface MetricTileProps {
  label: string
  value: string
  unit?: string
  accent?: 'gap' | 'visual' | 'motor' | 'muted' | 'pulse' | 'alert'
  sub?: string
  live?: boolean
  /** Remount count-up when this changes (session / module / mode). */
  countKey?: string
}

const accentClass: Record<NonNullable<MetricTileProps['accent']>, string> = {
  gap: 'text-signal border-signal/30',
  visual: 'text-visual border-visual/30',
  motor: 'text-motor border-motor/30',
  muted: 'text-fog border-line',
  pulse: 'text-pulse border-pulse/30',
  alert: 'text-alert border-alert/30',
}

/** Parse "12.340", "72", "12%" — skip durations / em-dashes. */
function parseNumeric(value: string): { n: number; decimals: number } | null {
  const trimmed = value.trim()
  if (!trimmed || trimmed === '—' || /[a-zA-Z:]/.test(trimmed.replace(/%$/, ''))) {
    return null
  }
  const raw = trimmed.endsWith('%') ? trimmed.slice(0, -1) : trimmed
  const n = Number(raw)
  if (!Number.isFinite(n)) return null
  const dot = raw.indexOf('.')
  const decimals = dot >= 0 ? raw.length - dot - 1 : 0
  return { n, decimals: Math.min(3, decimals) }
}

export function MetricTile({
  label,
  value,
  unit = 'ms',
  accent = 'muted',
  sub,
  live = false,
  countKey = value,
}: MetricTileProps) {
  const parsed = parseNumeric(value)
  const counted = useCountUp(parsed?.n ?? null, countKey, {
    decimals: parsed?.decimals ?? 0,
    durationMs: duration.count * 1000,
  })
  const shown =
    parsed && counted != null
      ? value.trim().endsWith('%')
        ? counted
        : counted
      : value

  return (
    <motion.div
      className={`surface-lift rounded-sm border bg-panel/80 px-4 py-3 backdrop-blur-sm ${accentClass[accent]}`}
      whileHover={{ y: -2 }}
      whileTap={{ scale: 0.985 }}
      transition={{ duration: duration.hover, ease: easeOut }}
    >
      <div className="flex items-center justify-between gap-2 font-mono text-[10px] uppercase tracking-[0.22em] text-muted">
        <span>{label}</span>
        {live ? (
          <span className="text-signal" title="Receiving fresh samples">
            ● Live
          </span>
        ) : null}
      </div>
      <div className="mt-2 flex items-baseline gap-1.5">
        <span className="font-display text-3xl font-semibold tabular-nums tracking-tight">
          {shown}
        </span>
        <span className="font-mono text-xs text-muted">{unit}</span>
      </div>
      {sub ? <div className="mt-1 font-mono text-[11px] text-muted">{sub}</div> : null}
    </motion.div>
  )
}
