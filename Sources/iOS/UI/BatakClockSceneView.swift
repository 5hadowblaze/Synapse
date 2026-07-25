import SceneKit
import SwiftUI
import UIKit

/// Floating 8-pad Batak-style clock in SceneKit. Depth-locked ~0.6–0.8 m;
/// parallax from front-camera face position (no rear world tracking).
struct BatakClockSceneView: UIViewRepresentable {
    var activeOctant: Int?
    var lastDetectedOctant: Int? = nil
    var spatialMatch: Bool? = nil
    /// Face translation in camera meters; drives parallax so the clock feels planted.
    var facePositionCamera: SIMD3<Float>? = nil
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
            facePositionCamera: facePositionCamera,
            depthMeters: depthMeters
        )
    }

    final class Coordinator {
        weak var view: SCNView?
        private var clockRoot: SCNNode?
        private var padNodes: [Int: SCNNode] = [:]
        private var baseDepth: Float = 0.7

        /// Lateral/vertical parallax gain (meters of clock shift per meter of face shift).
        private let parallaxGain: Float = 0.85
        private let maxParallax: Float = 0.12
        private let tiltGain: Float = 0.35

        func buildScene(depth: Float) -> SCNScene {
            baseDepth = depth
            let scene = SCNScene()
            scene.background.contents = UIColor.clear

            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.fieldOfView = 42
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
            root.position = SCNVector3(0, -0.06, -depth)
            scene.rootNode.addChildNode(root)
            clockRoot = root

            // Pads only — no rim, hub, spokes, or labels.
            let ringRadius: Float = 0.18
            for octant in ClockOctant.allCases {
                let angle = Float(octant.angleRadians) - (.pi / 2)
                let x = cos(angle) * ringRadius
                let y = -sin(angle) * ringRadius

                let pad = SCNSphere(radius: 0.022)
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
            facePositionCamera: SIMD3<Float>?,
            depthMeters: Float
        ) {
            if abs(depthMeters - baseDepth) > 0.01, let root = clockRoot {
                baseDepth = depthMeters
                var pos = root.position
                pos.z = -depthMeters
                root.position = pos
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

            updateParallax(facePositionCamera: facePositionCamera)
        }

        private func updateParallax(facePositionCamera: SIMD3<Float>?) {
            guard let root = clockRoot else { return }
            guard let face = facePositionCamera else {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                root.position = SCNVector3(0, -0.06, -baseDepth)
                root.eulerAngles = SCNVector3(0, 0, 0)
                SCNTransaction.commit()
                return
            }

            // Face moves right → clock shifts left so it feels room-fixed (mirrored front cam).
            let rawX = -face.x * parallaxGain
            let rawY = -face.y * parallaxGain
            let dx = max(-maxParallax, min(maxParallax, rawX))
            let dy = max(-maxParallax, min(maxParallax, rawY))

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.08
            root.position = SCNVector3(dx, -0.06 + dy, -baseDepth)
            root.eulerAngles = SCNVector3(
                dy * tiltGain * 0.5,
                dx * tiltGain,
                0
            )
            SCNTransaction.commit()
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
