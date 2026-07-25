import type { Session } from '../types/session'

interface ClockSyncBadgeProps {
  session: Session
}

export function ClockSyncBadge({ session }: ClockSyncBadgeProps) {
  const rtt = session.clockRttMs
  const quality =
    rtt <= 50 ? 'EXCELLENT' : rtt <= 100 ? 'GOOD' : rtt <= 150 ? 'DEGRADED' : 'POOR'
  const tone =
    rtt <= 50
      ? 'text-signal border-signal/40'
      : rtt <= 100
        ? 'text-visual border-visual/40'
        : rtt <= 150
          ? 'text-amber border-amber/40'
          : 'text-alert border-alert/40'

  return (
    <div className={`inline-flex items-center gap-3 rounded-sm border bg-panel px-3 py-1.5 ${tone}`}>
      <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-muted">
        Clock sync
      </span>
      <span className="font-mono text-xs tabular-nums">
        offset {session.clockOffsetMs.toFixed(1)} ms
      </span>
      <span className="text-line">|</span>
      <span className="font-mono text-xs tabular-nums">RTT {rtt.toFixed(0)} ms</span>
      <span className="font-mono text-[10px] tracking-wider">{quality}</span>
    </div>
  )
}
