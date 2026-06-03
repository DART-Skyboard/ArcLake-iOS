
import SwiftUI
import SceneKit

/// ArcLake 3D Viewport — exact THREE.OrbitControls match
/// Web app: controls = new THREE.OrbitControls(camera, renderer.domElement)
///          controls.enableDamping = false
/// Controls:
///   1-finger drag       = orbit (rotate around target)
///   2-finger pan drag   = translate camera+target through world space
///   Pinch               = dolly (camera moves toward/away — NOT FOV zoom)
///   2-finger rotate     = azimuth orbit twist (bonus)
///   Double tap          = reset to default view
///   Single tap on atom  = focus + probe
///   No min/max distance = infinite travel in any direction
public struct ArcSceneView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = labVM.scene
        v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.backgroundColor = UIColor(red:0.015, green:0.03, blue:0.07, alpha:1)
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true

        let cam = SCNCamera()
        cam.fieldOfView = 60
        cam.zFar = 100000
        cam.zNear = 0.001
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.name = "mainCamera"
        labVM.scene.rootNode.addChildNode(camNode)
        context.coordinator.cameraNode = camNode
        context.coordinator.resetView(nil)

        let orbit = UIPanGestureRecognizer(target: context.coordinator,
                                            action: #selector(Coordinator.handleOrbit(_:)))
        orbit.minimumNumberOfTouches = 1; orbit.maximumNumberOfTouches = 1

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2; pan.maximumNumberOfTouches = 2

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handleDolly(_:)))

        let rotate = UIRotationGestureRecognizer(target: context.coordinator,
                                                  action: #selector(Coordinator.handleRotate(_:)))

        let dblTap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.resetView(_:)))
        dblTap.numberOfTapsRequired = 2

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: dblTap)

        [orbit, pan, pinch, rotate, dblTap, tap].forEach {
            ($0 as? UIPanGestureRecognizer)?.delegate    = context.coordinator
            ($0 as? UIPinchGestureRecognizer)?.delegate  = context.coordinator
            ($0 as? UIRotationGestureRecognizer)?.delegate = context.coordinator
            v.addGestureRecognizer($0)
        }
        v.addInteraction(UIDropInteraction(delegate: context.coordinator))
        context.coordinator.scnView = v
        return v
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {
        // Swap scene when active tab changes — this is how tab switching works
        if uiView.scene !== labVM.scene {
            uiView.scene = labVM.scene
        }
    }
    public func makeCoordinator() -> Coordinator { Coordinator(labVM: labVM) }

    public final class Coordinator: NSObject,
            UIGestureRecognizerDelegate, UIDropInteractionDelegate {

        let labVM: ArcLabViewModel
        weak var scnView: SCNView?
        var cameraNode: SCNNode?

        // OrbitControls state — spherical coordinates around target
        private var theta:  Float = -0.6    // azimuth angle
        private var phi:    Float = 0.55    // polar angle from Y axis
        private var radius: Float = 16.0    // distance from target
        private var target  = SIMD3<Float>(0, 0, 0)  // controls.target

        // Start snapshots
        private var s_theta:  Float = 0; private var s_phi:   Float = 0
        private var s_radius: Float = 0; private var s_target = SIMD3<Float>.zero
        private var s_rotate: Float = 0; private var s_theta2: Float = 0

        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        // ── 1-finger = orbit ──────────────────────────────────────
        @objc func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began { s_theta = theta; s_phi = phi }
            if g.state == .changed {
                let t = g.translation(in: v)
                theta = s_theta - Float(t.x) * 0.008
                phi   = max(0.04, min(Float.pi - 0.04,
                            s_phi - Float(t.y) * 0.008))
                commit()
            }
        }

        // ── 2-finger pan = translate through space ────────────────
        // Both camera AND target move — this is true "pan through world"
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began { s_target = target }
            if g.state == .changed {
                let t = g.translation(in: v)
                let speed = radius * 0.0018
                // Camera right vector from current theta
                let right = SIMD3<Float>(cos(theta),  0, -sin(theta))
                let up    = SIMD3<Float>(0, 1, 0)
                target = s_target
                    - right * Float(t.x) * speed
                    + up    * Float(t.y) * speed
                commit()
            }
        }

        // ── Pinch = DOLLY (move camera through space, not FOV) ────
        // radius decreases = camera moves toward target (flies into scene)
        // No min/max = fly through atoms if desired
        @objc func handleDolly(_ g: UIPinchGestureRecognizer) {
            if g.state == .began { s_radius = radius }
            if g.state == .changed {
                radius = max(0.05, s_radius / Float(g.scale))
                commit()
            }
        }

        // ── 2-finger rotate = orbit twist ────────────────────────
        @objc func handleRotate(_ g: UIRotationGestureRecognizer) {
            if g.state == .began { s_rotate = Float(g.rotation); s_theta2 = theta }
            if g.state == .changed {
                theta = s_theta2 - (Float(g.rotation) - s_rotate)
                commit()
            }
        }

        // ── Double tap = reset ────────────────────────────────────
        @objc func resetView(_ sender: Any? = nil) {
            theta = -0.6; phi = 0.55; radius = 16.0; target = .zero
            SCNTransaction.begin()
            SCNTransaction.animationDuration = (sender == nil) ? 0 : 0.5
            commit()
            SCNTransaction.commit()
        }

        // ── Single tap = probe + fly to atom ─────────────────────
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
                    let wp = cur.worldPosition
                    target = SIMD3<Float>(wp.x, wp.y, wp.z)
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

        // ── Camera position from spherical coords ─────────────────
        // Identical math to THREE.OrbitControls
        private func commit() {
            guard let cam = cameraNode else { return }
            let sp = sin(phi); let cp = cos(phi)
            let st = sin(theta); let ct = cos(theta)
            cam.position = SCNVector3(
                target.x + radius * sp * st,
                target.y + radius * cp,
                target.z + radius * sp * ct)
            cam.look(at: SCNVector3(target.x, target.y, target.z))
        }

        public func gestureRecognizer(_ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        // Drop
        public func dropInteraction(_ i: UIDropInteraction, canHandle s: UIDropSession) -> Bool {
            s.canLoadObjects(ofClass: NSString.self)
        }
        public func dropInteraction(_ i: UIDropInteraction,
            sessionDidUpdate s: UIDropSession) -> UIDropProposal { UIDropProposal(operation: .copy) }
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
