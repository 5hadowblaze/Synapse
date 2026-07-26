# Synapse

**Synapse** — cognitive pacing, PVT-anchored. It looks like a Pomodoro timer; it's a pacing tool for people whose fatigue is a medical problem, not a productivity one. Tech moat: Watch HR + wrist motion + phone camera, read against your own baseline rather than a population norm.

**Source of truth for agents and product:** [`docs/MASTER.md`](docs/MASTER.md)

## Getting started

```bash
cd /Users/amirdzakwan/Documents/Synapse

xcodegen generate
open Synapse.xcodeproj

# Signing: Xcode → Synapse / SynapseWatch → Team (once)
# Firebase: download GoogleService-Info.plist into Sources/iOS/ (gitignored)
#   or: cp Sources/iOS/GoogleService-Info.plist.example Sources/iOS/GoogleService-Info.plist
# Voice: scheme env OPENAI_API_KEY + ELEVENLABS_API_KEY (see docs/MASTER.md §10)

# Optional clinical dashboard (separate ownership)
cd web && npm install && npm run dev
```

Schema detail: [`docs/SCHEMA.md`](docs/SCHEMA.md). Pitch / physical range condensed in MASTER §12.

**Judge brief (1-pager):** [`docs/Synapse-Pitch.pdf`](docs/Synapse-Pitch.pdf) · markdown source [`docs/PITCH.md`](docs/PITCH.md)
