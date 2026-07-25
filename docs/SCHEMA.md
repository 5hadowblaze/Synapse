# Synapse Firestore Schema

> **Product / plan / ship status:** [`MASTER.md`](MASTER.md). This file remains the canonical **field-level** Firestore contract.

Frozen for the hackathon so iOS (writer) and web (reader) can build in parallel.

## Collections

```
sessions/{sessionId}
  athleteId: string
  module: "kineticClock" | "visionPvt" | "focusDesk"
  startedAt: Timestamp | number   // ms epoch ok for demo
  status: "active" | "complete"
  clockOffsetMs: number           // Cristian's algorithm offset (credibility)
  clockRttMs: number              // lowest-RTT handshake sample
  baselineGapMs: number | null    // mean metric after trial 10 (gap or module RT)
  baselineStdMs: number | null    // stddev of baseline window
  breakPointTrial: number | null  // trial index when fatigue onset fires
  // Discrete Watch workout HR (Series 5 ~1 sample / few seconds — not camera-frame locked)
  lastHeartRateBpm: number | null
  lastHeartRatePhoneMs: number | null   // phone-clock ms (watch + Cristian offset)
  lastHeartRateWatchMs: number | null
  lastHeartRateSource: string | null    // e.g. "workoutBuilder"
  lastHeartRateHkStart: number | null   // HK window (timeIntervalSinceReferenceDate)
  lastHeartRateHkEnd: number | null

sessions/{sessionId}/trials/{index}
  index: number                   // 0-based trial index (doc id may mirror this)
  targetCell: number              // legacy 3×3; vision uses 4 (center); kinetic may mirror octant
  targetOnsetMs: number           // phone clock, CADisplayLink.targetTimestamp
  saccadeOnsetMs: number | null   // vision PVT
  gazeSettleMs: number | null
  strikeMs: number | null         // kinetic: watch sample time + clock offset
  visualRtMs: number | null       // saccadeOnset - targetOnset
  motorRtMs: number | null        // strike - targetOnset (always kept when strike arrives)
  cognitiveMotorGapMs: number | null  // fusion only (out of v1)
  peakG: number | null
  arousalIndex: number | null
  targetOctant: number | null     // 0..7 kinetic only
  detectedOctant: number | null   // 0..7 kinetic only
  spatialMatch: boolean | null    // detected == target; wrong direction flagged, not discarded
  valid: boolean
  invalidReason: string | null

sessions/{sessionId}/trials/{index}/gaze/{docId}
  // Prefer a single packed window doc (e.g. id "window") covering -200ms..+800ms
  // Vision PVT only; kinetic may omit.
  t0Ms: number
  samples: Array<{ dt: number, x: number, y: number, z: number }>
  // ~60 packed samples — not a continuous 60Hz stream
```

## Modules

- **visionPvt** — classic single-flash PVT (saccade / arousal). No Watch required.
- **kineticClock** — 8-direction clock; Watch strike timing + octant. `spatialMatch` flags accuracy; motor RT always persisted on strike.
- **focusDesk** — health-aware Pomodoro (desk Focus). No PVT flashes / Kinetic punches. Session fields may include `focusFocusedSeconds`, `focusBreakSeconds`, `focusFadeCount`, `focusMeanHrBpm`, `focusExtendedOnce`, `focusBaselineReady`. Sparse samples live under `sessions/{id}/epochs/{index}` (`phase`, `remainingMs`, `fadeScore`, `hrBpm`, `arousalIndex`, `motionEnergy`, `fadeSuggested`). Baseline fields reuse `baselineGapMs` / `baselineStdMs` for the fade-score window.

## Octants (0..7)

`12, 1:30, 3, 4:30, 6, 7:30, 9, 10:30`

## Break-point

After the first 10 valid trials, compute `baselineGapMs` / `baselineStdMs` from the module metric
(vision: `visualRtMs`; kinetic: `motorRtMs`).  
When a later trial exceeds baseline by **2σ**, set `breakPointTrial` on the session doc.

## Shared TypeScript types

See `web/src/types/session.ts` — keep in sync with this document and the iOS models.
