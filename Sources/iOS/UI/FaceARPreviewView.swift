import ARKit
import SceneKit
import SwiftUI
import UIKit

/// Front-camera face mesh + cyan gaze ray + optional arm skeleton overlay.
struct FaceARPreviewView: UIViewRepresentable {
    let session: ARSession
    var isTracked: Bool
    var saccadeFlashToken: Int
    var mirrored: Bool = true
    /// When set, draws Vision arm joints / bones in screen space.
    var armJoints: [FrontArmEstimator.OverlayJoint] = []
    var armBones: [(CGPoint, CGPoint)] = []
    /// Called once after the view attaches so FaceTracker can refresh face anchors.
    var onAttached: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        context.coordinator.view = view
        view.automaticallyUpdatesLighting = true
        view.autoenablesDefaultLighting = true
        view.scene = SCNScene()
        view.backgroundColor = .black
        // Attach to the existing face session — never call session.run here.
        view.session = session
        if mirrored {
            view.transform = CGAffineTransform(scaleX: -1, y: 1)
        }
        context.coordinator.installChrome(on: view)
        DispatchQueue.main.async {
            onAttached?()
        }
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
            DispatchQueue.main.async {
                onAttached?()
            }
        }
        context.coordinator.setTracked(isTracked)
        context.coordinator.handleSaccadeFlash(token: saccadeFlashToken)
        context.coordinator.updateArmOverlay(
            joints: armJoints,
            bones: armBones,
            // Preview is already CGAffineTransform mirrored; undo joint mirror so bones align.
            unmirrorJoints: mirrored
        )
        let mirror = CGAffineTransform(scaleX: -1, y: 1)
        if mirrored, uiView.transform != mirror {
            uiView.transform = mirror
        } else if !mirrored, uiView.transform != .identity {
            uiView.transform = .identity
        }
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.delegate = nil
        // Detach without pausing FaceTracker's shared session (setup ↔ live swap).
        uiView.session = ARSession()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        weak var view: ARSCNView?
        private var faceNode: SCNNode?
        private var gazeRayNode: SCNNode?
        private var ringLayer: CAShapeLayer?
        private var armLayer: CAShapeLayer?
        private var lastFlashToken = 0

        func installChrome(on view: ARSCNView) {
            let ring = CAShapeLayer()
            ring.fillColor = UIColor.clear.cgColor
            ring.lineWidth = 4
            ring.strokeColor = UIColor.systemRed.cgColor
            ring.opacity = 0.9
            view.layer.addSublayer(ring)
            ringLayer = ring

            let arm = CAShapeLayer()
            arm.fillColor = UIColor.clear.cgColor
            arm.strokeColor = UIColor.systemGreen.withAlphaComponent(0.95).cgColor
            arm.lineWidth = 3
            arm.lineCap = .round
            arm.lineJoin = .round
            view.layer.addSublayer(arm)
            armLayer = arm

            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.layoutRing(in: view.bounds)
            }
        }

        func layoutRing(in bounds: CGRect) {
            guard let ringLayer else { return }
            let inset = bounds.insetBy(dx: 8, dy: 8)
            ringLayer.frame = bounds
            ringLayer.path = UIBezierPath(roundedRect: inset, cornerRadius: 16).cgPath
            armLayer?.frame = bounds
        }

        func setTracked(_ tracked: Bool) {
            ringLayer?.strokeColor = (tracked ? UIColor.systemGreen : UIColor.systemRed).cgColor
            if let view {
                layoutRing(in: view.bounds)
            }
        }

        func handleSaccadeFlash(token: Int) {
            guard token != lastFlashToken, token > 0 else { return }
            lastFlashToken = token
            guard let view else { return }
            let flash = UIView(frame: view.bounds)
            flash.backgroundColor = UIColor.cyan.withAlphaComponent(0.35)
            flash.isUserInteractionEnabled = false
            flash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(flash)
            UIView.animate(withDuration: 0.25, animations: {
                flash.alpha = 0
            }, completion: { _ in
                flash.removeFromSuperview()
            })
        }

        /// Joints are stored mirrored for SwiftUI overlays; ARSCNView itself is transform-mirrored,
        /// so convert back to unmirrored normalized coords before drawing in layer space.
        func updateArmOverlay(
            joints: [FrontArmEstimator.OverlayJoint],
            bones: [(CGPoint, CGPoint)],
            unmirrorJoints: Bool
        ) {
            guard let view, let armLayer else { return }
            layoutRing(in: view.bounds)
            let bounds = view.bounds
            guard bounds.width > 1, bounds.height > 1 else { return }

            func map(_ p: CGPoint) -> CGPoint {
                let x = unmirrorJoints ? (1 - p.x) : p.x
                let y = p.y
                return CGPoint(x: x * bounds.width, y: y * bounds.height)
            }

            let path = UIBezierPath()
            for bone in bones {
                let a = map(bone.0)
                let b = map(bone.1)
                path.move(to: a)
                path.addLine(to: b)
            }
            for joint in joints {
                let c = map(joint.point)
                path.move(to: CGPoint(x: c.x + 5, y: c.y))
                path.addArc(withCenter: c, radius: 5, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            }
            armLayer.path = path.cgPath
            armLayer.isHidden = joints.isEmpty && bones.isEmpty
        }

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let faceAnchor = anchor as? ARFaceAnchor,
                  let device = view?.device,
                  let geometry = ARSCNFaceGeometry(device: device)
            else { return nil }

            geometry.firstMaterial?.fillMode = .lines
            geometry.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.85)
            geometry.firstMaterial?.lightingModel = .physicallyBased

            let node = SCNNode(geometry: geometry)
            faceNode = node

            let ray = makeGazeRayNode()
            node.addChildNode(ray)
            gazeRayNode = ray
            updateGazeRay(on: ray, face: faceAnchor)
            return node
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor,
                  let faceGeometry = node.geometry as? ARSCNFaceGeometry
            else { return }
            faceGeometry.update(from: faceAnchor.geometry)
            if let ray = gazeRayNode ?? node.childNode(withName: "gazeRay", recursively: false) {
                updateGazeRay(on: ray, face: faceAnchor)
            }
            if let view {
                DispatchQueue.main.async { [weak self] in
                    self?.layoutRing(in: view.bounds)
                }
            }
        }

        private func makeGazeRayNode() -> SCNNode {
            let node = SCNNode()
            node.name = "gazeRay"
            return node
        }

        private func updateGazeRay(on node: SCNNode, face: ARFaceAnchor) {
            let left = face.leftEyeTransform.columns.3
            let right = face.rightEyeTransform.columns.3
            let origin = SIMD3<Float>(
                (left.x + right.x) * 0.5,
                (left.y + right.y) * 0.5,
                (left.z + right.z) * 0.5
            )
            let look = SIMD3<Float>(face.lookAtPoint.x, face.lookAtPoint.y, face.lookAtPoint.z)
            var direction = look - origin
            let len = simd_length(direction)
            if len < 1e-5 {
                direction = SIMD3(0, 0, -1)
            } else {
                direction /= len
            }
            let tip = origin + direction * 0.12

            node.geometry = rayGeometry(from: origin, to: tip)
            node.geometry?.firstMaterial?.diffuse.contents = UIColor.cyan
            node.geometry?.firstMaterial?.emission.contents = UIColor.cyan
            node.geometry?.firstMaterial?.lightingModel = .constant
        }

        private func rayGeometry(from: SIMD3<Float>, to: SIMD3<Float>) -> SCNGeometry {
            let vertices: [SCNVector3] = [
                SCNVector3(from.x, from.y, from.z),
                SCNVector3(to.x, to.y, to.z)
            ]
            let source = SCNGeometrySource(vertices: vertices)
            let indices: [Int32] = [0, 1]
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            return SCNGeometry(sources: [source], elements: [element])
        }
    }
}
