# Agent notes — Synapse native

- Edit `project.yml`, then run `xcodegen generate`. Never hand-edit `.pbxproj`.
- iOS 17+, watchOS 10.0, SwiftUI, `@Observable`.
- Bundle IDs: `com.synapse.app` / `com.synapse.app.watchkitapp`.
- Phone is the only Firebase writer; watch uses WatchConnectivity only.
- Series 5: `CMMotionManager` @ 100Hz — no `CMBatchedSensorManager`.
- Watch UI stays trivial (status + haptics).
- Do not build or own the React `web/` dashboard unless asked.
