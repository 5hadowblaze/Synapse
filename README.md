# Synapse

iPhone ARKit reaction task + Apple Watch Series 5 strike detector, clock-synced via Cristian's algorithm over WatchConnectivity. Phone is the only Firebase writer; the React dashboard reads Firestore live.

## Getting started

```bash
cd /Users/amirdzakwan/Documents/Synapse

# 1. Generate the Xcode project (never hand-edit .pbxproj)
xcodegen generate
open Synapse.xcodeproj

# 2. Signing — once per machine
#    Xcode → Synapse target → Signing & Capabilities → pick Team
#    Repeat for SynapseWatch
#    Bundle IDs stay locked: com.synapse.app / com.synapse.app.watchkitapp

# 3. Firebase plist (project: synapse-clinical-hz, app: com.synapse.app)
#    Real file should already be at Sources/iOS/GoogleService-Info.plist.
#    If missing / REPLACE_ME stub only:
firebase apps:sdkconfig IOS 1:325784899993:ios:b6115b338638970d050308 \
  --project synapse-clinical-hz \
  -o Sources/iOS/GoogleService-Info.plist
#    Or Console → Project settings → Your apps → download plist into Sources/iOS/
#    Fallback for build-only: cp Sources/iOS/GoogleService-Info.plist.example \
#      Sources/iOS/GoogleService-Info.plist  (stub writer mode; no live Firestore)

# 4. Clinical dashboard
cd web && npm install && npm run dev   # http://localhost:5173

# 5. Seeded session (dashboard default)
#    Session id: demo-session-001  (VITE_DEFAULT_SESSION_ID)
#    From web/: node scripts/seedDemoRest.mjs   # or seedDemo.mjs — see web/README.md
#    On device: Synapse → Canned Replay writes the same id when Firebase is configured
```

Schema: [docs/SCHEMA.md](docs/SCHEMA.md). Pitch: [Docs/PITCH_CHECKLIST.md](Docs/PITCH_CHECKLIST.md). Physical range: [Docs/PHYSICAL_RANGE_CHECKLIST.md](Docs/PHYSICAL_RANGE_CHECKLIST.md).

## Layout

```
project.yml
Sources/Shared/     # ClockDomain, StrikeEvent (both targets)
Sources/iOS/        # Trial engine, face, Firestore writer, UI
Sources/watchOS/    # Workout keep-alive, 100Hz motion, clock sync
Docs/               # Physical range + pitch checklist
docs/SCHEMA.md      # Frozen Firestore contract
web/                # Dashboard (separate ownership)
```

## Simulator build

```bash
xcodegen generate

xcodebuild build -scheme Synapse \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet
```

Face tracking and WatchConnectivity need **physical devices** for a real demo. Pair Series 5 (watchOS 10.0+; S5 caps at 10.6), allow Motion/Health on watch and Camera on phone, then **Start** (live) or **Canned Replay** (Firestore/stub fallback).
