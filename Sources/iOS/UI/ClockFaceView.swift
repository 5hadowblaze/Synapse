import SwiftUI

/// Eight-spoke kinetic clock; highlights the active octant.
struct ClockFaceView: View {
    let activeOctant: Int?
    var lastDetectedOctant: Int? = nil
    var spatialMatch: Bool? = nil

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            // Keep pad disks (up to 36pt when active) inside the view bounds.
            let padAllowance: CGFloat = 20
            let radius = max(0, side * 0.5 - padAllowance)

            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 2)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                ForEach(ClockOctant.allCases, id: \.rawValue) { octant in
                    let isActive = activeOctant == octant.rawValue
                    let isDetected = lastDetectedOctant == octant.rawValue
                    spoke(
                        octant: octant,
                        center: center,
                        radius: radius,
                        isActive: isActive,
                        isDetected: isDetected
                    )
                }

                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 10, height: 10)
                    .position(center)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(8)
    }

    private func spoke(
        octant: ClockOctant,
        center: CGPoint,
        radius: CGFloat,
        isActive: Bool,
        isDetected: Bool
    ) -> some View {
        let angle = octant.angleRadians - (.pi / 2) // 0 at 12 o'clock in UI coords
        let tip = CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
        let labelR = radius * 0.72
        let labelPos = CGPoint(
            x: center.x + CGFloat(cos(angle)) * labelR,
            y: center.y + CGFloat(sin(angle)) * labelR
        )

        return ZStack {
            Path { path in
                path.move(to: center)
                path.addLine(to: tip)
            }
            .stroke(
                isActive ? Color.green : Color.white.opacity(0.22),
                style: StrokeStyle(lineWidth: isActive ? 5 : 2, lineCap: .round)
            )

            Circle()
                .fill(padColor(isActive: isActive, isDetected: isDetected))
                .frame(width: isActive ? 36 : 22, height: isActive ? 36 : 22)
                .overlay {
                    Text(octant.label)
                        .font(.system(size: isActive ? 11 : 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .position(tip)
                .animation(.easeOut(duration: 0.08), value: isActive)

            if isActive {
                Text(octant.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .position(labelPos)
            }
        }
    }

    private func padColor(isActive: Bool, isDetected: Bool) -> Color {
        if isActive { return .green }
        if isDetected {
            if spatialMatch == true { return .cyan }
            if spatialMatch == false { return .orange }
            return .cyan.opacity(0.7)
        }
        return Color.white.opacity(0.2)
    }
}
