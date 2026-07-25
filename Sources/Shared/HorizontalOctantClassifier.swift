import Foundation

/// Pure horizontal-plane octant math used by Watch motion (no CoreMotion / WatchKit).
struct HorizontalOctantClassifier: Sendable, Equatable {
    /// Unit forward in the calibrated horizontal plane (toward phone).
    var forwardXZ: (x: Double, z: Double)

    static func == (lhs: HorizontalOctantClassifier, rhs: HorizontalOctantClassifier) -> Bool {
        lhs.forwardXZ.x == rhs.forwardXZ.x && lhs.forwardXZ.z == rhs.forwardXZ.z
    }

    /// Project a 3D vector into the gravity-rejected horizontal plane and map to nearest octant.
    /// - Parameters:
    ///   - mirrorLateral: left-wrist mirror of the lateral axis.
    ///   - minHorizontal: minimum in-plane magnitude before classifying.
    func octant(
        vectorX: Double,
        vectorY: Double,
        vectorZ: Double,
        gravityX: Double,
        gravityY: Double,
        gravityZ: Double,
        mirrorLateral: Bool,
        minHorizontal: Double = 0.05
    ) -> Int? {
        let gMag = sqrt(gravityX * gravityX + gravityY * gravityY + gravityZ * gravityZ)
        guard gMag > 0.1 else { return nil }
        let ngx = gravityX / gMag
        let ngy = gravityY / gMag
        let ngz = gravityZ / gMag
        let alongG = vectorX * ngx + vectorY * ngy + vectorZ * ngz
        var hx = vectorX - alongG * ngx
        var hz = vectorZ - alongG * ngz
        _ = vectorY - alongG * ngy

        if mirrorLateral {
            hx = -hx
        }

        let hMag = sqrt(hx * hx + hz * hz)
        guard hMag > minHorizontal else { return nil }
        hx /= hMag
        hz /= hMag

        let dot = forwardXZ.x * hx + forwardXZ.z * hz
        let cross = forwardXZ.x * hz - forwardXZ.z * hx
        let angle = atan2(cross, dot)
        // atan2 is CCW from forward; clock wants clockwise → negate.
        let clockAngle = -angle
        return ClockOctant.nearest(angleRadians: clockAngle).rawValue
    }

    /// Build a classifier from averaged calibration gravity + attitude-forward samples.
    static func fromCalibration(
        gravitySumX: Double,
        gravitySumY: Double,
        gravitySumZ: Double,
        forwardSumX: Double,
        forwardSumZ: Double,
        sampleCount: Int
    ) -> HorizontalOctantClassifier? {
        guard sampleCount > 0 else { return nil }
        let n = Double(sampleCount)
        let gx = gravitySumX / n
        let gy = gravitySumY / n
        let gz = gravitySumZ / n
        let gMag = sqrt(gx * gx + gy * gy + gz * gz)
        guard gMag > 0.1 else { return nil }

        var fx = forwardSumX / n
        var fz = forwardSumZ / n
        let gHorizMag = sqrt(gx * gx + gz * gz)
        if gHorizMag > 0.05 {
            fx -= gx
            fz -= gz
        }
        let fMag = sqrt(fx * fx + fz * fz)
        if fMag < 1e-4 {
            fx = 0
            fz = 1
        } else {
            fx /= fMag
            fz /= fMag
        }
        return HorizontalOctantClassifier(forwardXZ: (fx, fz))
    }
}
