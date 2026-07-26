import Foundation
import simd

/// Pure framing coach for the fixed Batak kinetic clock (no ARKit).
/// Sweet spot ~0.55–0.85 m depth; lateral/vertical beyond ~0.08 m prompts a move.
enum KineticFramingGuidance {
    static let minDistanceMeters: Float = 0.55
    static let maxDistanceMeters: Float = 0.85
    static let maxLateralMeters: Float = 0.08
    static let maxVerticalMeters: Float = 0.08

    /// Primary framing prompt, or `nil` when the face is in band.
    /// Priority: missing face → depth → left/right → up/down.
    /// Left/right are selfie-mirrored (positive `face.x` → “Move left”).
    static func prompt(
        facePositionCamera: SIMD3<Float>?,
        distanceMeters: Float? = nil
    ) -> String? {
        guard let face = facePositionCamera else {
            return "Face the phone"
        }

        let distance = distanceMeters ?? simd_length(face)
        if distance < minDistanceMeters {
            return "Move further from the camera"
        }
        if distance > maxDistanceMeters {
            return "Move closer to the camera"
        }

        if abs(face.x) > maxLateralMeters {
            // Front-camera mirror: face moves right (+x) → coach says move left.
            return face.x > 0 ? "Move left" : "Move right"
        }

        if abs(face.y) > maxVerticalMeters {
            return face.y > 0 ? "Move down" : "Move up"
        }

        return nil
    }
}
