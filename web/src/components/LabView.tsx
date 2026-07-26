import { useEffect, useMemo, useState } from 'react'
import {
  isKineticModule,
  meanFinite,
  octantLabel,
  spatialAccuracyPct,
  type Session,
  type TrialWithGaze,
} from '../types/session'
import { GazeField } from './GazeField'
import { MetricTile } from './MetricTile'
import { TimelineChart } from './TimelineChart'
import { ChartReveal, Reveal, RevealItem } from './motion/Reveal'

interface LabViewProps {
  session: Session
  trials: TrialWithGaze[]
}

function formatMs(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return '—'
  return Math.round(value).toString()
}

function formatPct(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return '—'
  return value.toFixed(0)
}

/** Vision PVT / Kinetic Clock lab modules — trial-based, not Focus epochs. */
export function LabView({ session, trials }: LabViewProps) {
  const kinetic = isKineticModule(session.module)
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null)
  const [scrubMs, setScrubMs] = useState(400)

  useEffect(() => {
    if (trials.length === 0) {
      setSelectedIndex(null)
      return
    }
    setSelectedIndex((prev) => {
      if (prev != null && trials.some((t) => t.index === prev)) return prev
      return trials[trials.length - 1]?.index ?? null
    })
  }, [trials])

  const selectedTrial = useMemo(
    () => trials.find((t) => t.index === selectedIndex) ?? null,
    [trials, selectedIndex],
  )

  const latest = trials.length > 0 ? trials[trials.length - 1] : null
  const accuracy = useMemo(() => spatialAccuracyPct(trials), [trials])
  const meanArousal = useMemo(
    () => meanFinite(trials.map((t) => t.arousalIndex)),
    [trials],
  )

  const gazeMax = selectedTrial?.gaze?.samples.at(-1)?.dt ?? 800
  const gazeMin = selectedTrial?.gaze?.samples[0]?.dt ?? -200

  useEffect(() => {
    setScrubMs(Math.min(400, gazeMax))
  }, [selectedIndex, gazeMax])

  const countKey = `${session.id}-${session.module}`
  const chartKey = `${session.id}-${trials.length}`

  return (
    <Reveal replayKey={countKey} className="flex flex-col gap-4">
      <RevealItem className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {kinetic ? (
          <>
            <MetricTile
              label="Spatial accuracy"
              value={formatPct(accuracy)}
              unit="%"
              accent="gap"
              countKey={countKey}
              sub={
                latest?.spatialMatch != null
                  ? `last ${latest.spatialMatch ? 'match' : 'miss'} · T ${octantLabel(latest.targetOctant)} → D ${octantLabel(latest.detectedOctant)}`
                  : 'awaiting strikes'
              }
            />
            <MetricTile
              label="Motor RT"
              value={formatMs(latest?.motorRtMs)}
              accent="motor"
              countKey={countKey}
              sub="strike − target"
            />
            <MetricTile
              label="Peak G"
              value={
                latest?.peakG != null && Number.isFinite(latest.peakG)
                  ? latest.peakG.toFixed(1)
                  : '—'
              }
              unit="g"
              accent="visual"
              countKey={countKey}
              sub="strike peak accel"
            />
            <MetricTile
              label="Watch HR"
              value={
                session.lastHeartRateBpm != null &&
                Number.isFinite(session.lastHeartRateBpm)
                  ? Math.round(session.lastHeartRateBpm).toString()
                  : '—'
              }
              unit="bpm"
              accent="muted"
              countKey={countKey}
              sub={
                session.lastHeartRateSource
                  ? `workout · ${session.lastHeartRateSource}`
                  : 'Series 5 discrete sample'
              }
            />
          </>
        ) : (
          <>
            <MetricTile
              label="Visual RT"
              value={formatMs(latest?.visualRtMs)}
              accent="visual"
              countKey={countKey}
              sub="saccade onset − target"
            />
            <MetricTile
              label="Arousal"
              value={
                latest?.arousalIndex != null
                  ? latest.arousalIndex.toFixed(2)
                  : '—'
              }
              unit=""
              accent="gap"
              countKey={countKey}
              sub={
                meanArousal != null
                  ? `session mean ${meanArousal.toFixed(2)}`
                  : 'blink-gated index'
              }
            />
            <MetricTile
              label="Gaze settle"
              value={
                latest?.gazeSettleMs != null && latest?.targetOnsetMs != null
                  ? formatMs(latest.gazeSettleMs - latest.targetOnsetMs)
                  : '—'
              }
              accent="motor"
              countKey={countKey}
              sub="settle − target"
            />
            <MetricTile
              label="Watch HR"
              value={
                session.lastHeartRateBpm != null &&
                Number.isFinite(session.lastHeartRateBpm)
                  ? Math.round(session.lastHeartRateBpm).toString()
                  : '—'
              }
              unit="bpm"
              accent="muted"
              countKey={countKey}
              sub="session latest (if Watch paired)"
            />
          </>
        )}
      </RevealItem>

      <RevealItem className="grid min-h-[340px] gap-4 lg:grid-cols-5">
        <ChartReveal replayKey={chartKey} className="lg:col-span-3">
          <TimelineChart
            trials={trials}
            session={session}
            selectedIndex={selectedIndex}
            onSelect={setSelectedIndex}
          />
        </ChartReveal>
        <div className="surface-lift lg:col-span-2">
          <GazeField trial={selectedTrial} scrubMs={scrubMs} module={session.module} />
        </div>
      </RevealItem>

      {!kinetic ? (
        <RevealItem>
          <section className="surface-lift rounded-sm border border-line bg-panel/60 px-4 py-3">
            <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
              <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-muted">
                Gaze scrub · trial timeline window (−200 → +800 ms)
              </span>
              <span className="font-mono text-xs tabular-nums text-fog">
                {scrubMs.toFixed(0)} ms
              </span>
            </div>
            <input
              type="range"
              min={gazeMin}
              max={gazeMax}
              step={8}
              value={scrubMs}
              onChange={(e) => setScrubMs(Number(e.target.value))}
              className="w-full accent-signal"
            />
            <div className="mt-3 flex flex-wrap gap-2">
              {trials.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => setSelectedIndex(t.index)}
                  className={`btn-press rounded-sm border px-2 py-1 font-mono text-[10px] tabular-nums ${
                    t.index === selectedIndex
                      ? 'border-signal/50 bg-signal/10 text-signal'
                      : t.index === session.breakPointTrial
                        ? 'border-alert/50 text-alert'
                        : 'border-line text-muted hover:text-fog'
                  }`}
                >
                  {t.index}
                </button>
              ))}
            </div>
          </section>
        </RevealItem>
      ) : (
        <RevealItem>
          <section className="surface-lift rounded-sm border border-line bg-panel/60 px-4 py-3">
            <div className="mb-2 font-mono text-[10px] uppercase tracking-[0.2em] text-muted">
              Trial strip · spatial match / miss
            </div>
            <div className="flex flex-wrap gap-2">
              {trials.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => setSelectedIndex(t.index)}
                  className={`btn-press rounded-sm border px-2 py-1 font-mono text-[10px] tabular-nums ${
                    t.index === selectedIndex
                      ? 'border-signal/50 bg-signal/10 text-signal'
                      : t.spatialMatch === false
                        ? 'border-alert/50 text-alert'
                        : t.index === session.breakPointTrial
                          ? 'border-amber/50 text-amber'
                          : 'border-line text-muted hover:text-fog'
                  }`}
                  title={`T ${octantLabel(t.targetOctant)} · D ${octantLabel(t.detectedOctant)}`}
                >
                  {t.index}
                  {t.spatialMatch === false ? '×' : t.spatialMatch ? '✓' : ''}
                </button>
              ))}
            </div>
          </section>
        </RevealItem>
      )}
    </Reveal>
  )
}
