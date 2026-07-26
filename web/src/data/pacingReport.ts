/**
 * Judge-facing session pacing report — narrative indicators inferred from
 * Firestore focus + optional PVT bookend fields. Wellness signal language only;
 * never a diagnosis or a productivity score.
 */
import { buildFocusModel } from './focusAnalysis'
import {
  FOCUS_EPOCH_INTERVAL_MS,
  focusFadeEvents,
  formatDurationSeconds,
  type FocusEpoch,
  type Session,
} from '../types/session'

/** mm:ss from block start — epoch i lands at (i + 1) × 30 s. */
function elapsedLabel(index: number): string {
  const totalSeconds = Math.round(((index + 1) * FOCUS_EPOCH_INTERVAL_MS) / 1000)
  const m = Math.floor(totalSeconds / 60)
  const s = totalSeconds % 60
  return `${m}:${String(s).padStart(2, '0')}`
}

export type PacingCardTone = 'steady' | 'easing' | 'break' | 'neutral'

export interface PacingReportCard {
  id: string
  eyebrow: string
  title: string
  body: string
  footnote?: string
  tone: PacingCardTone
  /** Optional headline number for projector distance. */
  highlight?: string
}

export interface PacingReport {
  generatedAt: number
  headline: string
  disclaimer: string
  cards: PacingReportCard[]
}

export const PACING_REPORT_DISCLAIMER =
  'These are session indicators inferred from your own baseline and optional reaction checks — a nudge toward pacing, not a diagnosis or a productivity score.'

function msLabel(ms: number | null | undefined): string {
  if (ms == null || !Number.isFinite(ms)) return '—'
  return `${Math.round(ms)} ms`
}

function reactionCard(session: Session): PacingReportCard | null {
  const hasBookend =
    session.pvtPreMedianMs != null ||
    session.pvtPostMedianMs != null ||
    session.pvtDirection != null
  if (!hasBookend) return null

  const pre = session.pvtPreMedianMs
  const post = session.pvtPostMedianMs
  const direction = session.pvtDirection
  const delta = session.pvtMedianDeltaMs
  const usable =
    (session.pvtPreValidTrials ?? 0) >= 3 && (session.pvtPostValidTrials ?? 0) >= 3

  let title = 'Reaction check'
  let body: string
  let tone: PacingCardTone = 'neutral'
  let highlight: string | undefined

  if (pre != null && post != null) {
    highlight = `${Math.round(pre)} → ${Math.round(post)} ms`
  }

  if (!usable || direction == null || delta == null) {
    body =
      'A reaction check ran, but there were not enough clean taps on both sides to compare. Treat this as incomplete, not as a fast result.'
  } else {
    const abs = Math.round(Math.abs(delta))
    switch (direction) {
      case 'slower':
        title = 'Reaction slowed'
        tone = 'break'
        body = `Median reaction time moved ${abs} ms slower after the block (${msLabel(pre)} → ${msLabel(post)}). That is an indicator alertness may have drifted — useful to check against the break nudge, not a medical finding.`
        break
      case 'faster':
        title = 'Reaction held or improved'
        tone = 'steady'
        body = `Median reaction time moved ${abs} ms faster after the block (${msLabel(pre)} → ${msLabel(post)}). An indicator the block did not cost vigilance in this sample — still not a diagnosis.`
        break
      case 'steady':
        title = 'Reaction held steady'
        tone = 'steady'
        body = `Median reaction time stayed within a small band (${msLabel(pre)} → ${msLabel(post)}). An indicator vigilance held through this block.`
        break
    }
  }

  const lapseLine =
    session.pvtPreLapses != null && session.pvtPostLapses != null
      ? ` Lapses (responses slower than 355 ms): ${session.pvtPreLapses} → ${session.pvtPostLapses}.`
      : ''

  return {
    id: 'reaction',
    eyebrow: 'Reaction check · PVT-B',
    title,
    body: body + lapseLine,
    footnote:
      'PVT-B means Psychomotor Vigilance Test, brief form — a published 60-second tap test used in sleep and aviation research. Synapse runs it before and after a block so you can see a measured change, not a vibe. Lapse threshold is 355 ms by design for the brief protocol.',
    tone,
    highlight,
  }
}

