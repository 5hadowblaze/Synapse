import {
  focusFadeThreshold,
  formatDurationSeconds,
  type Session,
} from '../../types/session'

interface FocusRecapPanelProps {
  session: Session
}

interface Row {
  label: string
  field: string
  value: string
  tone?: 'default' | 'signal' | 'amber' | 'muted'
}

const toneClass: Record<NonNullable<Row['tone']>, string> = {
  default: 'text-fog',
  signal: 'text-signal',
  amber: 'text-amber',
  muted: 'text-muted',
}

function flag(value: boolean | null): { value: string; tone: Row['tone'] } {
  if (value == null) return { value: 'not written', tone: 'muted' }
  return value ? { value: 'yes', tone: 'signal' } : { value: 'no', tone: 'default' }
}

export function FocusRecapPanel({ session }: FocusRecapPanelProps) {
  const recapWritten = session.focusFocusedSeconds != null
  const threshold = focusFadeThreshold(session)
  const extended = flag(session.focusExtendedOnce)
  const baselineReady = flag(session.focusBaselineReady)

  const rows: Row[] = [
    {
      label: 'Focused',
      field: 'focusFocusedSeconds',
      value: formatDurationSeconds(session.focusFocusedSeconds),
      tone: 'signal',
    },
    {
      label: 'On break',
      field: 'focusBreakSeconds',
      value: formatDurationSeconds(session.focusBreakSeconds),
    },
    {
      label: 'Fade catches',
      field: 'focusFadeCount',
      value: session.focusFadeCount != null ? String(session.focusFadeCount) : '—',
      tone: session.focusFadeCount ? 'amber' : 'default',
    },
    {
      label: 'Mean HR',
      field: 'focusMeanHrBpm',
      value:
        session.focusMeanHrBpm != null
          ? `${session.focusMeanHrBpm.toFixed(1)} bpm`
          : '—',
    },
    {
      label: 'Locked in again',
      field: 'focusExtendedOnce',
      value: extended.value,
      tone: extended.tone,
    },
    {
      label: 'Baseline ready',
      field: 'focusBaselineReady',
      value: baselineReady.value,
      tone: baselineReady.tone,
    },
    {
      label: 'Fade baseline',
      field: 'baselineGapMs',
      value: session.baselineGapMs != null ? session.baselineGapMs.toFixed(3) : '—',
    },
    {
      label: 'Baseline σ',
      field: 'baselineStdMs',
      value: session.baselineStdMs != null ? session.baselineStdMs.toFixed(3) : '—',
    },
    {
      label: 'Trip line',
      field: 'baseline + 2σ',
      value: threshold != null ? threshold.toFixed(3) : '—',
      tone: 'amber',
    },
  ]

  return (
    <div className="flex h-full flex-col rounded-sm border border-line bg-panel/70">
      <div className="flex items-center justify-between border-b border-line px-4 py-2">
        <h2 className="font-display text-sm font-medium tracking-wide text-fog">Recap</h2>
        <span
          className={`font-mono text-[10px] uppercase tracking-wider ${
            recapWritten ? 'text-signal' : 'text-muted'
          }`}
        >
          {recapWritten ? 'written' : 'block in progress'}
        </span>
      </div>
      <dl className="divide-y divide-line/60">
        {rows.map((row) => (
          <div
            key={row.field}
            className="flex items-baseline justify-between gap-3 px-4 py-[7px]"
          >
            <dt className="min-w-0">
              <span className="block text-[13px] text-fog">{row.label}</span>
              <span className="block truncate font-mono text-[9.5px] tracking-wide text-muted">
                {row.field}
              </span>
            </dt>
            <dd
              className={`shrink-0 font-mono text-[13px] tabular-nums ${
                toneClass[row.tone ?? 'default']
              }`}
            >
              {row.value}
            </dd>
          </div>
        ))}
      </dl>
    </div>
  )
}
