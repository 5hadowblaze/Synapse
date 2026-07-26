import type { LiveChannel, ChannelLiveState } from '../../data/liveChannels'

const tone: Record<ChannelLiveState, string> = {
  live: 'border-signal/40 text-signal',
  stale: 'border-amber/40 text-amber',
  missing: 'border-line text-muted',
  demo: 'border-amber/30 text-amber',
  idle: 'border-visual/40 text-visual',
}

const pip: Record<ChannelLiveState, string> = {
  live: '●',
  stale: '◐',
  missing: '○',
  demo: '◆',
  idle: '…',
}

interface FocusLiveStripProps {
  channels: LiveChannel[]
}

/** Compact per-channel live / stale / missing strip for the Focus HUD. */
export function FocusLiveStrip({ channels }: FocusLiveStripProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {channels.map((ch) => (
        <div
          key={ch.key}
          className={`surface-lift min-w-[7.5rem] rounded-sm border bg-panel/70 px-2.5 py-1.5 ${tone[ch.state]}`}
          title={`${ch.label}: ${ch.detail}`}
        >
          <div className="flex items-center gap-1.5 font-mono text-[10px] uppercase tracking-[0.18em]">
            <span aria-hidden>{pip[ch.state]}</span>
            <span>{ch.label}</span>
          </div>
          <div className="mt-0.5 font-mono text-[10px] normal-case tracking-normal text-muted">
            {ch.detail}
          </div>
        </div>
      ))}
    </div>
  )
}
