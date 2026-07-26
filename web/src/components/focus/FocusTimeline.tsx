import { useId, useMemo, useRef, type PointerEvent as ReactPointerEvent } from 'react'
import {
  fadeScoreDomain,
  isScoredPhase,
  type FocusModel,
} from '../../data/focusAnalysis'
import {
  focusFadeEvents,
  focusFadeThreshold,
  type FocusEpoch,
  type FocusPhase,
  type Session,
} from '../../types/session'
import { elapsedLabel } from './focusTime'

interface FocusTimelineProps {
  epochs: FocusEpoch[]
  session: Session
  model: FocusModel
  activeIndex: number | null
  onHover: (index: number | null) => void
  onSelect: (index: number) => void
}

const VB_W = 1000
const VB_H = 400
const PAD_L = 56
const PAD_R = 22
const HR_TOP = 26
const HR_BOT = 186
const FADE_TOP = 218
const FADE_BOT = 330
const RIBBON_TOP = 344
const RIBBON_H = 11
const AXIS_Y = 374

const PHASE_FILL: Record<FocusPhase, string> = {
  focus: 'rgba(61,255,196,0.14)',
  fade: 'rgba(240,180,41,0.42)',
  break: 'rgba(77,163,255,0.30)',
  done: 'rgba(107,130,153,0.22)',
  idle: 'rgba(107,130,153,0.12)',
  unknown: 'rgba(107,130,153,0.12)',
}

const PHASE_TEXT: Record<FocusPhase, string> = {
  focus: '#3dffc4',
  fade: '#f0b429',
  break: '#4da3ff',
  done: '#6b8299',
  idle: '#6b8299',
  unknown: '#6b8299',
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v))
}

type Pt = { x: number; y: number } | null

function linePath(points: Pt[]): string {
  let d = ''
  let pen = false
  for (const p of points) {
    if (!p) {
      pen = false
      continue
    }
    d += `${pen ? 'L' : 'M'}${p.x.toFixed(2)} ${p.y.toFixed(2)} `
    pen = true
  }
  return d.trim()
}

function areaPath(points: Pt[], baseY: number): string {
  let d = ''
  let run: { x: number; y: number }[] = []
  const flush = () => {
    if (run.length < 2) {
      run = []
      return
    }
    d += `M${run[0].x.toFixed(2)} ${baseY} `
    for (const p of run) d += `L${p.x.toFixed(2)} ${p.y.toFixed(2)} `
    d += `L${run[run.length - 1].x.toFixed(2)} ${baseY} Z `
    run = []
  }
  for (const p of points) {
    if (!p) flush()
    else run.push(p)
  }
  flush()
  return d.trim()
}

