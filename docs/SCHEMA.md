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
  lastHeartRatePhoneMs: number | null   // uptime-domain phone clock (watch + Cristian offset) — fusion math only
  lastHeartRateWatchMs: number | null
  lastHeartRateSource: string | null    // e.g. "workoutBuilder" | "phoneCache"
  lastHeartRateHkStart: number | null   // HK window (timeIntervalSinceReferenceDate)
  lastHeartRateHkEnd: number | null
  lastHeartRateReceivedAtMs: number | null  // wall-clock ms when phone wrote the sample (dashboard freshness)
  lastEpochIndex: number | null         // denormalised from latest focus epoch write
  lastEpochAtMs: number | null          // wall-clock ms of latest epoch write
  lastEpochPhase: string | null

live/focus                            // pitch pointer — web "Find live" without guessing UUID
  sessionId: string | null
  status: "active" | "idle"
  module: "focusDesk" | null
  updatedAtMs: number

sessions/{sessionId}/trials/{index}
  index: number                   // 0-based trial index (doc id may mirror this)
  targetCell: number              // 3×3 row-major 0..8; vision flashes peripherals (not 4); kinetic may mirror octant
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

// Focus PVT bookend lives in sessions/{id}/pvt/{stage} — see "PVT bookend" below.
```

## Modules

- **visionPvt** — lab: peripheral single-flash PVT on a 3×3 field (center = fixation; outer cells flash). Saccade onset / arousal via TrueDepth. No Watch required.
- **kineticClock** — 8-direction clock; Watch strike timing + octant. `spatialMatch` flags accuracy; motor RT always persisted on strike.
- **focusDesk** — consumer pacing block (desk Focus). No lab PVT flashes / Kinetic punches. Session fields may include `focusFocusedSeconds`, `focusBreakSeconds`, `focusFadeCount`, `focusMeanHrBpm`, `focusExtendedOnce`, `focusBaselineReady`, plus denormalised `lastEpochIndex` / `lastEpochAtMs` / `lastEpochPhase` and wall-clock `lastHeartRateReceivedAtMs`. Sparse samples live under `sessions/{id}/epochs/{index}` (`phase`, `remainingMs`, `fadeScore`, `hrBpm`, `arousalIndex`, `motionEnergy`, `fadeSuggested`, `writtenAtMs`). Baseline fields reuse `baselineGapMs` / `baselineStdMs` for the fade-score window. Active block pointer: `live/focus`.

## Octants (0..7)

`12, 1:30, 3, 4:30, 6, 7:30, 9, 10:30`

## Break-point

After the first 10 valid trials, compute `baselineGapMs` / `baselineStdMs` from the module metric
(vision: `visualRtMs`; kinetic: `motorRtMs`).  
When a later trial exceeds baseline by **2σ**, set `breakPointTrial` on the session doc.

## PVT bookend (tap reaction check)

60 s tap-response task run before and after a Focus block — see [MASTER.md](MASTER.md) §3. Written by `SessionWriter.writeTapPVT` / `writeTapPVTComparison`.

```
sessions/{sessionId}
  // Summary per stage, denormalised onto the session doc so the dashboard needs no join.
  // {Stage} is Pre | Post | Standalone.
  pvt{Stage}MedianMs: number | null
  pvt{Stage}MeanMs: number | null
  pvt{Stage}Lapses: number          // response ≥ 355 ms (PVT-B threshold), or no response
  pvt{Stage}FalseStarts: number     // error of commission — not counted as a lapse
  pvt{Stage}ValidTrials: number
  // Pre → post comparison (written once, after the post run)
  pvtMedianDeltaMs: number | null
  pvtPercentChange: number | null
  pvtLapseDelta: number             // post lapses − pre lapses
  pvtDirection: "slower" | "faster" | "steady"   // ±10 ms dead band

sessions/{sessionId}/pvt/{stage}    // stage = "pre" | "post" | "standalone"
  stage: string
  startedAt: number                 // ms epoch
  durationSeconds: number
  medianRtMs / meanRtMs / fastestRtMs / slowestRtMs: number | null
  lapses: number
  falseStarts: number
  validTrials: number
  attemptedTrials: number
  lapseThresholdMs: number          // 355, recorded so the convention is auditable
  trials: Array<{ index, isiMs, reactionMs?, falseStart, timedOut, lapse }>
                                    // isiMs is measured from the previous response and
                                    // includes the feedback dwell (PVT-B convention).
                                    // reactionMs is present on anticipations (<100 ms,
                                    // scored as falseStart), absent on pre-stimulus taps
                                    // and no-responses.
```

Protocol is **PVT-B** (Basner, Mollicone & Dinges 2011): 1–4 s intervals, lapse at ≥355 ms, responses <100 ms are false starts. The threshold differs from the 10-minute PVT's 500 ms by design — consumers of this data should read `lapseThresholdMs` rather than assume 500.

A run needs **≥3 valid trials** to be usable; below that, treat the summary as absent rather than as a fast result. `pvtMedianDeltaMs` / `pvtPercentChange` / `pvtDirection` are only written when *both* stages clear that bar.

## Focus check-in (optional talk-through)

Self-report only — written by `SessionWriter.writeFocusCheckIn` after session complete (follow-up patch). Never inferred from sensors. See [MASTER.md](MASTER.md) §3 voice / §13.

```
sessions/{sessionId}
  checkInAt: number                 // ms epoch
  checkInFeltEnergy: number | null  // 1–5 self-report
  checkInFeltClarity: number | null // 1–5
  checkInNudgeMatched: boolean | null
  checkInWouldStopEarlier: boolean | null
  checkInSummary: string | null     // agent paraphrase of user words
  checkInSkipped: boolean           // true if talk-through never completed
```

## Known gaps

- `web/src/types/session.ts` omits the `lastHeartRateHkStart` / `lastHeartRateHkEnd` fields defined above. Harmless today (nothing reads them), but the two files are meant to match.

## Shared TypeScript types

See `web/src/types/session.ts` — keep in sync with this document and the iOS models.
