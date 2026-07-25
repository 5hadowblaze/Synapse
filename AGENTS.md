# Agent notes — Synapse native

- Edit `project.yml`, then run `xcodegen generate`. Never hand-edit `.pbxproj`.
- iOS 17+, watchOS 10.0, SwiftUI, `@Observable`.
- Bundle IDs: `com.synapse.app` / `com.synapse.app.watchkitapp`.
- Phone is the only Firebase writer; watch uses WatchConnectivity only.
- Series 5: `CMMotionManager` @ 100Hz — no `CMBatchedSensorManager`.
- Watch UI stays trivial (status + haptics).
- Do not build or own the React `web/` dashboard unless asked.
- Firebase: download `GoogleService-Info.plist` from Console project `synapse-clinical-hz` into `Sources/iOS/` (gitignored). Use `.example` stub only for build-without-Firebase.
