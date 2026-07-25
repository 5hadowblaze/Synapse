import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { useSession } from '../hooks/useSession'
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

  const gazeMax = selectedTrial?.gaze?.samples.at(-1)?.dt ?? 800
  const gazeMin = selectedTrial?.gaze?.samples[0]?.dt ?? -200

  useEffect(() => {
    setScrubMs(Math.min(400, gazeMax))
  }, [selectedIndex, gazeMax])

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
              Synapse · Clinical HUD
            </div>
            <h1 className="mt-1 font-display text-3xl font-semibold tracking-tight text-fog md:text-4xl">
              Cognitive-Motor Monitor
            </h1>
            <p className="mt-1 max-w-xl text-sm text-muted">
              Live gaze onset vs strike timing. The gap is the signal — when it opens, fatigue has
              already started.
            </p>
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
        />

        <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <MetricTile
            label="Cognitive-Motor Gap"
            value={formatMs(latest?.cognitiveMotorGapMs)}
            accent="gap"
            sub={
              session?.baselineGapMs != null
                ? `baseline ${formatMs(session.baselineGapMs)} ± ${formatMs(session.baselineStdMs)}`
                : 'awaiting baseline (n≥10)'
            }
          />
          <MetricTile
            label="Visual RT"
            value={formatMs(latest?.visualRtMs)}
            accent="visual"
            sub="saccade onset − target"
          />
          <MetricTile
            label="Motor RT"
            value={formatMs(latest?.motorRtMs)}
            accent="motor"
            sub="strike − target"
          />
          <MetricTile
            label="Trials"
            value={String(trials.length)}
            unit=""
            accent="muted"
            sub={session ? `${session.status} · ${session.athleteId}` : '—'}
          />
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
            <GazeField trial={selectedTrial} scrubMs={scrubMs} />
          </div>
        </section>

        <section className="rounded-sm border border-line bg-panel/60 px-4 py-3">
          <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
            <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-muted">
              Gaze scrub · trial timeline window (−200 → +800 ms)
            </span>
            <span className="font-mono text-xs tabular-nums text-fog">{scrubMs.toFixed(0)} ms</span>
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
      </div>
    </div>
  )
}
