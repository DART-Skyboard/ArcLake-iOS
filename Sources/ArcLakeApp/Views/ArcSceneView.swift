
import SwiftUI
import SceneKit

public struct ArcSceneView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = labVM.scene
        v.allowsCameraControl = false   // we handle camera ourselves
        v.autoenablesDefaultLighting = false
        v.backgroundColor = UIColor(red:0.015, green:0.03, blue:0.07, alpha:1)
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.showsStatistics = false

        // Build camera
        let cam = SCNCamera()
        cam.fieldOfView = 55
        cam.zFar = 1000
        cam.zNear = 0.01
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 2, 14)
        camNode.look(at: SCNVector3Zero)
        camNode.name = "mainCamera"
        labVM.scene.rootNode.addChildNode(camNode)
        context.coordinator.cameraNode = camNode

        // Gestures — all on the SCNView
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handlePinch(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let rotate = UIRotationGestureRecognizer(target: context.coordinator,
                                                  action: #selector(Coordinator.handleRotate(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTouchesRequired = 1

        // Allow simultaneous gestures
        pinch.delegate  = context.coordinator
        pan.delegate    = context.coordinator
        rotate.delegate = context.coordinator

        v.addGestureRecognizer(pinch)
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(rotate)
        v.addGestureRecognizer(tap)

        // Drop target
        v.addInteraction(UIDropInteraction(delegate: context.coordinator))

        context.coordinator.scnView = v
        return v
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(labVM: labVM) }

    // MARK: — Coordinator
    public final class Coordinator: NSObject,
        UIGestureRecognizerDelegate, UIDropInteractionDelegate {

        let labVM: ArcLabViewModel
        weak var scnView: SCNView?
        var cameraNode: SCNNode?

        // Camera state
        private var orbitYaw:   Float = 0      // horizontal orbit angle
        private var orbitPitch: Float = 0.3    // vertical orbit angle
        private var orbitDist:  Float = 14     // distance from target
        private var panOffset   = SIMD3<Float>(0, 0, 0)  // world-space pan offset
        private var orbitTarget = SIMD3<Float>(0, 0, 0)  // orbit focus point

        // Gesture start values
        private var startPinchDist: Float = 14
        private var startPanOffset = SIMD3<Float>(0, 0, 0)
        private var startOrbitYaw:  Float = 0
        private var startOrbitPitch:Float = 0
        private var startRotateAngle: Float = 0

        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        // ── Pinch = zoom (change orbit distance) ──────────────────
        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                startPinchDist = orbitDist
            case .changed:
                orbitDist = max(1.5, min(80, startPinchDist / Float(g.scale)))
                updateCamera()
            default: break
            }
        }

        // ── 2-finger pan = move camera through scene ──────────────
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            let t = g.translation(in: v)
            switch g.state {
            case .began:
                startPanOffset = panOffset
            case .changed:
                // Pan speed scales with distance
                let speed = orbitDist * 0.003
                // Move in camera's local right and up directions
                let yaw = orbitYaw
                let right = SIMD3<Float>( cos(yaw), 0, -sin(yaw))
                let up    = SIMD3<Float>(0, 1, 0)
                panOffset = startPanOffset
                    - right * Float(t.x) * speed
                    + up    * Float(t.y) * speed
                updateCamera()
            default: break
            }
        }

        // ── 2-finger rotate = orbit around target ─────────────────
        @objc func handleRotate(_ g: UIRotationGestureRecognizer) {
            switch g.state {
            case .began:
                startRotateAngle = orbitYaw
                startOrbitPitch  = orbitPitch
            case .changed:
                orbitYaw = startRotateAngle - Float(g.rotation)
                updateCamera()
            default: break
            }
        }

        // ── Tap = probe atom ──────────────────────────────────────
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let v = scnView else { return }
            let loc = g.location(in: v)
            let hits = v.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = hits.first else { return }

            // Walk up node tree to find atom root
            var node: SCNNode? = hit.node
            while let cur = node {
                if let name = cur.name, name.hasPrefix("atomZ:"),
                   let z = Int(name.dropFirst(6)),
                   let el = ElementStore.shared.elements.first(where: { $0.id == z }) {
                    // Set orbit target to tapped atom
                    let wp = cur.worldPosition
                    orbitTarget = SIMD3<Float>(wp.x, wp.y, wp.z)
                    panOffset = orbitTarget
                    updateCamera()
                    Task { @MainActor in self.labVM.openProbe(for: el) }
                    return
                }
                node = cur.parent
            }
            // Tapped empty space — reset orbit to world origin
            orbitTarget = SIMD3<Float>(0, 0, 0)
            panOffset   = SIMD3<Float>(0, 0, 0)
            updateCamera()
        }

        // ── Camera position from spherical coords ─────────────────
        private func updateCamera() {
            guard let cam = cameraNode else { return }
            let pitch = max(-.pi/2 + 0.05, min(.pi/2 - 0.05, orbitPitch))
            let x = orbitDist * cos(pitch) * sin(orbitYaw)
            let y = orbitDist * sin(pitch)
            let z = orbitDist * cos(pitch) * cos(orbitYaw)
            let target = panOffset
            cam.position = SCNVector3(target.x + x, target.y + y, target.z + z)
            cam.look(at: SCNVector3(target.x, target.y, target.z))
        }

        // Allow simultaneous pinch + rotate
        public func gestureRecognizer(_ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // ── Drop interaction ──────────────────────────────────────
        public func dropInteraction(_ i: UIDropInteraction,
            canHandle s: UIDropSession) -> Bool {
            s.canLoadObjects(ofClass: NSString.self)
        }
        public func dropInteraction(_ i: UIDropInteraction,
            sessionDidUpdate s: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }
        public func dropInteraction(_ i: UIDropInteraction,
            performDrop s: UIDropSession) {
            s.loadObjects(ofClass: NSString.self) { items in
                guard let sym = items.first as? String else { return }
                Task { @MainActor in
                    if let el = ElementStore.shared.elements.first(where: { $0.elementSymbol == sym }) {
                        self.labVM.addElement(el)
                    }
                }
            }
        }
    }
}
