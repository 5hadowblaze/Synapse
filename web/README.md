# Synapse Clinical Dashboard

Vite + React + TypeScript + Tailwind + Three.js dashboard that mirrors live Firestore sessions from the iOS/Watch trial stack.

## Quick start

```bash
cd web
cp .env.example .env   # already filled for project synapse-clinical-hz
npm install
npm run dev            # http://localhost:5173
```

Build:

```bash
npm run build
npm run preview
```

Demo / offline: click **Demo mode** in the header, or wait ~4s if Firebase has no session — canned JSON drives the same UI.

QR handout page: [/qr](http://localhost:5173/qr)

## Firebase

| Item | Value |
|------|--------|
| Project ID | `synapse-clinical-hz` |
| Console | https://console.firebase.google.com/project/synapse-clinical-hz/overview |
| Web App ID | `1:325784899993:web:1e78f1bb7b95ae9f050308` |

Env vars (all `VITE_FIREBASE_*`):

- `VITE_FIREBASE_API_KEY`
- `VITE_FIREBASE_AUTH_DOMAIN`
- `VITE_FIREBASE_PROJECT_ID`
- `VITE_FIREBASE_STORAGE_BUCKET`
- `VITE_FIREBASE_MESSAGING_SENDER_ID`
- `VITE_FIREBASE_APP_ID`
- `VITE_DEFAULT_SESSION_ID` (default `demo-session-001`)

Root repo files:

- `firebase.json` — Firestore rules path
- `firestore.rules` — **open demo rules**, expire comment `2026-08-01`
- `.firebaserc` — default project

Deploy rules (from repo root):

```bash
firebase deploy --only firestore:rules --project synapse-clinical-hz
```

Seed a demo session (for live-mode smoke test):

```bash
cd web
node scripts/seedDemoRest.mjs   # uses gcloud auth (recommended)
# or, once rules allow client writes:
node --env-file=.env scripts/seedDemo.mjs
```

### One-time console steps (if not already done)

1. Enable **Cloud Firestore** (Native mode) in the Firebase console if the CLI create failed due to API propagation delay.
2. Region used in CLI attempts: `europe-west2` (pick any; demo only).
3. Confirm rules deployed (open read/write until 2026-08-01).
4. **iOS agent owns** `GoogleService-Info.plist` + SPM Firebase for the phone app — download the iOS plist from the same project; do not put it in `web/`.

## Firestore schema

Canonical copy: [`../docs/SCHEMA.md`](../docs/SCHEMA.md)  
TypeScript types: [`src/types/session.ts`](src/types/session.ts)

```
sessions/{sessionId}
  athleteId, startedAt, status
  clockOffsetMs, clockRttMs
  baselineGapMs, baselineStdMs
  breakPointTrial?

sessions/{sessionId}/trials/{index}
  visualRtMs, motorRtMs, cognitiveMotorGapMs, …
sessions/{sessionId}/trials/{index}/gaze/{doc}
  t0Ms, samples: [{dt,x,y,z}]
```

## Coordination note

If the native agent creates `project.yml` / `Sources/` at repo root, leave those alone. Web changes stay under `web/` plus additive root Firebase files (`firebase.json`, `firestore.rules`, `.firebaserc`, `docs/`).
