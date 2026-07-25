import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { useSession } from '../hooks/useSession'
import {
  isKineticModule,
  meanFinite,
  octantLabel,
  spatialAccuracyPct,
} from '../types/session'
import { BreakPointBanner } from './BreakPointBanner'
import { ClockSyncBadge } from './ClockSyncBadge'
import { GazeField } from './GazeField'
import { MetricTile } from './MetricTile'
import { SessionPicker } from './SessionPicker'
import { TimelineChart } from './TimelineChart'

function formatMs(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return '—'
  return Math.round(value).toString()
}

function formatPct(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return '—'
  return value.toFixed(0)
}

export function Dashboard() {
  const {
    mode,
    sessionId,
    setSessionId,
    snapshot,
    error,
    forceDemo,
    exitDemo,
    isDemoForced,
  } = useSession()

  const trials = snapshot?.trials ?? []
  const session = snapshot?.session
  const kinetic = session ? isKineticModule(session.module) : false

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

  const moduleLabel = kinetic ? 'Kinetic Clock' : 'Vision PVT'
  const headline = kinetic ? 'Spatial-Motor Monitor' : 'Oculomotor PVT Monitor'
  const blurb = kinetic
    ? 'Eight-direction clock. Timing is always kept; spatialMatch flags whether the punch went the right way.'
    : 'Single-flash oculomotor PVT — saccade onset and arousal, no punch board.'

  return (
    <div className="relative min-h-full bg-ink">
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.35]"
        style={{
          backgroundImage:
            'radial-gradient(ellipse 80% 50% at 50% -10%, rgba(61,255,196,0.08), transparent), linear-gradient(180deg, #0a1018 0%, #070b10 40%, #05080c 100%)',
        }}
      />

      <BreakPointBanner breakPointTrial={session?.breakPointTrial ?? null} />

      <div
        className={`relative mx-auto flex max-w-[1600px] flex-col gap-4 px-5 pb-8 ${
          session?.breakPointTrial != null ? 'pt-20' : 'pt-6'
        }`}
      >
        <header className="flex flex-wrap items-end justify-between gap-4 border-b border-line pb-4">
          <div>
            <div className="font-mono text-[10px] uppercase tracking-[0.35em] text-signal">
              Synapse · Clinical HUD · {moduleLabel}
            </div>
            <h1 className="mt-1 font-display text-3xl font-semibold tracking-tight text-fog md:text-4xl">
              {headline}
            </h1>
            <p className="mt-1 max-w-xl text-sm text-muted">{blurb}</p>
          </div>
          <div className="flex flex-col items-end gap-2">
            {session ? <ClockSyncBadge session={session} /> : null}
            <Link
              to="/qr"
              className="font-mono text-[10px] uppercase tracking-wider text-muted hover:text-signal"
            >
              Dashboard QR →
            </Link>
          </div>
        </header>

        <SessionPicker
          sessionId={sessionId}
          onChange={setSessionId}
          mode={mode}
          isDemoForced={isDemoForced}
          onForceDemo={forceDemo}
          onExitDemo={exitDemo}
          error={error}
          module={session?.module ?? null}
        />

        <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {kinetic ? (
            <>
              <MetricTile
                label="Spatial accuracy"
                value={formatPct(accuracy)}
                unit="%"
                accent="gap"
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
                sub="strike peak accel"
              />
              <MetricTile
                label="Watch HR"
                value={
                  session?.lastHeartRateBpm != null &&
                  Number.isFinite(session.lastHeartRateBpm)
                    ? Math.round(session.lastHeartRateBpm).toString()
                    : '—'
                }
                unit="bpm"
                accent="muted"
                sub={
                  session?.lastHeartRateSource
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
                sub="settle − target"
              />
              <MetricTile
                label="Watch HR"
                value={
                  session?.lastHeartRateBpm != null &&
                  Number.isFinite(session.lastHeartRateBpm)
                    ? Math.round(session.lastHeartRateBpm).toString()
                    : '—'
                }
                unit="bpm"
                accent="muted"
                sub="session latest (if Watch paired)"
              />
            </>
          )}
        </section>

        <section className="grid min-h-[340px] gap-4 lg:grid-cols-5">
          <div className="lg:col-span-3">
            {session ? (
              <TimelineChart
                trials={trials}
                session={session}
                selectedIndex={selectedIndex}
                onSelect={setSelectedIndex}
              />
            ) : (
              <div className="flex h-full min-h-[260px] items-center justify-center rounded-sm border border-line bg-panel/50 font-mono text-xs text-muted">
                Waiting for session…
              </div>
            )}
          </div>
          <div className="lg:col-span-2">
            <GazeField
              trial={selectedTrial}
              scrubMs={scrubMs}
              module={session?.module ?? 'visionPvt'}
            />
          </div>
        </section>

        {!kinetic ? (
          <section className="rounded-sm border border-line bg-panel/60 px-4 py-3">
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
                  className={`rounded-sm border px-2 py-1 font-mono text-[10px] tabular-nums ${
                    t.index === selectedIndex
                      ? 'border-signal/50 bg-signal/10 text-signal'
                      : t.index === session?.breakPointTrial
                        ? 'border-alert/50 text-alert'
                        : 'border-line text-muted hover:text-fog'
                  }`}
                >
                  {t.index}
                </button>
              ))}
            </div>
          </section>
        ) : (
          <section className="rounded-sm border border-line bg-panel/60 px-4 py-3">
            <div className="mb-2 font-mono text-[10px] uppercase tracking-[0.2em] text-muted">
              Trial strip · spatial match / miss
            </div>
            <div className="flex flex-wrap gap-2">
              {trials.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => setSelectedIndex(t.index)}
                  className={`rounded-sm border px-2 py-1 font-mono text-[10px] tabular-nums ${
                    t.index === selectedIndex
                      ? 'border-signal/50 bg-signal/10 text-signal'
                      : t.spatialMatch === false
                        ? 'border-alert/50 text-alert'
                        : t.index === session?.breakPointTrial
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
        )}
      </div>
    </div>
  )
}
