import { useId } from 'react'
import {
  epochTerms,
  type ChannelKey,
  type ChannelState,
  type FocusModel,
} from '../../data/focusAnalysis'
import type { FocusEpoch } from '../../types/session'

interface FocusSignalPanelProps {
  epochs: FocusEpoch[]
  epoch: FocusEpoch | null
  model: FocusModel
}

const CHANNEL_COLOR: Record<ChannelKey, string> = {
  hr: '#ff7a8a',
  arousal: '#4da3ff',
  motion: '#f0b429',
}

function isDropped(state: ChannelState): boolean {
  return state === 'absent' || state === 'belowNoiseFloor'
}

function Sparkline({
  values,
  color,
  activeIndex,
}: {
  values: Array<number | null>
  color: string
  activeIndex: number | null
}) {
  const uid = useId().replace(/:/g, '')
  const nums = values.filter((v): v is number => v != null)
  if (nums.length < 2) {
    return <div className="h-full min-h-[28px] w-full rounded-sm border border-line/60 bg-ink/40" />
  }
  const lo = Math.min(...nums)
  const hi = Math.max(...nums)
  const span = Math.max(1e-6, hi - lo)
  const w = 240
  const h = 34
  const x = (i: number) => (i / Math.max(1, values.length - 1)) * w
  const y = (v: number) => h - 3 - ((v - lo) / span) * (h - 8)

  let d = ''
  let pen = false
  values.forEach((v, i) => {
    if (v == null) {
      pen = false
      return
    }
    d += `${pen ? 'L' : 'M'}${x(i).toFixed(1)} ${y(v).toFixed(1)} `
    pen = true
  })

  const activeValue =
    activeIndex != null && activeIndex >= 0 && activeIndex < values.length
      ? values[activeIndex]
      : null

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="h-full w-full" preserveAspectRatio="none">
      <defs>
        <linearGradient id={`spark-${uid}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={color} stopOpacity="0.28" />
          <stop offset="1" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={`${d}L${w} ${h} L0 ${h} Z`} fill={`url(#spark-${uid})`} />
      <path d={d.trim()} fill="none" stroke={color} strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
      {activeValue != null && activeIndex != null ? (
        <line
          x1={x(activeIndex)}
          x2={x(activeIndex)}
          y1="0"
          y2={h}
          stroke={color}
          strokeOpacity="0.5"
          vectorEffect="non-scaling-stroke"
        />
      ) : null}
    </svg>
  )
}

/** A dropped channel gets a struck-through track, never a flat line at zero. */
function DroppedTrack({ uid }: { uid: string }) {
  return (
    <svg viewBox="0 0 240 34" className="h-full w-full" preserveAspectRatio="none">
      <defs>
        <pattern
          id={`hatch-${uid}`}
          width="7"
          height="7"
          patternUnits="userSpaceOnUse"
          patternTransform="rotate(45)"
        >
          <line x1="0" y1="0" x2="0" y2="7" stroke="#1e2d3d" strokeWidth="2" />
        </pattern>
      </defs>
      <rect x="0" y="1" width="240" height="32" fill={`url(#hatch-${uid})`} stroke="#16222f" />
    </svg>
  )
}

export function FocusSignalPanel({ epochs, epoch, model }: FocusSignalPanelProps) {
  const uid = useId().replace(/:/g, '')
  const activePos = epoch ? epochs.findIndex((e) => e.index === epoch.index) : -1
  const activeIndex = activePos >= 0 ? activePos : null
  const terms = epochTerms(epoch, model)

  const anchorLabel = model.hrAnchor != null ? Math.round(model.hrAnchor) : null
  const sigmaLabel =
    model.arousalBaselineStd != null ? model.arousalBaselineStd.toFixed(3) : null

  const rows = [
    {
      key: 'hr' as const,
      label: 'HR drift',
      field: 'hrBpm',
      values: epochs.map((e) => e.hrBpm),
      readout:
        epoch?.hrBpm != null
          ? `${epoch.hrBpm.toFixed(0)} bpm${
              anchorLabel != null
                ? ` · ${epoch.hrBpm - (model.hrAnchor ?? 0) >= 0 ? '+' : ''}${(
                    epoch.hrBpm - (model.hrAnchor ?? 0)
                  ).toFixed(1)} vs ${anchorLabel}`
                : ''
            }`
          : 'no sample this epoch',
    },
    {
      key: 'arousal' as const,
      label: 'Lid aperture (σ below baseline)',
      field: 'arousalIndex',
      values: epochs.map((e) => e.arousalIndex),
      readout:
        epoch?.arousalIndex != null
          ? `${epoch.arousalIndex.toFixed(3)}${sigmaLabel ? ` · σ ${sigmaLabel}` : ''}`
          : 'face not tracked',
    },
    {
      key: 'motion' as const,
      label: 'Motion energy',
      field: 'motionEnergy',
      values: epochs.map((e) => e.motionEnergy),
      readout: epoch?.motionEnergy != null ? epoch.motionEnergy.toFixed(2) : 'no sample this epoch',
    },
  ]

  const weightSummary = (['hr', 'arousal', 'motion'] as const)
    .map((key) => {
      const weight = model.channels[key].weight
      return weight == null ? '—' : Math.round(weight * 100)
    })
    .join(' / ')

  return (
    <div className="flex h-full flex-col rounded-sm border border-line bg-panel/70">
      <div className="flex items-center justify-between gap-3 border-b border-line px-4 py-2">
        <h2 className="font-display text-sm font-medium tracking-wide text-fog">
          Fade score inputs
        </h2>
        <span
          className={`font-mono text-[10px] uppercase tracking-wider ${
            model.hasDroppedChannel ? 'text-amber' : 'text-muted'
          }`}
          title={
            model.hasDroppedChannel
              ? 'A channel dropped out, so the detector renormalised the weights across the rest'
              : 'Nominal weights — every channel live'
          }
        >
          weighted {weightSummary}
          {model.hasDroppedChannel ? ' · renormalised' : ''}
        </span>
      </div>

      <div className="flex flex-1 flex-col divide-y divide-line/60">
        {rows.map((row) => {
          const channel = model.channels[row.key]
          const dropped = isDropped(channel.state)
          const term = terms[row.key]
          return (
            <div key={row.key} className="flex min-h-[76px] flex-1 flex-col px-4 py-2.5">
              <div className="flex items-baseline justify-between gap-3">
                <span className={`text-[13px] ${dropped ? 'text-muted' : 'text-fog'}`}>
                  {row.label}{' '}
                  <span className="font-mono text-[9.5px] tracking-wide text-muted">
                    {row.field}
                  </span>
                </span>
                {dropped ? (
                  <span className="rounded-sm border border-amber/45 px-1.5 py-0.5 font-mono text-[9.5px] uppercase tracking-wider text-amber">
                    dropped out
                  </span>
                ) : (
                  <span className="font-mono text-[12px] tabular-nums text-fog">{row.readout}</span>
                )}
              </div>

              <div className="mt-1 flex min-h-0 flex-1 items-stretch gap-3">
                <div className="min-h-[28px] min-w-0 flex-1">
                  {dropped ? (
                    <DroppedTrack uid={`${uid}-${row.key}`} />
                  ) : (
                    <Sparkline
                      values={row.values}
                      color={CHANNEL_COLOR[row.key]}
                      activeIndex={activeIndex}
                    />
                  )}
                </div>
                <div className="flex w-[74px] shrink-0 flex-col justify-center text-right">
                  <div
                    className={`font-mono text-[12px] tabular-nums ${
                      dropped ? 'text-muted' : 'text-fog'
                    }`}
                  >
                    {dropped
                      ? 'no term'
                      : term.contribution != null
                        ? term.contribution.toFixed(3)
                        : '—'}
                  </div>
                  <div className="font-mono text-[9.5px] tracking-wide text-muted">
                    {dropped ? (
                      <span className="line-through">w {channel.nominalWeight.toFixed(2)}</span>
                    ) : (
                      `w ${(channel.weight ?? channel.nominalWeight).toFixed(2)}`
                    )}
                  </div>
                </div>
              </div>

              <p
                className={`mt-1 font-mono text-[9.5px] leading-relaxed ${
                  dropped ? 'text-amber/80' : 'text-muted'
                }`}
              >
                {channel.note}
              </p>
            </div>
          )
        })}
      </div>

      <p className="border-t border-line px-4 py-1.5 font-mono text-[9.5px] leading-relaxed text-muted">
        Terms reconstructed from each epoch&apos;s inputs — the phone scores every 8 s, an epoch
        is a 30 s snapshot of that. Anchor and baseline σ estimated from the first{' '}
        {model.baselineEpochs} epochs.
      </p>
    </div>
  )
}
