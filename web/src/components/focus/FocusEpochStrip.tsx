import { fadeScoreDomain } from '../../data/focusAnalysis'
import type { FocusEpoch, FocusPhase } from '../../types/session'
import { elapsedLabel } from './focusTime'

interface FocusEpochStripProps {
  epochs: FocusEpoch[]
  activeIndex: number | null
  onSelect: (index: number) => void
  onHover: (index: number | null) => void
  threshold: number | null
}

const PHASE_BAR: Record<FocusPhase, string> = {
  focus: 'bg-signal/55',
  fade: 'bg-amber',
  break: 'bg-visual/70',
  done: 'bg-muted/50',
  idle: 'bg-muted/30',
  unknown: 'bg-muted/30',
}

export function FocusEpochStrip({
  epochs,
  activeIndex,
  onSelect,
  onHover,
  threshold,
}: FocusEpochStripProps) {
  if (epochs.length === 0) return null

  // Same session-relative scale as the timeline: a calm block sits just above zero, and the
  // HR term's negative allowance can put an epoch just below it.
  const domain = fadeScoreDomain(epochs, threshold)
  const span = domain.hi - domain.lo
  const zeroPct = ((0 - domain.lo) / span) * 100
  const last = epochs[epochs.length - 1]

  return (
    <section className="rounded-sm border border-line bg-panel/60 px-4 py-3">
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
        <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-muted">
          Epoch strip · fade score per 30 s
        </span>
        <span className="font-mono text-[10px] uppercase tracking-wider text-muted">
          {epochs.length} epochs · {elapsedLabel(last.index)} elapsed · scale{' '}
          {domain.lo.toFixed(2)}–{domain.hi.toFixed(2)}
        </span>
      </div>

      <div className="relative flex h-14 items-stretch gap-px" onPointerLeave={() => onHover(null)}>
        <div
          className="pointer-events-none absolute inset-x-0 border-t border-line"
          style={{ bottom: `${zeroPct}%` }}
        />
        {threshold != null && threshold <= domain.hi ? (
          <div
            className="pointer-events-none absolute inset-x-0 border-t border-dashed border-amber/45"
            style={{ bottom: `${((threshold - domain.lo) / span) * 100}%` }}
          />
        ) : null}
        {epochs.map((epoch) => {
          const score = epoch.fadeScore ?? 0
          const magnitude = Math.max(1.5, (Math.abs(score) / span) * 100)
          const active = epoch.index === activeIndex
          const negative = score < 0
          return (
            <button
              key={epoch.id}
              type="button"
              onClick={() => onSelect(epoch.index)}
              onPointerEnter={() => onHover(epoch.index)}
              title={`${elapsedLabel(epoch.index)} · ${epoch.phase} · fade ${
                epoch.fadeScore != null ? epoch.fadeScore.toFixed(3) : '—'
              }${epoch.hrBpm != null ? ` · ${Math.round(epoch.hrBpm)} bpm` : ''}`}
              className={`group relative min-w-[3px] flex-1 ${
                active ? 'bg-fog/10' : 'hover:bg-fog/5'
              }`}
            >
              <span
                className={`absolute inset-x-0 block ${PHASE_BAR[epoch.phase]} ${
                  active ? 'outline outline-1 outline-fog/70' : ''
                } ${negative ? 'opacity-60' : ''}`}
                style={
                  negative
                    ? { top: `${100 - zeroPct}%`, height: `${magnitude}%` }
                    : { bottom: `${zeroPct}%`, height: `${magnitude}%` }
                }
              />
            </button>
          )
        })}
      </div>

      <div className="mt-1.5 flex items-center justify-between font-mono text-[9.5px] tracking-wide text-muted">
        <span>{elapsedLabel(epochs[0].index)}</span>
        <span className="flex gap-3">
          <span className="text-signal">focus</span>
          <span className="text-amber">fade</span>
          <span className="text-visual">break</span>
        </span>
        <span>{elapsedLabel(last.index)}</span>
      </div>
    </section>
  )
}
