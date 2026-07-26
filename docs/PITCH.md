# Synapse — Judge brief

**Cognitive pacing, PVT-anchored.** One–two pages for judges who dig.

---

> *It looks like a Pomodoro timer. It’s actually a pacing tool — for people whose fatigue isn’t a productivity problem, it’s a medical one.*

**Synapse** is an iPhone + Apple Watch app that learns your own physiological baseline at the start of a work block and tells you to stop *before* you overrun your limit — not after. The Pomodoro surface is intentional: people already know how to use one. What ends the block is your physiology, bookended by a published reaction-time test so you can see whether the nudge was right.

### Who it’s for

**Primary:** people with **energy-limiting conditions** — long COVID / ME-CFS, where pacing is NICE-recommended standard of care, and **post-concussion return-to-work**. For these users, “how you feel right now” is often the signal that fails: post-exertional cost arrives hours or days late. Pacing means stopping before the crash; the hard part is knowing where the line is.

**Secondary:** knowledge workers on the burnout track. Same mechanism, lower stakes.

We are not a hospital platform, not a diagnosis, and not a productivity timer with sensors bolted on. Clinic / rehab angles are upside only — never the cold open.

### What we measure (and what we don’t)

We don’t measure fatigue — nobody can, non-invasively, in real time. The output is always **“take a break,”** never a diagnosis.

**Default claim (heart-rate-led):** the signal doing the work is **heart rate** — your own resting rate over the first couple of minutes of the block, then sustained drift above that baseline. The Watch adds **wrist stillness and fidget**. The camera is **presence and attention** (is someone there, facing the screen) — not a fatigue input. A device diagnostic may later unlock a fuller multi-proxy story; until then we do not claim three-channel fusion.

**What keeps the story honest — PVT-B.** Either side of the block we run a 60-second **PVT-B** (Basner, Mollicone & Dinges, *Acta Astronautica* 69, 2011): the published brief psychomotor vigilance test used in aviation and sleep medicine. Parameters we ship: **1–4 s** inter-stimulus interval, lapse at **RT ≥ 355 ms** (not the 10-minute test’s 500 ms — Basner et al. lowered the cutoff because the brief protocol produces faster RTs), and an **anticipation floor** of **100 ms** (faster = false start, not a fast reaction). Without that floor, early taps drag the pre-block median down and inflate the slowdown. We report a within-person pre/post delta, never a score against population norms.

Two honest deviations from the paper: we run **60 s** rather than the validated 3 min, and a **3 s** no-response window rather than 30 s. Fewer trials → noisier median → which is exactly why the recap is a before/after delta minutes apart.

### Honest gaps

- **HRV next.** We cannot yet separate “stressed” from “fading” — both can raise heart rate. Heart-rate variability is the signal that separates them, and it is the next thing we would add.
- **No diagnosis.** Wellness signal and a dismissible nudge only. Never disease detection, never invented accuracy percentages.
- **Over-nudge on purpose.** We tune toward false positives. A false break costs ninety seconds; a missed one costs the afternoon — and for the primary user, potentially the next few days. That asymmetry is a product decision, which is why a noisy proxy is shippable.

### Architecture & sponsors

**Phone + Watch → WatchConnectivity → phone (sole Firebase writer) → Firestore.** Watch: workout HR + `CMMotionManager` @ 100 Hz. Phone: Focus HUD, PVT bookend, on-device face sensing (no face video to cloud), voice orb. Voice path: **Apple Speech → OpenAI Realtime (tools) → ElevenLabs TTS.** Live sessions on **Firebase** (`synapse-clinical-hz`). **Supabase is not in product** this weekend.

Dashboard for judges: https://synapse-clinical-hz.web.app

---

*One-line:* Cognitive pacing for people who can’t feel their limit until they’ve already crossed it — phone + Watch read your physiology against your own baseline, a 60-second PVT keeps the signal honest, and the voice coach calls the break.

*Canonical detail:* [`MASTER.md`](MASTER.md) · Source: `docs/PITCH.md` · PDF: `docs/Synapse-Pitch.pdf`
