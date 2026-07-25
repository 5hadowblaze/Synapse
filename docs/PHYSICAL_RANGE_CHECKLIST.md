# Physical Range Checklist (Hour 1)

TrueDepth face tracking degrades past roughly **70 cm**, but a jab extends **60–70 cm** from the shoulder. These barely coexist. Run this on a physical iPhone with Face ID **before** relying on the trial engine.

## Setup

1. Mount the iPhone on a tripod in portrait, screen facing the athlete.
2. Measure **60–70 cm** from the front camera to the athlete’s face (tape measure).
3. Launch Synapse; confirm HUD chip shows **Tracked** (green) and distance ≈ measured cm.
4. Athlete stands square; keep shoulders behind the measurement plane so jabs stop short of the glass.

## AR mesh + gaze ray (setup screen)

Before Start, the full-bleed TrueDepth preview must prove the face pipeline is alive:

1. Confirm the **wireframe face mesh** sticks to the face (not a frozen silhouette).
2. Keep the head still and glance **left / right** with the eyes only — the **cyan gaze ray** must move with the glance (not only when the head turns).
3. Tap **Calibrate** while looking at phone center — approx gaze crosshair (after Start) should sit near **cell 4**. Cursor is confidence only; do **not** treat cell hit as clinical accuracy.
4. Fail if mesh never appears, ray is frozen, or tracking flickers at rest at 60–70 cm.

## Face hold under jabs

1. With tracking green, throw **10 jabs** that stop **short of the screen** (near-misses).
2. Watch the HUD: face should remain **Tracked** through the sequence (PIP mesh may wobble but should not stay Lost).
3. If tracking drops mid-jab → move the athlete **closer** and punch **past** the phone (not at it). Re-test.
4. Note the working distance on this sheet: __________ cm.

## Tripod vibration

1. Throw 5 near-miss jabs that create a small breeze / light bump on the mount.
2. Confirm AR face anchor does **not** reset (no prolonged Lost / red ring).
3. If vibration breaks tracking → stiffen the tripod, add weight to the base, or soft-pad the mount. Re-test.

## Pass / fail

| Check | Pass? |
| --- | --- |
| Face tracked at 60–70 cm at rest | |
| Mesh visible and stuck to face | |
| Cyan gaze ray moves on eye glance (L/R), not only head turn | |
| Calibrate centers approx gaze near cell 4 | |
| Face survives 10 stop-short jabs | |
| Tripod vibration does not break tracking | |
| Ergonomics decision locked (punch at vs past phone) | |

**Decision:** If tracking fails at jab distance, lock ergonomics now (athlete closer, punches past phone). Do not discover this in hour 40.

**Pitch note:** Timing uses saccade **onset** after the target flash (60 Hz), not laboratory screen-gaze pixel accuracy on a phone.
