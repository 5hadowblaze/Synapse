import { useMemo } from 'react'
import { Link } from 'react-router-dom'

/** Simple QR via public API — enough for pitch title-slide / handout. */
export function QrPage() {
  const url = useMemo(() => {
    if (typeof window === 'undefined') return 'http://localhost:5173'
    return window.location.origin
  }, [])

  const qrSrc = `https://api.qrserver.com/v1/create-qr-code/?size=280x280&bgcolor=070b10&color=3dffc4&data=${encodeURIComponent(url)}`

  return (
    <div className="flex min-h-full flex-col items-center justify-center gap-8 bg-ink px-6 text-center">
      <div>
        <div className="font-mono text-[10px] uppercase tracking-[0.35em] text-signal">
          Synapse
        </div>
        <h1 className="mt-2 font-display text-3xl font-semibold text-fog">Live dashboard</h1>
        <p className="mt-2 max-w-md text-sm text-muted">
          Scan to open the clinical HUD on your phone. Judges watch trials stream in while the
          athlete trains.
        </p>
      </div>

      <div className="rounded-sm border border-line bg-panel p-4">
        <img src={qrSrc} alt={`QR code for ${url}`} width={280} height={280} className="block" />
      </div>

      <code className="rounded-sm border border-line bg-panel-2 px-3 py-2 font-mono text-xs text-signal">
        {url}
      </code>

      <Link
        to="/"
        className="font-mono text-[10px] uppercase tracking-wider text-muted hover:text-fog"
      >
        ← Back to HUD
      </Link>
    </div>
  )
}
