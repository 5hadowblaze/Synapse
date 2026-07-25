import { useState } from 'react'
import type { DataMode } from '../hooks/useSession'
import type { SessionModule } from '../types/session'

interface SessionPickerProps {
  sessionId: string
  onChange: (id: string) => void
  mode: DataMode
  isDemoForced: boolean
  onForceDemo: (module?: SessionModule) => void
  onExitDemo: () => void
  error: string | null
  module: SessionModule | null
}

export function SessionPicker({
  sessionId,
  onChange,
  mode,
  isDemoForced,
  onForceDemo,
  onExitDemo,
  error,
  module,
}: SessionPickerProps) {
  const [draft, setDraft] = useState(sessionId)

  return (
    <div className="flex flex-wrap items-center gap-3">
      <form
        className="flex items-center gap-2"
        onSubmit={(e) => {
          e.preventDefault()
          onChange(draft.trim() || sessionId)
        }}
      >
        <label className="font-mono text-[10px] uppercase tracking-[0.2em] text-muted">
          Session
        </label>
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          className="w-52 rounded-sm border border-line bg-ink px-2 py-1.5 font-mono text-xs text-fog outline-none focus:border-signal/50"
          spellCheck={false}
        />
        <button
          type="submit"
          className="rounded-sm border border-line bg-panel-2 px-3 py-1.5 font-mono text-[10px] uppercase tracking-wider text-fog hover:border-signal/40 hover:text-signal"
        >
          Load
        </button>
      </form>

      {module ? (
        <div className="rounded-sm border border-line px-2 py-1 font-mono text-[10px] uppercase tracking-[0.18em] text-fog">
          {module === 'kineticClock' ? 'Kinetic Clock' : 'Vision PVT'}
        </div>
      ) : null}

      <div
        className={`rounded-sm border px-2 py-1 font-mono text-[10px] uppercase tracking-[0.18em] ${
          mode === 'live'
            ? 'border-signal/40 text-signal'
            : mode === 'demo'
              ? 'border-amber/40 text-amber'
              : mode === 'connecting'
                ? 'border-visual/40 text-visual'
                : 'border-alert/40 text-alert'
        }`}
      >
        {mode === 'live' ? '● Live' : mode === 'demo' ? '◆ Demo' : mode === 'connecting' ? '… Sync' : '✕ Error'}
      </div>

      {isDemoForced ? (
        <button
          type="button"
          onClick={onExitDemo}
          className="rounded-sm border border-line px-2 py-1 font-mono text-[10px] uppercase tracking-wider text-muted hover:text-fog"
        >
          Exit demo
        </button>
      ) : null}

      <button
        type="button"
        onClick={() => onForceDemo('visionPvt')}
        className="rounded-sm border border-visual/30 px-2 py-1 font-mono text-[10px] uppercase tracking-wider text-visual hover:bg-visual/10"
      >
        Demo vision
      </button>
      <button
        type="button"
        onClick={() => onForceDemo('kineticClock')}
        className="rounded-sm border border-motor/30 px-2 py-1 font-mono text-[10px] uppercase tracking-wider text-motor hover:bg-motor/10"
      >
        Demo kinetic
      </button>

      {error ? (
        <span className="max-w-md truncate font-mono text-[11px] text-muted" title={error}>
          {error}
        </span>
      ) : null}
    </div>
  )
}
