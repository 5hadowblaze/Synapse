interface MetricTileProps {
  label: string
  value: string
  unit?: string
  accent?: 'gap' | 'visual' | 'motor' | 'muted'
  sub?: string
}

const accentClass: Record<NonNullable<MetricTileProps['accent']>, string> = {
  gap: 'text-signal border-signal/30',
  visual: 'text-visual border-visual/30',
  motor: 'text-motor border-motor/30',
  muted: 'text-fog border-line',
}

export function MetricTile({
  label,
  value,
  unit = 'ms',
  accent = 'muted',
  sub,
}: MetricTileProps) {
  return (
    <div
      className={`rounded-sm border bg-panel/80 px-4 py-3 backdrop-blur-sm ${accentClass[accent]}`}
    >
      <div className="font-mono text-[10px] uppercase tracking-[0.22em] text-muted">
        {label}
      </div>
      <div className="mt-2 flex items-baseline gap-1.5">
        <span className="font-display text-3xl font-semibold tabular-nums tracking-tight">
          {value}
        </span>
        <span className="font-mono text-xs text-muted">{unit}</span>
      </div>
      {sub ? <div className="mt-1 font-mono text-[11px] text-muted">{sub}</div> : null}
    </div>
  )
}
