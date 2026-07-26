import SceneKit
import SwiftUI
import UIKit

/// Floating 8-pad Batak-style clock in SceneKit. Depth-locked ~0.6–0.8 m;
/// fixed in camera view (no face parallax) — framing prompts coach the user instead.
struct BatakClockSceneView: UIViewRepresentable {
    var activeOctant: Int?
    var lastDetectedOctant: Int? = nil
    var spatialMatch: Bool? = nil
    /// Ring depth in front of the virtual camera (meters).
    var depthMeters: Float = 0.7

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = false
        view.isPlaying = true
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.buildScene(depth: depthMeters)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.apply(
            activeOctant: activeOctant,
            lastDetectedOctant: lastDetectedOctant,
            spatialMatch: spatialMatch,
            depthMeters: depthMeters
        )
    }

    final class Coordinator {
        weak var view: SCNView?
        private var clockRoot: SCNNode?
        private var padNodes: [Int: SCNNode] = [:]
        private var baseDepth: Float = 0.7

        func buildScene(depth: Float) -> SCNScene {
            baseDepth = depth
            let scene = SCNScene()
            scene.background.contents = UIColor.clear

            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            // Horizontal FOV so 3/9 o'clock pads stay inside the portrait frustum
            // (default vertical FOV clips side orbs on narrow iPhones).
            cameraNode.camera?.projectionDirection = .horizontal
            cameraNode.camera?.fieldOfView = 48
            cameraNode.camera?.zNear = 0.05
            cameraNode.camera?.zFar = 4
            cameraNode.position = SCNVector3(0, 0, 0)
            scene.rootNode.addChildNode(cameraNode)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 400
            ambient.light?.color = UIColor.white
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 900
            key.light?.color = UIColor.white
            key.eulerAngles = SCNVector3(-0.5, 0.35, 0)
            scene.rootNode.addChildNode(key)

            let root = SCNNode()
            root.name = "batakClock"
            // Slightly below eye line so punches read in front of the torso.
            root.position = SCNVector3(0, -0.04, -depth)
            scene.rootNode.addChildNode(root)
            clockRoot = root

            // Pads only — no rim, hub, spokes, or labels.
            // ringR 0.15 + active pad ~0.03 fits inside tan(24°)*depth at depth≈0.7.
            let ringRadius: Float = 0.15
            for octant in ClockOctant.allCases {
                let angle = Float(octant.angleRadians) - (.pi / 2)
                let x = cos(angle) * ringRadius
                let y = -sin(angle) * ringRadius

                let pad = SCNSphere(radius: 0.02)
                pad.firstMaterial = padMaterial(active: false, detected: false, match: nil)
                let padNode = SCNNode(geometry: pad)
                padNode.name = "pad-\(octant.rawValue)"
                padNode.position = SCNVector3(x, y, 0.01)
                root.addChildNode(padNode)
                padNodes[octant.rawValue] = padNode
            }

            return scene
        }

        func apply(
            activeOctant: Int?,
            lastDetectedOctant: Int?,
            spatialMatch: Bool?,
            depthMeters: Float
        ) {
            if abs(depthMeters - baseDepth) > 0.01, let root = clockRoot {
                baseDepth = depthMeters
                root.position = SCNVector3(0, -0.04, -depthMeters)
                root.eulerAngles = SCNVector3(0, 0, 0)
            }

            for (raw, node) in padNodes {
                let isActive = activeOctant == raw
                let isDetected = lastDetectedOctant == raw
                node.geometry?.firstMaterial = padMaterial(
                    active: isActive,
                    detected: isDetected,
                    match: spatialMatch
                )
                let scale: Float = isActive ? 1.35 : 1.0
                node.simdScale = SIMD3<Float>(repeating: scale)
            }
        }

        private func padMaterial(active: Bool, detected: Bool, match: Bool?) -> SCNMaterial {
            let mat = SCNMaterial()
            mat.lightingModel = .physicallyBased
            if active {
                mat.diffuse.contents = UIColor.systemGreen
                mat.emission.contents = UIColor.systemGreen.withAlphaComponent(0.85)
                mat.metalness.contents = 0.15
                mat.roughness.contents = 0.35
            } else if detected {
                let color: UIColor
                if match == true {
                    color = .systemCyan
                } else if match == false {
                    color = .systemOrange
                } else {
                    color = UIColor.systemCyan.withAlphaComponent(0.7)
                }
                mat.diffuse.contents = color
                mat.emission.contents = color.withAlphaComponent(0.45)
                mat.metalness.contents = 0.1
                mat.roughness.contents = 0.45
            } else {
                mat.diffuse.contents = UIColor.white.withAlphaComponent(0.28)
                mat.emission.contents = UIColor.black
                mat.metalness.contents = 0.05
                mat.roughness.contents = 0.55
            }
            return mat
        }

    }
}
