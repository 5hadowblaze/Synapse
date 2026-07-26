# Synapse

**Cognitive pacing, PVT-anchored.** An iPhone + Apple Watch companion that looks like a Pomodoro timer — and is actually a pacing tool for people whose fatigue isn’t a productivity problem, it’s a medical one.

Synapse learns *your* physiological baseline at the start of a work block, watches cheap proxies against that baseline, and nudges a break *before* you overrun your limit. A 60-second **PVT-B** (published brief psychomotor vigilance test) bookends the block so the recap shows a measured reaction-time change, not a vibe. A voice coach can talk the session through; a web dashboard is the microscope for the fine-grained timeline.

> **One-liner:** Cognitive pacing for people who can’t feel their limit until they’ve already crossed it — phone + Watch read your physiology against your own baseline, a 60-second PVT keeps the signal honest, and the voice coach calls the break.

**Canonical source of truth:** [`docs/MASTER.md`](docs/MASTER.md)  
**Judge brief (1-pager):** [`docs/Synapse-Pitch.pdf`](docs/Synapse-Pitch.pdf) · [`docs/PITCH.md`](docs/PITCH.md)  
**Live dashboard:** [synapse-clinical-hz.web.app](https://synapse-clinical-hz.web.app) · [QR](https://synapse-clinical-hz.web.app/qr)

---

## Who it’s for

| | |
| --- | --- |
| **Primary** | People with **energy-limiting conditions** — long COVID / ME-CFS (where pacing is NICE-recommended standard of care) and **post-concussion return-to-work**. For these users, “how you feel right now” is often the signal that fails; post-exertional cost arrives hours or days late. |
| **Secondary** | Knowledge workers on the burnout track — same mechanism, lower stakes. |

Not a hospital platform, not a diagnosis, not another streak counter. Wellness signal and a dismissible nudge only.

**Why sensing matters here:** pitched as a Pomodoro, a judge can say “just use a timer” — and be right. Pitched at people who cannot self-assess their limit until after they’ve crashed, passive measurement isn’t decorative; it’s the only mechanism available. **Visible** validates paid HR-based pacing for long COVID (dedicated armband, mostly after-the-fact). Synapse’s wedge: **no extra hardware** (phone + Watch you own) and **in-the-moment interrupt**.

---

## Product loop

```
PVT-B → Baseline → Focus → Break → PVT-B → Voice recap → Patterns
         ↑____________ in-session pacing ____________↑
```

**Measure → learn baseline → work → get stopped → measure again.** The post-block reaction delta is the wow moment.

### Three surfaces

| Surface | Job |
| --- | --- |
| **Phone + Watch** | In-block pacing HUD, break nudge, optional PVT-B, pattern tips. The companion you live in. |
| **Voice (ElevenLabs)** | Conversational coach / breath / reflect check-in — life context sensors can’t see. |
| **Web dashboard** | Fine-grained Focus timeline: fade score, HR, phase, per-channel signals, pacing report. |

Phone = act in the moment. Dashboard = microscope. PVT stays a **phone-screen moment** by design (dashboard does not render reaction fields).

---

## What’s in the app

### Focus (primary demo · `focusDesk`)

- **Setup → live HUD → break → recap**
- **Calibrating** — dashed ring: *“Learning your baseline · N%”*
- **Steady** → **Easing off** (*“Drifting from your baseline”*) → **Break suggested** (*“Your body is asking for a pause”*)
- Escalation by warmth: teal → sand → amber (no reds, no alarm aesthetics)
- Break: countdown + optional breath (box / 4-7-8) + lock-in ~10
- Presets: Classic 25/5 · Short 15/5 · Deep 50/10 · **Quick 5/1** (short baseline for demos) · optional 2/1 stage block behind Settings
- **Camera modes:** Always on · Brief check-ins · Watch only (HR + stillness; honesty copy on HUD)
- Soft posture drift nudge (does **not** weight the fade / break score)

### Sensing (honest claim)

We don’t measure fatigue — nobody can, non-invasively, in real time. Output is always **“take a break,”** never a diagnosis.

Three cheap physiological proxies against your **own** in-session baseline (pitch claim locked to three-proxy Answer A):

| Proxy | Approx weight |
| --- | --- |
| Watch HR vs session baseline | ~45% |
| Face arousal (on-device ARKit) | ~40% |
| Wrist stillness / fidget (IMU @ 100 Hz) | ~15% |

Missing or unusable channels drop out; weights renormalise. Composite sampled every ~8 s vs rolling **mean + 2σ**, 90 s cooldown, **two consecutive** over-threshold samples (~16 s floor before a nudge). Tuned to **over-nudge** on purpose: a false break costs ~90 seconds; a missed one costs the afternoon.

### PVT-B bookend (“Reaction check”)

Opt-in at Focus setup (**off by default — turn on for demos**). Implements **Basner, Mollicone & Dinges (2011)** brief PVT:

| Parameter | Value |
| --- | --- |
| Duration | 60 s (~20 trials) |
| ISI | 1–4 s |
| Lapse | RT ≥ **355 ms** (not 500 — deliberate for the brief protocol) |
| Anticipation | RT &lt; **100 ms** = false start |
| Headline | Median RT · within-person pre → post delta |

Honest deviations from the paper: 60 s instead of 3 min; 3 s no-response window instead of 30 s. Recap frames a within-person delta minutes apart — not a score against population norms.

### Voice coach

**ElevenLabs Conversational Agents** (Swift SDK / LiveKit) — modes `coach` / `breath` / `reflect`. Client tools drive Focus, breath, reaction check, check-in. Setup: [`docs/ELEVENLABS_AGENT.md`](docs/ELEVENLABS_AGENT.md). Requires `ELEVENLABS_AGENT_ID` (orb still appears without it; conversations fail soft).

### Lab modules (hub)

| Module | Purpose |
| --- | --- |
| `visionPvt` | Peripheral single-flash 3×3; saccade / arousal via TrueDepth (tripod). |
| `kineticClock` | 8-direction clock; Watch strike + octant. |
| `postureCheck` | Sit-tall baseline + front-camera upper-body drift (local; not a Firestore writer in v1). |

### Web dashboard

Vite + React + TypeScript. Live Firestore sessions from the phone (sole Firebase writer).

| Route | Shows |
| --- | --- |
| `/` · `/session/:id` | Live session (module-driven view) |
| `/demo/focus` · `/demo/vision` · `/demo/kinetic` | Offline canned snapshots (pitch fail-safe) |
| `/qr` | Hosting URL QR |

Focus view: epoch timeline, signal panels, pacing report. Details: [`web/README.md`](web/README.md).

---

## Architecture

```
Apple Watch (Series 5+)          iPhone                         Cloud / Web
─────────────────────            ─────────────────────          ─────────────────
Workout HR                       Focus HUD + PVT-B              Firestore
CMMotionManager @ 100 Hz  ←WC→   Face / arousal (on-device)  →   sessions + epochs
Haptics + status UI              Voice orb (ElevenLabs)         React dashboard
Cristian clock sync              SessionWriter (sole writer)
```

| Layer | Role |
| --- | --- |
| **Watch** | Keep-alive workout, 100 Hz IMU, discrete HR, WatchConnectivity only (no Firebase). |
| **Phone** | Sole Firebase writer. Focus, PVT, face path, lab engines, voice tools. |
| **Firestore** | Project `synapse-clinical-hz`. Contract: [`docs/SCHEMA.md`](docs/SCHEMA.md). |
| **Web** | Judge-facing HUD; reads trials + Focus epochs. |

**Bundle IDs (locked):** `com.dzak.synapse` · `com.dzak.synapse.watchkitapp`

---

## Tech stack

| Area | Stack |
| --- | --- |
| Native | Swift 5.9+, SwiftUI, iOS 17+, watchOS 10+, XcodeGen (`project.yml`) |
| Sensing | HealthKit / workout HR, Core Motion 100 Hz, ARKit / Vision (on-device) |
| Backend | Firebase Core + Firestore |
| Voice | ElevenLabs Conversational Agents SDK |
| Web | Vite, React, TypeScript |
| Tests | XCTest (`Tests/SynapseTests`) |

---

## Getting started

```bash
cd /path/to/Synapse

# 1. Generate Xcode project (never hand-edit .pbxproj)
xcodegen generate
open Synapse.xcodeproj

# 2. Signing — once per machine
#    Xcode → Synapse / SynapseWatch → Signing & Capabilities → Team

# 3. Firebase plist (gitignored — never commit the real file)
#    Project: synapse-clinical-hz · iOS bundle: com.dzak.synapse
firebase apps:sdkconfig IOS 1:325784899993:ios:b6115b338638970d050308 \
  --project synapse-clinical-hz \
  -o Sources/iOS/GoogleService-Info.plist
# Build-only fallback:
#   cp Sources/iOS/GoogleService-Info.plist.example Sources/iOS/GoogleService-Info.plist

# 4. Voice — scheme env (preferred) or VoiceSecrets.plist (gitignored)
#    ELEVENLABS_AGENT_ID   (required for spoken coach)
#    optional ELEVENLABS_VOICE_ID
#    optional OPENAI_API_KEY  (pattern tip polish only — not voice)
#    See docs/ELEVENLABS_AGENT.md

# 5. Simulator smoke (face + Watch need physical devices for a real demo)
xcodebuild build -scheme Synapse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet

xcodebuild test -scheme Synapse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet

# 6. Web dashboard
cd web && cp .env.example .env && npm install && npm run dev
# http://localhost:5173
# Seed: node scripts/seedDemoRest.mjs
```

**Physical devices required** for face tracking and WatchConnectivity. Series 5 caps at watchOS 10.6.

### Demo pre-flight (short)

- [ ] **Reaction check** toggle **ON** at Focus setup  
- [ ] Prefer **Quick 5/1** for short blocks (don’t narrate preset names on camera)  
- [ ] Say HUD copy exactly: Steady → **Easing off** → Break suggested  
- [ ] Dashboard tab ready: live session or `/demo/focus`  
- Full checklist: MASTER §12

---

## Honest limits

- **Never claim fatigue detection or diagnosis.** Wellness nudge only.
- **HRV not in yet** — we cannot yet cleanly separate “stressed” from “fading”; both can raise HR. Named next add.
- Longitudinal “what in your health affects focus” pattern brain is early (session tips + voice check-in are the seed).
- No invented accuracy % or clinical validation claims.
- Face video stays on-device; phone is the only Firebase writer.

---

## Repository map

```
project.yml                 # XcodeGen source of truth → xcodegen generate
AGENTS.md                   # Agent never-violate bullets → MASTER
docs/MASTER.md              # Canonical product / architecture / pitch / Q&A
docs/SCHEMA.md              # Firestore contract
docs/PITCH.md · Synapse-Pitch.pdf
docs/PITCH_SLIDE_BRIEF.md   # Slide / narrative brief
docs/ELEVENLABS_AGENT.md    # Voice agent setup
Sources/Shared/             # Clock sync, strike events, WC keys
Sources/iOS/                # Focus, Face, Voice, Firebase, UI, Pet
Sources/watchOS/            # Motion, workout keep-alive, haptics
Tests/SynapseTests/         # Unit tests
web/                        # React dashboard (separate ownership unless asked)
firebase.json · firestore.rules · .firebaserc
```

---

## Language kit (for demos & docs)

**Say:** pacing · your own baseline · three cheap proxies · wellness nudge · PVT-B · Easing off · over-nudge on purpose  

**Never say:** we detect cognitive fatigue · AI knows your brain is tired · clinically validated · diagnoses burnout · lapse threshold of 500 ms · “fading” as on-screen HUD copy  

Full Q&A scripts: [`docs/MASTER.md`](docs/MASTER.md) §13.

---

## License / status

Hackathon build — consumer healthcare pacing companion for demo and judging. Secrets (`GoogleService-Info.plist`, filled `VoiceSecrets.plist`, `web/.env`) are gitignored; use the `.example` stubs.
