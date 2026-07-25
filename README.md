# Synapse

**Synapse Focus** — health-aware Pomodoro for builders and students. Tech moat: fused phone camera + Watch motion + HR.

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
