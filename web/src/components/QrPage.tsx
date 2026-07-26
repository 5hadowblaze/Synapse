import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import { SynapseMark } from './SynapseMark'

/** Simple QR via public API — enough for pitch title-slide / handout. */
/** Production Hosting URL — pitch QR must encode this, not localhost. */
const PRODUCTION_DASHBOARD_URL = 'https://synapse-clinical-hz.web.app'

export function QrPage() {
  const url = useMemo(() => {
    // Prefer live Hosting origin when served from Firebase; otherwise bake production.
    if (typeof window !== 'undefined') {
      const origin = window.location.origin
      if (origin.includes('synapse-clinical-hz')) return origin
    }
    return PRODUCTION_DASHBOARD_URL
  }, [])

  const qrSrc = `https://api.qrserver.com/v1/create-qr-code/?size=280x280&bgcolor=070b10&color=3dffc4&data=${encodeURIComponent(url)}`

  return (
    <div className="flex min-h-full flex-col items-center justify-center gap-8 bg-ink px-6 text-center">
      <div>
        <div className="flex items-center justify-center gap-2.5">
          <SynapseMark className="h-7 w-7 shrink-0 rounded-[7px] ring-1 ring-line" />
          <div className="font-mono text-[10px] uppercase tracking-[0.35em] text-signal">
            Synapse
          </div>
        </div>
        <h1 className="mt-2 font-display text-3xl font-semibold text-fog">Live dashboard</h1>
        <p className="mt-2 max-w-md text-sm text-muted">
          Scan to open the HUD on your phone — heart rate, fade score, and every fade catch stream
          in live while the focus block runs.
        </p>
      </div>

      <div className="surface-lift rounded-sm border border-line bg-panel p-4">
        <img src={qrSrc} alt={`QR code for ${url}`} width={280} height={280} className="block" />
      </div>

      <code className="rounded-sm border border-line bg-panel-2 px-3 py-2 font-mono text-xs text-signal">
        {url}
      </code>

      <Link
        to="/"
        className="btn-press font-mono text-[10px] uppercase tracking-wider text-muted hover:text-fog"
      >
        ← Back to HUD
      </Link>
    </div>
  )
}
