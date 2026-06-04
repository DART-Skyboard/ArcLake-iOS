import SwiftUI
import SceneKit

/// ArcLake 3D Viewport — OrbitControls faithful port
/// 1-finger drag = orbit  |  2-finger pan = translate  |  pinch = dolly
/// 2-finger rotate = twist  |  double-tap = reset  |  single-tap = probe atom
public struct ArcSceneView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl = false   // we own the camera
        v.autoenablesDefaultLighting = false
        v.backgroundColor = UIColor(red:0.015, green:0.03, blue:0.07, alpha:1)
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.scene = labVM.scene

        // Camera — created once, owned by coordinator
        let cam = SCNCamera()
        cam.fieldOfView = 60; cam.zFar = 100000; cam.zNear = 0.001
        let camNode = SCNNode(); camNode.camera = cam; camNode.name = "mainCamera"
        labVM.scene.rootNode.addChildNode(camNode)

        // Set as point of view so SceneKit renders from this camera
        v.pointOfView = camNode

        context.coordinator.cameraNode = camNode
        context.coordinator.scnView    = v
        context.coordinator.lastScene  = labVM.scene
        context.coordinator.resetView(nil)

        // Gestures
        let orbit = UIPanGestureRecognizer(target: context.coordinator,
                                           action: #selector(Coordinator.handleOrbit(_:)))
        orbit.minimumNumberOfTouches = 1; orbit.maximumNumberOfTouches = 1

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2; pan.maximumNumberOfTouches = 2

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleDolly(_:)))

        let rot = UIRotationGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handleRotate(_:)))

        let dblTap = UITapGestureRecognizer(target: context.coordinator,
                                            action: #selector(Coordinator.resetView(_:)))
        dblTap.numberOfTapsRequired = 2

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: dblTap)

        for g in [orbit, pan, pinch, rot, dblTap, tap] {
            g.delegate = context.coordinator
            v.addGestureRecognizer(g)
        }

        v.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return v
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {
        let coord = context.coordinator
        guard let cam = coord.cameraNode else { return }

        // Only migrate camera when scene actually changes (tab switch)
        if uiView.scene !== labVM.scene {
            cam.removeFromParentNode()
            uiView.scene = labVM.scene
            labVM.scene.rootNode.addChildNode(cam)
            uiView.pointOfView = cam     // ← CRITICAL: re-point after scene swap
            coord.lastScene = labVM.scene
            coord.commit()
        }

        // Always ensure pointOfView is set (SwiftUI can clear it on re-render)
        if uiView.pointOfView !== cam {
            uiView.pointOfView = cam
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(labVM: labVM) }

    // MARK: — Coordinator
    public final class Coordinator: NSObject,
            UIGestureRecognizerDelegate, UIDropInteractionDelegate {

        let labVM: ArcLabViewModel
        weak var scnView: SCNView?
        var cameraNode: SCNNode?
        var lastScene: SCNScene?

        // Spherical coords around target — matches THREE.OrbitControls math
        private var theta:  Float = -0.6
        private var phi:    Float = 0.55
        private var radius: Float = 18.0
        private var target  = SIMD3<Float>.zero

        // Gesture start snapshots
        private var sTheta: Float = 0; private var sPhi:    Float = 0
        private var sRad:   Float = 0; private var sTgt     = SIMD3<Float>.zero
        private var sRot:   Float = 0; private var sThetaR: Float = 0

        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        // ── 1-finger orbit ────────────────────────────────────────
        @objc func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began { sTheta = theta; sPhi = phi }
            if g.state == .changed {
                let t = g.translation(in: v)
                theta = sTheta - Float(t.x) * 0.008
                phi   = max(0.04, min(.pi - 0.04, sPhi - Float(t.y) * 0.008))
                commit()
            }
        }

        // ── 2-finger pan (translate camera + target) ──────────────
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began { sTgt = target }
            if g.state == .changed {
                let t = g.translation(in: v)
                let speed = radius * 0.002
                // Right and up vectors relative to current theta
                let right = SIMD3<Float>(cos(theta),  0, -sin(theta))
                let up    = SIMD3<Float>(0, 1, 0)
                target = sTgt
                    - right * Float(t.x) * speed
                    + up    * Float(t.y) * speed
                commit()
            }
        }

        // ── Pinch dolly (move camera in/out, not FOV zoom) ────────
        @objc func handleDolly(_ g: UIPinchGestureRecognizer) {
            if g.state == .began { sRad = radius }
            if g.state == .changed {
                radius = max(0.1, sRad / Float(g.scale))
                commit()
            }
        }

        // ── 2-finger rotate (azimuth twist) ──────────────────────
        @objc func handleRotate(_ g: UIRotationGestureRecognizer) {
            if g.state == .began { sRot = Float(g.rotation); sThetaR = theta }
            if g.state == .changed {
                theta = sThetaR - (Float(g.rotation) - sRot)
                commit()
            }
        }

        // ── Double-tap: reset ─────────────────────────────────────
        @objc func resetView(_ sender: Any? = nil) {
            theta = -0.6; phi = 0.55; radius = 18.0; target = .zero
            SCNTransaction.begin()
            SCNTransaction.animationDuration = (sender == nil) ? 0 : 0.5
            commit()
            SCNTransaction.commit()
        }

        // ── Single tap: probe atom ────────────────────────────────
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let v = scnView else { return }
            let hits = v.hitTest(g.location(in: v),
                options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = hits.first else { return }
            var node: SCNNode? = hit.node
            while let cur = node {
                if let name = cur.name, name.hasPrefix("atomZ:"),
                   let z = Int(name.dropFirst(6)),
                   let el = ElementStore.shared.elements.first(where: { $0.id == z }) {
                    target = SIMD3<Float>(cur.worldPosition.x,
                                         cur.worldPosition.y,
                                         cur.worldPosition.z)
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = 0.35
                    commit()
                    SCNTransaction.commit()
                    Task { @MainActor in self.labVM.openProbe(for: el) }
                    return
                }
                node = cur.parent
            }
        }

        // ── Spherical → Cartesian camera position ─────────────────
        func commit() {
            guard let cam = cameraNode else { return }
            let sp = sin(phi); let cp = cos(phi)
            let st = sin(theta); let ct = cos(theta)
            cam.position = SCNVector3(
                target.x + radius * sp * st,
                target.y + radius * cp,
                target.z + radius * sp * ct)
            cam.look(at: SCNVector3(target.x, target.y, target.z))
        }

        // Allow simultaneous gesture recognition
        public func gestureRecognizer(_ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        // Drop interaction
        public func dropInteraction(_ i: UIDropInteraction,
            canHandle s: UIDropSession) -> Bool { s.canLoadObjects(ofClass: NSString.self) }
        public func dropInteraction(_ i: UIDropInteraction,
            sessionDidUpdate s: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }
        public func dropInteraction(_ i: UIDropInteraction, performDrop s: UIDropSession) {
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
