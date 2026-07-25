# Synapse Pitch Checklist

## Hardware / day-of

- [ ] **Series 5 charged to 100%** — keep the charger on the demo table (workout session drains fast).
- [ ] iPhone Face ID device mounted on tripod at **60–70 cm**.
- [ ] Personal hotspot ready (prefer over venue Wi-Fi).
- [ ] Backup demo video on the laptop (airplane-mode insurance).
- [ ] Watch + phone paired; WatchConnectivity confirmed with a test punch.

## Projection / AirPlay

- [ ] Project the **clinical dashboard** full-screen (audience view).
- [ ] **AirPlay / mirror the iPhone** into a small corner of the projection so the room sees the 3×3 targets light up.
- [ ] Disable auto-lock on phone and laptop; night-shift / True Tone off if colors look wrong on the projector.
- [ ] Confirm dashboard URL reachable from judge phones (same hotspot / network).

## Dashboard QR

- [ ] **Live Hosting:** https://synapse-clinical-hz.web.app
- [ ] **Pitch QR page:** https://synapse-clinical-hz.web.app/qr (encodes the production URL).
- [ ] Open `/qr` on the laptop (or title slide) — QR encodes the live dashboard origin.
- [ ] Put the QR on the **title slide**; tell judges to scan while you talk.
- [ ] Prefer the Hosting URL above over hotspot IP / tunnel / `localhost`.
- [ ] Smoke-test: scan → HUD loads → Demo mode works offline.

## Rehearse script (≈ 3 minutes)

1. **Hook (20s)** — Two clocks, one gap. Phone sees the eyes; Watch feels the strike. Nothing else measures both.
2. **Live start (40s)** — Athlete on the grid. Dashboard tiles update: Visual RT, Motor RT, **Cognitive-Motor Gap**.
3. **Credibility (20s)** — Point at clock sync badge (offset + RTT). Cristian's algorithm — not Bluetooth arrival time.
4. **Build (60s)** — Baseline locks after trial 10. Gap holds… then opens.
5. **Money line (when red banner fires)**  
   > *The system detected the crash four trials before the athlete could feel it.*
6. **Close (20s)** — Judges: scan the QR; you're looking at the same live session.

## Fail-safes

- [ ] **Demo mode** button on the HUD loads canned JSON if Firebase/venue net dies.
- [ ] Pre-seed `sessions/demo-session-001` in Firestore before stage time.
- [ ] Rules still open for the demo window (expire comment in `firestore.rules`: 2026-08-01).

## Freeze

**H46–48: code freeze.** Pitch only. Any code written here is a bug.
