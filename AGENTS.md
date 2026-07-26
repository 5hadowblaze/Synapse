# Agent notes — Synapse native

**Read [`docs/MASTER.md`](docs/MASTER.md) first.** That file is the single source of truth (product, architecture, ship status, build plan, demos, keys, checklists).

**Positioning (locked, MASTER §1 + §14):** Synapse is **cognitive pacing, PVT-anchored** — for people with energy-limiting conditions (long COVID / ME-CFS, post-concussion return-to-work), not a productivity Pomodoro. The Pomodoro surface is intentional; it is not the pitch.

## Never violate

- Edit `project.yml`, then run `xcodegen generate`. Never hand-edit `.pbxproj`.
- Bundle IDs locked: `com.dzak.synapse` / `com.dzak.synapse.watchkitapp` (was `com.synapse.app` — taken on App Store by Sevaro).
- Phone is the only Firebase writer; watch uses WatchConnectivity only.
- Series 5: `CMMotionManager` @ 100Hz — no `CMBatchedSensorManager`. Watch UI = status + haptics.
- Do not build or own `web/` unless asked.
- **Never commit secrets** (`GoogleService-Info.plist`, ElevenLabs/OpenAI keys, filled VoiceSecrets).
- Voice: `ELEVENLABS_AGENT_ID` required (scheme env preferred); optional `ELEVENLABS_VOICE_ID`. `OPENAI_API_KEY` only for optional pattern tips — not voice. Dashboard setup: [`docs/ELEVENLABS_AGENT.md`](docs/ELEVENLABS_AGENT.md). Details in MASTER §10.
- **Design:** always research good mobile/health/focus-app design before UI work; UI must look intentional (not AI-generic). Follow [`docs/MASTER.md`](docs/MASTER.md) §5 Design quality.
- **Never claim to detect or measure fatigue** — not in UI copy, docs, or commit messages. Banned phrases and the approved wording are in MASTER §13 (Q&A survival kit). Wellness signal and a nudge; never a diagnosis.
- **PVT-B is the protocol** (Basner, Mollicone & Dinges 2011): lapse threshold **355 ms**, anticipation floor **100 ms**, 1–4 s ISI. 355 is deliberate — it is *not* a typo for the 10-minute PVT's 500 ms. Don't "fix" it. Reasoning in MASTER §3.
- **Pitch claim:** §13 **Answer A** (three proxies) locked 26 July. Answer B is fallback only if a live arousal diagnostic says the face channel is constant.
