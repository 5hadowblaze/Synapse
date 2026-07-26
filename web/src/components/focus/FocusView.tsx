import { useEffect, useMemo, useState } from 'react'
import { buildFocusModel, isScoredPhase } from '../../data/focusAnalysis'
import { buildLiveChannels } from '../../data/liveChannels'
import type { DataMode } from '../../hooks/useSession'
import {
  focusFadeEvents,
  focusFadeThreshold,
  formatDurationSeconds,
  type FocusEpoch,
  type Session,
} from '../../types/session'
import { MetricTile } from '../MetricTile'
import { ChartReveal, Reveal, RevealItem } from '../motion/Reveal'
import { FocusEpochStrip } from './FocusEpochStrip'
import { FocusLiveStrip } from './FocusLiveStrip'
import { FocusPacingReport } from './FocusPacingReport'
import { FocusRecapPanel } from './FocusRecapPanel'
import { FocusSignalPanel } from './FocusSignalPanel'
import { FocusTimeline } from './FocusTimeline'
import { elapsedLabel } from './focusTime'

interface FocusViewProps {
  session: Session
  epochs: FocusEpoch[]
  mode: DataMode
}

function remainingLabel(remainingMs: number | null): string {
  if (remainingMs == null) return '—'
  const total = Math.max(0, Math.round(remainingMs / 1000))
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`
}

export function FocusView({ session, epochs, mode }: FocusViewProps) {
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null)
  const [hoverIndex, setHoverIndex] = useState<number | null>(null)
  const [nowMs, setNowMs] = useState(() => Date.now())

  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [])

  const liveChannels = useMemo(
    () => buildLiveChannels({ mode, session, epochs, nowMs }),
    [mode, session, epochs, nowMs],
  )

  const latest = epochs.length > 0 ? epochs[epochs.length - 1] : null

  useEffect(() => {
    setSelectedIndex((prev) => {
      if (prev != null && epochs.some((e) => e.index === prev)) return prev
      // A finished block opens on its last catch — that is the story. A running
      // one opens on the newest epoch.
      const events = focusFadeEvents(epochs)
      if (session.status === 'complete' && events.length > 0) {
        return events[events.length - 1].index
      }
      return epochs[epochs.length - 1]?.index ?? null
    })
  }, [epochs, session.status])

  const activeIndex = hoverIndex ?? selectedIndex
  const activeEpoch = useMemo(
    () => epochs.find((e) => e.index === activeIndex) ?? latest,
    [epochs, activeIndex, latest],
  )

  const threshold = focusFadeThreshold(session)
  const fadeEvents = useMemo(() => focusFadeEvents(epochs), [epochs])
  const model = useMemo(() => buildFocusModel(epochs), [epochs])
  const hrAnchor = model.hrAnchor

  const fadeCount = session.focusFadeCount ?? fadeEvents.length
  const lastFadeAt = fadeEvents.length > 0 ? fadeEvents[fadeEvents.length - 1] : null

  const focusedSeconds =
    session.focusFocusedSeconds ??
    (latest ? (latest.index * 30_000) / 1000 : null)

  /** One derived sentence so the chart reads at a glance. */
  const story = useMemo(() => {
    if (epochs.length === 0) return null
    const parts: string[] = []
    if (fadeEvents.length > 0) {
      const times = fadeEvents.map((e) => elapsedLabel(e.index)).join(' and ')
      parts.push(
        `Fade caught ${fadeEvents.length}× — at ${times} into the block`,
      )
    } else {
      parts.push('No fade caught yet — the block is holding')
    }
    const hrs = epochs.map((e) => e.hrBpm).filter((v): v is number => v != null)
    // Peak after the baseline window, so a warm start isn't reported as the climb.
    const settledHrs = epochs
      .slice(model.baselineEpochs)
      .map((e) => e.hrBpm)
      .filter((v): v is number => v != null)
    if (model.hrAnchor != null && settledHrs.length > 1) {
      parts.push(
        `heart rate anchored at ${Math.round(model.hrAnchor)} bpm and climbed to ${Math.round(
          Math.max(...settledHrs),
        )}`,
      )
    } else if (hrs.length > 1) {
      parts.push(
        `heart rate ${Math.round(Math.min(...hrs))} → ${Math.round(Math.max(...hrs))} bpm`,
      )
    }
    const firstBreak = epochs.find((e) => e.phase === 'break')
    if (firstBreak) parts.push(`break started ${elapsedLabel(firstBreak.index)}`)

    const droppedNames = (['hr', 'arousal', 'motion'] as const)
      .filter((key) => model.channels[key].weight == null)
      .map((key) => ({ hr: 'heart rate', arousal: 'arousal', motion: 'motion' })[key])
    const dropped =
      droppedNames.length > 0
        ? ` ${droppedNames.join(' and ')} dropped out, so the score is weighted across the rest.`
        : ''
    return `${parts.join(' · ')}.${dropped}`
  }, [epochs, fadeEvents, model])

  const shownScore = activeEpoch?.fadeScore ?? null
  const overTrip = shownScore != null && threshold != null && shownScore > threshold

  const hrShown = activeEpoch?.hrBpm ?? session.lastHeartRateBpm
  const hrDelta =
    hrShown != null && hrAnchor != null ? hrShown - hrAnchor : null
  const hrLive = liveChannels.find((c) => c.key === 'hr')
  const fadeLive = liveChannels.find((c) => c.key === 'fade')
  const countKey = `${session.id}-${mode}`
  const chartKey = `${session.id}-${epochs.length}-${mode}`

  return (
    <Reveal replayKey={countKey} className="flex flex-col gap-4">
      <RevealItem>
        <FocusLiveStrip channels={liveChannels} />
      </RevealItem>

      <RevealItem className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <MetricTile
          label="Fade score"
          value={shownScore != null ? shownScore.toFixed(3) : '—'}
          unit=""
          accent={overTrip ? 'motor' : 'gap'}
          live={fadeLive?.state === 'live'}
          countKey={countKey}
          sub={
            threshold != null
              ? `trip ${threshold.toFixed(3)} · baseline +2σ`
              : 'baseline still building'
          }
        />
        <MetricTile
          label="Heart rate"
          value={hrShown != null ? Math.round(hrShown).toString() : '—'}
          unit="bpm"
          accent="pulse"
          live={hrLive?.state === 'live'}
          countKey={countKey}
          sub={
            hrLive && hrLive.state !== 'missing'
              ? hrLive.detail
              : hrDelta != null
                ? `${hrDelta >= 0 ? '+' : ''}${hrDelta.toFixed(1)} vs anchor ≈${Math.round(hrAnchor ?? 0)}`
                : (session.lastHeartRateSource ?? 'awaiting Watch sample')
          }
        />
        <MetricTile
          label="Focused"
          value={formatDurationSeconds(focusedSeconds)}
          unit=""
          accent="muted"
          countKey={countKey}
          sub={
            session.focusBreakSeconds != null
              ? `break ${formatDurationSeconds(session.focusBreakSeconds)}`
              : `${epochs.length} epochs written`
          }
        />
        <MetricTile
          label="Fade catches"
          value={String(fadeCount)}
          unit=""
          accent={fadeCount > 0 ? 'motor' : 'muted'}
          countKey={countKey}
          sub={
            lastFadeAt
              ? `last at ${elapsedLabel(lastFadeAt.index)} into the block`
              : 'no nudge fired yet'
          }
        />
      </RevealItem>

      {story ? (
        <RevealItem>
          <p className="border-l-2 border-amber/70 bg-panel/40 px-4 py-2 text-[13px] leading-relaxed text-fog">
            {story}
          </p>
        </RevealItem>
      ) : null}

      <RevealItem>
        <FocusPacingReport session={session} epochs={epochs} />
      </RevealItem>

      <RevealItem>
        <ChartReveal replayKey={chartKey}>
          <FocusTimeline
            epochs={epochs}
            session={session}
            model={model}
            activeIndex={activeEpoch?.index ?? null}
            onHover={setHoverIndex}
            onSelect={setSelectedIndex}
          />
        </ChartReveal>
      </RevealItem>

      {activeEpoch ? (
        <RevealItem>
          <div className="surface-lift flex flex-wrap items-center gap-x-6 gap-y-1 rounded-sm border border-line bg-panel/60 px-4 py-2 font-mono text-[11px] tabular-nums text-fog">
            <span className="text-muted">
              EPOCH <span className="text-fog">{activeEpoch.index}</span> ·{' '}
              {elapsedLabel(activeEpoch.index)}
            </span>
            <span className="text-muted">
              PHASE{' '}
              <span
                className={
                  activeEpoch.phase === 'fade'
                    ? 'text-amber'
                    : activeEpoch.phase === 'break'
                      ? 'text-visual'
                      : 'text-signal'
                }
              >
                {activeEpoch.phase}
              </span>
            </span>
            <span className="text-muted">
              FADE{' '}
              <span className={overTrip ? 'text-amber' : 'text-signal'}>
                {activeEpoch.fadeScore != null ? activeEpoch.fadeScore.toFixed(3) : '—'}
              </span>
              {!isScoredPhase(activeEpoch) ? (
                <span className="ml-1 text-[10px] uppercase tracking-wider text-muted">held</span>
              ) : null}
            </span>
            <span className="text-muted">
              HR{' '}
              <span className="text-pulse">
                {activeEpoch.hrBpm != null ? activeEpoch.hrBpm.toFixed(0) : '—'}
              </span>
            </span>
            <span className="text-muted">
              EYEWIDE{' '}
              <span className="text-fog">
                {activeEpoch.arousalIndex != null ? activeEpoch.arousalIndex.toFixed(3) : '—'}
              </span>
            </span>
            <span className="text-muted">
              MOTION{' '}
              <span className="text-fog">
                {activeEpoch.motionEnergy != null ? activeEpoch.motionEnergy.toFixed(2) : '—'}
              </span>
            </span>
            <span className="text-muted">
              REMAINING <span className="text-fog">{remainingLabel(activeEpoch.remainingMs)}</span>
            </span>
            {activeEpoch.fadeSuggested ? (
              <span className="rounded-sm border border-amber/50 px-1.5 py-0.5 text-[10px] uppercase tracking-wider text-amber">
                break suggested
              </span>
            ) : null}
          </div>
        </RevealItem>
      ) : null}

      <RevealItem className="grid gap-4 lg:grid-cols-5">
        <div className="surface-lift lg:col-span-3">
          <FocusSignalPanel epochs={epochs} epoch={activeEpoch} model={model} />
        </div>
        <div className="surface-lift lg:col-span-2">
          <FocusRecapPanel session={session} />
        </div>
      </RevealItem>

      <RevealItem>
        <FocusEpochStrip
          epochs={epochs}
          activeIndex={activeEpoch?.index ?? null}
          onSelect={setSelectedIndex}
          onHover={setHoverIndex}
          threshold={threshold}
        />
      </RevealItem>
    </Reveal>
  )
}