export function FocusTimeline({
  epochs,
  session,
  model,
  activeIndex,
  onHover,
  onSelect,
}: FocusTimelineProps) {
  const uid = useId().replace(/:/g, '')
  const svgRef = useRef<SVGSVGElement>(null)

  const geometry = useMemo(() => {
    const lastIndex = epochs.length > 0 ? epochs[epochs.length - 1].index : 0
    const span = Math.max(1, lastIndex)
    const plotW = VB_W - PAD_L - PAD_R
    const x = (index: number) => PAD_L + (index / span) * plotW

    const hrValues = epochs
      .map((e) => e.hrBpm)
      .filter((v): v is number => v != null)
    const hrLo = hrValues.length > 0 ? Math.min(...hrValues) : 60
    const hrHi = hrValues.length > 0 ? Math.max(...hrValues) : 100
    const hrPad = Math.max(3, (hrHi - hrLo) * 0.18)
    const hrMin = Math.floor(hrLo - hrPad)
    const hrMax = Math.ceil(hrHi + hrPad)
    const yHr = (bpm: number) =>
      HR_BOT - ((bpm - hrMin) / Math.max(1, hrMax - hrMin)) * (HR_BOT - HR_TOP)

    const threshold = focusFadeThreshold(session)
    // A calm block now rests near zero and only a real fade approaches 1, so the track is
    // scaled to the session rather than to a fixed 0…1 the trace would hug the floor of.
    const domain = fadeScoreDomain(epochs, threshold)
    const yFade = (score: number) =>
      FADE_BOT -
      ((clamp(score, domain.lo, domain.hi) - domain.lo) / (domain.hi - domain.lo)) *
        (FADE_BOT - FADE_TOP)

    return { span, x, hrMin, hrMax, yHr, threshold, domain, yFade }
  }, [epochs, session])

  const { x, hrMin, hrMax, yHr, threshold, domain, yFade } = geometry

  const hrPoints: Pt[] = epochs.map((e) =>
    e.hrBpm == null ? null : { x: x(e.index), y: yHr(e.hrBpm) },
  )
  const fadePoints: Pt[] = epochs.map((e) =>
    e.fadeScore == null ? null : { x: x(e.index), y: yFade(e.fadeScore) },
  )

  // The engine stops scoring the moment a break starts, so the last score simply stands.
  // Drawing that stretch as live signal would be a lie; it is dashed and dimmed instead.
  const scoredPoints: Pt[] = epochs.map((e, i) =>
    isScoredPhase(e) ? fadePoints[i] : null,
  )
  const heldPoints: Pt[] = epochs.map((e, i) => {
    if (!isScoredPhase(e)) return fadePoints[i]
    // Carry the last scored point into the held run so the line does not break at the seam.
    const next = epochs[i + 1]
    return next && !isScoredPhase(next) ? fadePoints[i] : null
  })
  const hasHeldRun = heldPoints.some((p) => p != null)

  const fadeEvents = useMemo(() => focusFadeEvents(epochs), [epochs])

  /**
   * Epochs whose score cleared the trip line without a nudge firing. On the phone a fade
   * needs two consecutive 8 s samples over the line, so a lone spike gets absorbed — this
   * is where you can see the debounce doing its job.
   */
  const debouncedSpikes = useMemo(() => {
    if (threshold == null) return []
    return epochs.filter(
      (e) =>
        isScoredPhase(e) &&
        !e.fadeSuggested &&
        e.fadeScore != null &&
        e.fadeScore > threshold,
    )
  }, [epochs, threshold])

  const hrAnchor = model.hrAnchor

  const phaseRuns = useMemo(() => {
    const runs: { phase: FocusPhase; from: number; to: number }[] = []
    for (const epoch of epochs) {
      const last = runs[runs.length - 1]
      if (last && last.phase === epoch.phase && epoch.index === last.to + 1) {
        last.to = epoch.index
      } else {
        runs.push({ phase: epoch.phase, from: epoch.index, to: epoch.index })
      }
    }
    return runs
  }, [epochs])

  const thresholdOffset =
    threshold != null
      ? clamp((yFade(threshold) - FADE_TOP) / (FADE_BOT - FADE_TOP), 0, 1)
      : 1

  const xTickStep = geometry.span > 40 ? 10 : geometry.span > 16 ? 4 : 2
  const xTicks: number[] = []
  for (let i = 0; i <= geometry.span; i += xTickStep) xTicks.push(i)

  function indexFromPointer(event: ReactPointerEvent<SVGSVGElement>): number | null {
    const svg = svgRef.current
    if (!svg || epochs.length === 0) return null
    const rect = svg.getBoundingClientRect()
    if (rect.width === 0) return null
    const xVb = ((event.clientX - rect.left) / rect.width) * VB_W
    const frac = (xVb - PAD_L) / (VB_W - PAD_L - PAD_R)
    const target = clamp(frac, 0, 1) * geometry.span
    let best = epochs[0]
    for (const epoch of epochs) {
      if (Math.abs(epoch.index - target) < Math.abs(best.index - target)) best = epoch
    }
    return best.index
  }

  if (epochs.length === 0) {
    return (
      <div className="surface-lift flex h-full min-h-[320px] flex-col rounded-sm border border-line bg-panel/70 p-4">
        <TimelineHeading />
        <div className="flex flex-1 items-center justify-center px-6 text-center">
          <div>
            <div className="font-mono text-xs text-fog">No epochs yet</div>
            <p className="mx-auto mt-2 max-w-sm font-mono text-[11px] leading-relaxed text-muted">
              The phone writes <span className="text-signal">sessions/{session.id}/epochs</span> once
              every 30 s while a Focus block runs. Start a block on the phone, or switch to Demo
              focus.
            </p>
          </div>
        </div>
      </div>
    )
  }

  const activeEpoch =
    activeIndex != null ? (epochs.find((e) => e.index === activeIndex) ?? null) : null

  return (
    <div className="surface-lift flex h-full min-h-[320px] flex-col rounded-sm border border-line bg-panel/70 p-4">
      <TimelineHeading showHeld={hasHeldRun} />
      {/* Phones scroll the plot rather than shrinking the labels to nothing. */}
      <div className="min-h-0 flex-1 overflow-x-auto">
        <svg
          key={`${session.id}-${epochs.length}`}
          ref={svgRef}
          viewBox={`0 0 ${VB_W} ${VB_H}`}
          className="h-auto w-full min-w-[680px] select-none"
          role="img"
          aria-label="Heart rate and fade score across the focus block"
          onPointerMove={(e) => onHover(indexFromPointer(e))}
          onPointerLeave={() => onHover(null)}
          onPointerDown={(e) => {
            const idx = indexFromPointer(e)
            if (idx != null) onSelect(idx)
          }}
        >
          <defs>
            <linearGradient id={`hrArea-${uid}`} x1="0" y1={HR_TOP} x2="0" y2={HR_BOT} gradientUnits="userSpaceOnUse">
              <stop offset="0" stopColor="#ff7a8a" stopOpacity="0.22" />
              <stop offset="1" stopColor="#ff7a8a" stopOpacity="0" />
            </linearGradient>
            <linearGradient id={`fadeArea-${uid}`} x1="0" y1={FADE_TOP} x2="0" y2={FADE_BOT} gradientUnits="userSpaceOnUse">
              <stop offset="0" stopColor="#f0b429" stopOpacity="0.26" />
              <stop offset={String(thresholdOffset)} stopColor="#3dffc4" stopOpacity="0.14" />
              <stop offset="1" stopColor="#3dffc4" stopOpacity="0.02" />
            </linearGradient>
            <linearGradient id={`fadeStroke-${uid}`} x1="0" y1={FADE_TOP} x2="0" y2={FADE_BOT} gradientUnits="userSpaceOnUse">
              <stop offset="0" stopColor="#ff3b4e" />
              <stop offset={String(Math.max(0, thresholdOffset - 0.001))} stopColor="#f0b429" />
              <stop offset={String(Math.min(1, thresholdOffset + 0.001))} stopColor="#3dffc4" />
              <stop offset="1" stopColor="#3dffc4" />
            </linearGradient>
          </defs>

          {/* Track frames */}
          <rect
            x={PAD_L}
            y={HR_TOP}
            width={VB_W - PAD_L - PAD_R}
            height={HR_BOT - HR_TOP}
            fill="#0a1119"
            stroke="#16222f"
          />
          <rect
            x={PAD_L}
            y={FADE_TOP}
            width={VB_W - PAD_L - PAD_R}
            height={FADE_BOT - FADE_TOP}
            fill="#0a1119"
            stroke="#16222f"
          />

          {/* HR gridlines */}
          {[hrMin, Math.round((hrMin + hrMax) / 2), hrMax].map((bpm) => (
            <g key={`hr-${bpm}`}>
              <line
                x1={PAD_L}
                x2={VB_W - PAD_R}
                y1={yHr(bpm)}
                y2={yHr(bpm)}
                stroke="#1e2d3d"
                strokeDasharray="2 6"
              />
              <text
                x={PAD_L - 8}
                y={yHr(bpm) + 3.5}
                textAnchor="end"
                fill="#6b8299"
                fontSize="10"
                fontFamily="IBM Plex Mono, monospace"
              >
                {bpm}
              </text>
            </g>
          ))}

          {/* Fade gridlines — zero is drawn solid, since the HR term can read below it */}
          {domain.ticks.map((score) => (
            <g key={`fade-${score}`}>
              <line
                x1={PAD_L}
                x2={VB_W - PAD_R}
                y1={yFade(score)}
                y2={yFade(score)}
                stroke={score === 0 && domain.lo < 0 ? '#2b3d50' : '#1e2d3d'}
                strokeDasharray={score === 0 && domain.lo < 0 ? undefined : '2 6'}
              />
              <text
                x={PAD_L - 8}
                y={yFade(score) + 3.5}
                textAnchor="end"
                fill="#6b8299"
                fontSize="10"
                fontFamily="IBM Plex Mono, monospace"
              >
                {score.toFixed(2)}
              </text>
            </g>
          ))}

          {/* Fade-suggested shading across both tracks */}
          {epochs
            .filter((e) => e.fadeSuggested)
            .map((e) => (
              <rect
                key={`hold-${e.index}`}
                x={x(e.index) - (VB_W - PAD_L - PAD_R) / geometry.span / 2}
                y={HR_TOP}
                width={(VB_W - PAD_L - PAD_R) / geometry.span}
                height={FADE_BOT - HR_TOP}
                fill="rgba(240,180,41,0.07)"
              />
            ))}

          {/* HR anchor (fade detector's session anchor) */}
          {hrAnchor != null ? (
            <g>
              <line
                x1={PAD_L}
                x2={VB_W - PAD_R}
                y1={yHr(hrAnchor)}
                y2={yHr(hrAnchor)}
                stroke="#ff7a8a"
                strokeOpacity="0.32"
                strokeDasharray="5 5"
              />
              <text
                x={VB_W - PAD_R - 6}
                y={yHr(hrAnchor) - 6}
                textAnchor="end"
                fill="#ff7a8a"
                fillOpacity="0.7"
                fontSize="9.5"
                letterSpacing="1"
                fontFamily="IBM Plex Mono, monospace"
              >
                ANCHOR ≈{Math.round(hrAnchor)} EST
              </text>
            </g>
          ) : null}

          <path d={areaPath(hrPoints, HR_BOT)} fill={`url(#hrArea-${uid})`} className="chart-area" />
          <path
            d={linePath(hrPoints)}
            fill="none"
            stroke="#ff7a8a"
            strokeWidth="2.2"
            strokeLinejoin="round"
            strokeLinecap="round"
            pathLength={1}
            className="chart-stroke"
          />

          {/* Fade trip line: baseline + 2σ */}
          {threshold != null && threshold <= domain.hi ? (
            <g>
              <line
                x1={PAD_L}
                x2={VB_W - PAD_R}
                y1={yFade(threshold)}
                y2={yFade(threshold)}
                stroke="#f0b429"
                strokeWidth="1.2"
                strokeDasharray="6 4"
                strokeOpacity="0.75"
              />
              <text
                x={VB_W - PAD_R - 6}
                y={yFade(threshold) - 6}
                textAnchor="end"
                fill="#f0b429"
                fontSize="9.5"
                letterSpacing="1"
                fontFamily="IBM Plex Mono, monospace"
              >
                TRIP {threshold.toFixed(3)} · BASELINE +2σ
              </text>
            </g>
          ) : null}

          <path
            d={areaPath(scoredPoints, yFade(Math.max(0, domain.lo)))}
            fill={`url(#fadeArea-${uid})`}
            className="chart-area"
          />
          <path
            d={linePath(scoredPoints)}
            fill="none"
            stroke={`url(#fadeStroke-${uid})`}
            strokeWidth="2.2"
            strokeLinejoin="round"
            strokeLinecap="round"
            pathLength={1}
            className="chart-stroke"
          />
          {hasHeldRun ? (
            <path
              d={linePath(heldPoints)}
              fill="none"
              stroke="#6b8299"
              strokeWidth="1.6"
              strokeDasharray="4 4"
              strokeLinejoin="round"
              strokeLinecap="round"
              className="chart-area"
            />
          ) : null}

          {/* Cleared the trip line, but not for two samples running */}
          <g className="chart-marks">
          {debouncedSpikes.map((e) => (
            <circle
              key={`spike-${e.index}`}
              cx={x(e.index)}
              cy={yFade(e.fadeScore as number)}
              r="3.4"
              fill="none"
              stroke="#f0b429"
              strokeWidth="1.3"
              strokeOpacity="0.8"
            />
          ))}

          {/* Fade catches */}
          {fadeEvents.map((event, i) => (
            <g key={`event-${event.index}`}>
              <line
                x1={x(event.index)}
                x2={x(event.index)}
                y1={HR_TOP}
                y2={FADE_BOT}
                stroke="#f0b429"
                strokeWidth="1.4"
                strokeDasharray="3 3"
                strokeOpacity="0.85"
              />
              <circle
                cx={x(event.index)}
                cy={HR_TOP}
                r="4"
                fill="#f0b429"
                stroke="#070b10"
                strokeWidth="1.5"
              />
              <text
                x={x(event.index) + (x(event.index) > VB_W - 190 ? -8 : 8)}
                y={HR_TOP + 13 + (i % 2) * 14}
                textAnchor={x(event.index) > VB_W - 190 ? 'end' : 'start'}
                fill="#f0b429"
                fontSize="10"
                letterSpacing="1.2"
                fontFamily="IBM Plex Mono, monospace"
              >
                FADE {i + 1} · {elapsedLabel(event.index)}
              </text>
              {event.hrBpm != null ? (
                <circle
                  cx={x(event.index)}
                  cy={yHr(event.hrBpm)}
                  r="3.4"
                  fill="#f0b429"
                  stroke="#070b10"
                  strokeWidth="1.2"
                />
              ) : null}
            </g>
          ))}
          </g>

          {/* Crosshair */}
          {activeEpoch ? (
            <g>
              <line
                x1={x(activeEpoch.index)}
                x2={x(activeEpoch.index)}
                y1={HR_TOP}
                y2={RIBBON_TOP + RIBBON_H}
                stroke="#9bb0c4"
                strokeOpacity="0.55"
              />
              {activeEpoch.hrBpm != null ? (
                <circle
                  cx={x(activeEpoch.index)}
                  cy={yHr(activeEpoch.hrBpm)}
                  r="4"
                  fill="#ff7a8a"
                  stroke="#070b10"
                  strokeWidth="1.5"
                />
              ) : null}
              {activeEpoch.fadeScore != null ? (
                <circle
                  cx={x(activeEpoch.index)}
                  cy={yFade(activeEpoch.fadeScore)}
                  r="4"
                  fill={
                    threshold != null && activeEpoch.fadeScore > threshold
                      ? '#f0b429'
                      : '#3dffc4'
                  }
                  stroke="#070b10"
                  strokeWidth="1.5"
                />
              ) : null}
            </g>
          ) : null}

          {/* Phase ribbon */}
          {phaseRuns.map((run) => {
            const half = (VB_W - PAD_L - PAD_R) / geometry.span / 2
            const x0 = clamp(x(run.from) - half, PAD_L, VB_W - PAD_R)
            const x1 = clamp(x(run.to) + half, PAD_L, VB_W - PAD_R)
            const w = Math.max(1, x1 - x0)
            return (
              <g key={`run-${run.phase}-${run.from}`}>
                <rect
                  x={x0}
                  y={RIBBON_TOP}
                  width={w}
                  height={RIBBON_H}
                  fill={PHASE_FILL[run.phase]}
                />
                {w > 54 ? (
                  <text
                    x={x0 + w / 2}
                    y={RIBBON_TOP + RIBBON_H - 2.5}
                    textAnchor="middle"
                    fill={PHASE_TEXT[run.phase]}
                    fontSize="8"
                    letterSpacing="1.6"
                    fontFamily="IBM Plex Mono, monospace"
                  >
                    {run.phase.toUpperCase()}
                  </text>
                ) : null}
              </g>
            )
          })}

          {/* X axis */}
          <line
            x1={PAD_L}
            x2={VB_W - PAD_R}
            y1={RIBBON_TOP + RIBBON_H + 6}
            y2={RIBBON_TOP + RIBBON_H + 6}
            stroke="#1e2d3d"
          />
          {xTicks.map((tick) => (
            <text
              key={`tick-${tick}`}
              x={x(tick)}
              y={AXIS_Y}
              textAnchor="middle"
              fill="#6b8299"
              fontSize="10"
              fontFamily="IBM Plex Mono, monospace"
            >
              {elapsedLabel(tick)}
            </text>
          ))}
        </svg>
      </div>
    </div>
  )
}

function TimelineHeading({ showHeld = false }: { showHeld?: boolean }) {
  return (
    <div className="mb-3 flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
      <div>
        <h2 className="font-display text-sm font-medium tracking-wide text-fog">
          Focus block timeline
        </h2>
        <p className="mt-0.5 font-mono text-[10px] tracking-wide text-muted">
          One epoch / 30 s · heart rate above, fade score below · elapsed mm:ss
        </p>
      </div>
      <div className="flex flex-wrap gap-x-4 gap-y-1 font-mono text-[10px] uppercase tracking-wider text-muted">
        <span className="text-pulse">● HR bpm</span>
        <span className="text-signal">● Fade score</span>
        <span className="text-amber">▲ Fade caught</span>
        <span className="text-amber/80" title="Over the trip line, but not for two samples running">
          ○ Over trip, debounced
        </span>
        {showHeld ? (
          <span title="The engine stops scoring on a break — the last score stands">
            ┄ Held on break
          </span>
        ) : null}
      </div>
    </div>
  )
}
