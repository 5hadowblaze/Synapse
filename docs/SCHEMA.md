# Synapse Firestore Schema

Frozen for the hackathon so iOS (writer) and web (reader) can build in parallel.

## Collections

```
sessions/{sessionId}
  athleteId: string
  startedAt: Timestamp | number   // ms epoch ok for demo
  status: "active" | "complete"
  clockOffsetMs: number           // Cristian's algorithm offset (credibility)
  clockRttMs: number              // lowest-RTT handshake sample
  baselineGapMs: number | null    // mean Cognitive-Motor Gap after trial 10
  baselineStdMs: number | null    // stddev of baseline window
  breakPointTrial: number | null  // trial index when fatigue onset fires

sessions/{sessionId}/trials/{index}
  index: number                   // 0-based trial index (doc id may mirror this)
  targetCell: number              // 0..8 on the 3×3 grid
  targetOnsetMs: number           // phone clock, CADisplayLink.targetTimestamp
  saccadeOnsetMs: number
  gazeSettleMs: number
  strikeMs: number                // watch sample time + clock offset
  visualRtMs: number              // saccadeOnset - targetOnset
  motorRtMs: number               // strike - targetOnset
  cognitiveMotorGapMs: number     // HERO: strike - saccadeOnset
  peakG: number
  arousalIndex: number
  valid: boolean

sessions/{sessionId}/trials/{index}/gaze/{docId}
  // Prefer a single packed window doc (e.g. id "window") covering -200ms..+800ms
  t0Ms: number
  samples: Array<{ dt: number, x: number, y: number, z: number }>
  // ~60 packed samples — not a continuous 60Hz stream
```

## Hero metric

**Cognitive-Motor Gap** = `strikeMs - saccadeOnsetMs`  
Interval between gaze acquiring the target and the body executing the strike.

## Break-point

After the first 10 valid trials, compute `baselineGapMs` / `baselineStdMs`.  
When a later trial's `cognitiveMotorGapMs` exceeds baseline by **2σ**, set `breakPointTrial` on the session doc. Dashboard reacts live (red banner + audio).

## Shared TypeScript types

See `web/src/types/session.ts` — keep in sync with this document and the iOS `Codable` models.
