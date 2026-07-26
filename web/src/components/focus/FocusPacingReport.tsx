import { useMemo, useState } from 'react'
import {
  buildPacingReport,
  type PacingCardTone,
  type PacingReportCard,
} from '../../data/pacingReport'
import type { FocusEpoch, Session } from '../../types/session'

interface FocusPacingReportProps {
  session: Session
  epochs: FocusEpoch[]
}

const toneBorder: Record<PacingCardTone, string> = {
  steady: 'border-signal/35',
  easing: 'border-amber/40',
  break: 'border-amber/55',
  neutral: 'border-line',
}

const toneText: Record<PacingCardTone, string> = {
  steady: 'text-signal',
  easing: 'text-amber',
  break: 'text-amber',
  neutral: 'text-fog',
}

function ReportCard({ card }: { card: PacingReportCard }) {
  return (
    <article
      className={`rounded-sm border bg-panel/80 px-4 py-4 ${toneBorder[card.tone]}`}
    >
      <div className="font-mono text-[10px] uppercase tracking-[0.18em] text-muted">
        {card.eyebrow}
      </div>
      <div className="mt-2 flex flex-wrap items-baseline justify-between gap-3">
        <h3 className={`font-display text-lg font-semibold ${toneText[card.tone]}`}>
          {card.title}
        </h3>
        {card.highlight ? (
          <span className="font-mono text-sm tabular-nums text-fog">{card.highlight}</span>
        ) : null}
      </div>
      <p className="mt-2 text-[13px] leading-relaxed text-fog/90">{card.body}</p>
      {card.footnote ? (
        <p className="mt-3 border-t border-line/70 pt-3 text-[11px] leading-relaxed text-muted">
          {card.footnote}
        </p>
      ) : null}
    </article>
  )
}

/**
 * On-demand pacing report for judges. Hidden until Generate — keeps the live HUD
 * clean, then expands narrative indicators (including plain-language PVT).
 */
export function FocusPacingReport({ session, epochs }: FocusPacingReportProps) {
  const [open, setOpen] = useState(false)

  const report = useMemo(
    () => (open ? buildPacingReport(session, epochs) : null),
    [open, session, epochs],
  )

  return (
    <section className="rounded-sm border border-line bg-panel/50">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line px-4 py-3">
        <div>
          <h2 className="font-display text-sm font-medium tracking-wide text-fog">
            Session pacing report
          </h2>
          <p className="mt-0.5 text-[11px] text-muted">
            Narrative indicators for this block — tap generate when you want the story
          </p>
        </div>
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="rounded-sm border border-signal/50 bg-signal/10 px-3 py-1.5 font-mono text-[11px] uppercase tracking-wider text-signal transition hover:bg-signal/20"
        >
          {open ? 'Hide report' : 'Generate report'}
        </button>
      </div>

      {report ? (
        <div className="space-y-4 px-4 py-4">
          <div>
            <p className="font-display text-base font-semibold text-fog">{report.headline}</p>
            <p className="mt-1 max-w-3xl text-[12px] leading-relaxed text-muted">
              {report.disclaimer}
            </p>
          </div>
          <div className="grid gap-3 lg:grid-cols-3">
            {report.cards.map((card) => (
              <ReportCard key={card.id} card={card} />
            ))}
          </div>
        </div>
      ) : null}
    </section>
  )
}