function wellnessCard(session: Session, epochs: FocusEpoch[]): PacingReportCard {
  const fadeEvents = focusFadeEvents(epochs)
  const fadeCount = session.focusFadeCount ?? fadeEvents.length
  const baselineReady = session.focusBaselineReady
  const extended = session.focusExtendedOnce === true
  const model = buildFocusModel(epochs)

  const settledHrs = epochs
    .slice(model.baselineEpochs)
    .map((e) => e.hrBpm)
    .filter((v): v is number => v != null)

  let hrClause = ''
  if (model.hrAnchor != null && settledHrs.length > 1) {
    const peak = Math.round(Math.max(...settledHrs))
    const anchor = Math.round(model.hrAnchor)
    if (peak > anchor + 3) {
      hrClause = ` Heart rate anchored near ${anchor} bpm and climbed toward ${peak} — one of the proxies behind the wellness signal.`
    } else {
      hrClause = ` Heart rate stayed near the session anchor (~${anchor} bpm).`
    }
  } else if (session.focusMeanHrBpm != null) {
    hrClause = ` Mean heart rate for the block was about ${Math.round(session.focusMeanHrBpm)} bpm.`
  }

  let title: string
  let body: string
  let tone: PacingCardTone

  if (baselineReady === false) {
    title = 'Baseline still building'
    tone = 'neutral'
    body =
      'The fade signal never finished learning this session’s baseline, so break suggestions would be less confident. Treat any nudge lightly.'
  } else if (fadeCount <= 0) {
    title = 'Signals held near baseline'
    tone = 'steady'
    body =
      'No break suggestion fired. Inferred indicator: proxies stayed close to your opening baseline for this block.'
  } else if (fadeCount === 1) {
    title = 'One early pause suggested'
    tone = 'easing'
    const when =
      fadeEvents.length > 0
        ? ` First catch around ${elapsedLabel(fadeEvents[0].index)} into the block.`
        : ''
    body = `The wellness signal suggested a break once.${when} Inferred indicator: drift from your own baseline held long enough to nudge — not a claim that you “failed” the block.`
  } else {
    title = 'Several pause indicators'
    tone = 'break'
    const times =
      fadeEvents.length > 0
        ? ` Caught at ${fadeEvents.map((e) => elapsedLabel(e.index)).join(', ')}.`
        : ''
    body = `The wellness signal suggested a break ${fadeCount} times.${times} Inferred indicator: repeated drift vs baseline — the product bias is to nudge early because a short pause costs less than overrunning.`
  }

  if (extended) {
    body += ' You locked in once after a suggestion — override is always allowed.'
  }

  body += hrClause

  return {
    id: 'wellness',
    eyebrow: 'Wellness signal',
    title,
    body,
    footnote:
      'Built from heart-rate trend vs your in-session baseline, plus wrist motion and camera presence when those channels are live. Indicator only.',
    tone,
    highlight: fadeCount > 0 ? `${fadeCount}× nudge` : '0 nudges',
  }
}

function blockCard(session: Session, epochs: FocusEpoch[]): PacingReportCard {
  const focused =
    session.focusFocusedSeconds ??
    (epochs.length > 0 ? (epochs[epochs.length - 1].index * 30_000) / 1000 : null)
  const brk = session.focusBreakSeconds

  const parts: string[] = []
  if (focused != null) parts.push(`Focused ${formatDurationSeconds(focused)}`)
  if (brk != null) parts.push(`break ${formatDurationSeconds(brk)}`)
  const summary = parts.length > 0 ? parts.join(' · ') : 'Block timing still writing'

  return {
    id: 'block',
    eyebrow: 'Block summary',
    title: summary,
    body:
      session.status === 'complete'
        ? 'Session marked complete. Numbers below are what the phone wrote for this pacing block.'
        : 'Block still active — report uses the latest written fields and may update as the phone finishes.',
    tone: 'neutral',
    highlight: focused != null ? formatDurationSeconds(focused) : undefined,
  }
}

/** Build a pacing report from live session + epoch stream. */
export function buildPacingReport(
  session: Session,
  epochs: FocusEpoch[],
): PacingReport {
  const cards: PacingReportCard[] = [
    blockCard(session, epochs),
    wellnessCard(session, epochs),
  ]
  const reaction = reactionCard(session)
  if (reaction) cards.push(reaction)

  const fadeCount = session.focusFadeCount ?? focusFadeEvents(epochs).length
  let headline: string
  if (reaction?.tone === 'break') {
    headline = 'Pacing report — reaction slowed after the block'
  } else if (fadeCount > 0) {
    headline = 'Pacing report — wellness signal suggested pausing'
  } else {
    headline = 'Pacing report — block indicators'
  }

  return {
    generatedAt: Date.now(),
    headline,
    disclaimer: PACING_REPORT_DISCLAIMER,
    cards,
  }
}
