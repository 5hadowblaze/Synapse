import type { DataMode } from '../hooks/useSession'
import type { FocusEpoch, Session } from '../types/session'

export type ChannelLiveState = 'live' | 'stale' | 'missing' | 'demo' | 'idle'

export interface LiveChannel {
  key: string
  label: string
  state: ChannelLiveState
  detail: string
}

const HR_LIVE_MS = 15_000
const EPOCH_LIVE_MS = 45_000

function ageLabel(ageMs: number | null): string {
  if (ageMs == null || !Number.isFinite(ageMs)) return '—'
  if (ageMs < 1_500) return 'just now'
  if (ageMs < 60_000) return `${Math.round(ageMs / 1000)}s ago`
  return `${Math.round(ageMs / 60_000)}m ago`
}

function stateFromAge(
  ageMs: number | null,
  liveWithinMs: number,
  hasValue: boolean,
): ChannelLiveState {
  if (!hasValue) return 'missing'
  if (ageMs == null) return 'stale'
  if (ageMs <= liveWithinMs) return 'live'
  return 'stale'
}

/**
 * Per-channel live/stale/missing for the Focus HUD.
 * HR uses wall-clock `lastHeartRateReceivedAtMs` (not uptime phoneMs).
 * Epoch channels use session `lastEpochAtMs` + field presence on the latest epoch.
 */
export function buildLiveChannels(args: {
  mode: DataMode
  session: Session | null
  epochs: FocusEpoch[]
  nowMs?: number
}): LiveChannel[] {
  const { mode, session, epochs } = args
  const now = args.nowMs ?? Date.now()

  if (mode === 'demo') {
    return [
      { key: 'firestore', label: 'Session', state: 'demo', detail: 'canned snapshot' },
      { key: 'hr', label: 'Watch HR', state: 'demo', detail: 'not from Watch' },
      { key: 'fade', label: 'Fade score', state: 'demo', detail: 'simulated' },
      { key: 'motion', label: 'Motion', state: 'demo', detail: 'simulated' },
      { key: 'arousal', label: 'Face', state: 'demo', detail: 'simulated' },
    ]
  }

  if (!session || mode !== 'live') {
    return [
      {
        key: 'firestore',
        label: 'Session',
        state: mode === 'connecting' ? 'idle' : 'missing',
        detail: mode === 'connecting' ? 'connecting…' : 'no session loaded',
      },
      { key: 'hr', label: 'Watch HR', state: 'missing', detail: '—' },
      { key: 'fade', label: 'Fade score', state: 'missing', detail: '—' },
      { key: 'motion', label: 'Motion', state: 'missing', detail: '—' },
      { key: 'arousal', label: 'Face', state: 'missing', detail: '—' },
    ]
  }

  const hrAge =
    session.lastHeartRateReceivedAtMs != null
      ? now - session.lastHeartRateReceivedAtMs
      : null
  const epochAge =
    session.lastEpochAtMs != null ? now - session.lastEpochAtMs : null
  const latest = epochs.length > 0 ? epochs[epochs.length - 1] : null

  const sessionDetail =
    session.status === 'complete'
      ? 'complete'
      : epochAge != null
        ? `epoch ${session.lastEpochIndex ?? latest?.index ?? '—'} · ${ageLabel(epochAge)}`
        : 'waiting for first epoch (~30s)'

  return [
    {
      key: 'firestore',
      label: 'Session',
      state: session.status === 'active' ? 'live' : 'stale',
      detail: sessionDetail,
    },
    {
      key: 'hr',
      label: 'Watch HR',
      state: stateFromAge(hrAge, HR_LIVE_MS, session.lastHeartRateBpm != null),
      detail:
        session.lastHeartRateBpm != null
          ? `${Math.round(session.lastHeartRateBpm)} bpm · ${ageLabel(hrAge)}`
          : 'awaiting Watch sample',
    },
    {
      key: 'fade',
      label: 'Fade score',
      state: stateFromAge(epochAge, EPOCH_LIVE_MS, latest?.fadeScore != null),
      detail:
        latest?.fadeScore != null
          ? `${latest.fadeScore.toFixed(3)} · ${ageLabel(epochAge)}`
          : epochs.length === 0
            ? 'no epoch yet'
            : 'no score this epoch',
    },
    {
      key: 'motion',
      label: 'Motion',
      state: stateFromAge(epochAge, EPOCH_LIVE_MS, latest?.motionEnergy != null),
      detail:
        latest?.motionEnergy != null
          ? `${latest.motionEnergy.toFixed(2)} · ${ageLabel(epochAge)}`
          : 'no Watch IMU this epoch',
    },
    {
      key: 'arousal',
      label: 'Face',
      state: stateFromAge(epochAge, EPOCH_LIVE_MS, latest?.arousalIndex != null),
      detail:
        latest?.arousalIndex != null
          ? `${latest.arousalIndex.toFixed(3)} · ${ageLabel(epochAge)}`
          : 'camera off / face lost',
    },
  ]
}
