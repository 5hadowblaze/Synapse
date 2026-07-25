# Coordination — web agent note

Firebase root files owned/created by the web dashboard agent:

- `firebase.json`
- `firestore.rules`
- `.firebaserc`
- `docs/SCHEMA.md`
- `web/**`
- `Docs/PITCH_CHECKLIST.md`

iOS / watch agent owns:

- `project.yml`, Xcode project, `Sources/**`
- `GoogleService-Info.plist` (iOS target only)
- Firebase SPM on the phone app

If both sides touch root README, merge additively. Do not delete the other side's scaffold.
