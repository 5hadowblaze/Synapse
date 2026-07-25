# Synapse Clinical Dashboard

Vite + React + TypeScript dashboard mirroring live Firestore sessions from the iOS/Watch stack.

**Product / architecture / agent rules:** [`../docs/MASTER.md`](../docs/MASTER.md) (canonical). Native agents should not own this tree unless asked.

## Quick start

```bash
cd web
cp .env.example .env   # project synapse-clinical-hz
npm install && npm run dev   # http://localhost:5173
```

Schema: [`../docs/SCHEMA.md`](../docs/SCHEMA.md) · types: `src/types/session.ts`.  
Hosting: https://synapse-clinical-hz.web.app · QR: `/qr`. Demo mode works offline.

Firebase root files (`firebase.json`, `firestore.rules`, `.firebaserc`) are web-owned; iOS owns `GoogleService-Info.plist`. See MASTER §9–§10.
