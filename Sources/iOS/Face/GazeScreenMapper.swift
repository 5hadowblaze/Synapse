import Foundation
import simd

/// Maps face-space `lookAtPoint` to approximate screen UV for a confidence / wow cursor.
/// Not laboratory screen-gaze accuracy — do not gate trial validity on the cursor cell.
@Observable
@MainActor
final class GazeScreenMapper {
    /// Gain from face-space lookAt.xy → UV delta.
    var gain = SIMD2<Float>(2.8, 2.8)
    /// Offset set by calibrate so rest gaze lands on center (cell 4).
    var offset = SIMD2<Float>(0, 0)
    /// Normalized screen UV (0…1). Origin top-leading for SwiftUI overlays.
    var screenUV: SIMD2<Float>?
    var isCalibrated = false

    func update(lookAt: SIMD3<Float>) {
        let raw = SIMD2(lookAt.x, lookAt.y)
        // Face +Y up; screen UV +Y down.
        var uv = SIMD2(
            0.5 + raw.x * gain.x + offset.x,
            0.5 - (raw.y * gain.y + offset.y)
        )
        uv.x = min(1, max(0, uv.x))
        uv.y = min(1, max(0, uv.y))
        screenUV = uv
    }

    /// While looking at the center pad (cell 4), zero offset so rest gaze sits at UV (0.5, 0.5).
    func calibrateToCenter(lookAt: SIMD3<Float>) {
        offset = SIMD2(-lookAt.x * gain.x, -lookAt.y * gain.y)
        isCalibrated = true
        update(lookAt: lookAt)
    }

    func resetCalibration() {
        offset = .zero
        isCalibrated = false
        screenUV = nil
    }
}
