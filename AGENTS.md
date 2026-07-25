# Agent notes — Synapse native

**Read [`docs/MASTER.md`](docs/MASTER.md) first.** That file is the single source of truth (product, architecture, ship status, build plan, demos, keys, checklists).

## Never violate

- Edit `project.yml`, then run `xcodegen generate`. Never hand-edit `.pbxproj`.
- Bundle IDs locked: `com.synapse.app` / `com.synapse.app.watchkitapp`.
- Phone is the only Firebase writer; watch uses WatchConnectivity only.
- Series 5: `CMMotionManager` @ 100Hz — no `CMBatchedSensorManager`. Watch UI = status + haptics.
- Do not build or own `web/` unless asked.
- **Never commit secrets** (`GoogleService-Info.plist`, OpenAI/ElevenLabs keys, filled VoiceSecrets).
- Voice keys (scheme env preferred): `OPENAI_API_KEY`, `ELEVENLABS_API_KEY`, optional `ELEVENLABS_VOICE_ID`. Details in MASTER §10.
