import SwiftUI
import SceneKit

/// ArcLake 3D Viewport
/// allowsCameraControl = false — we own all gestures for correct dolly behavior
/// → 1-finger drag   = orbit (rotate around target point)
/// → 2-finger drag   = pan   (truck camera + target through world space)
/// → pinch in/out    = DOLLY (camera physically moves closer/farther — NOT FOV zoom)
/// → double-tap      = reset to default view
/// → single tap      = probe atom
public struct ArcSceneView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl   = false  // we own gestures — no FOV zoom from SceneKit
        v.autoenablesDefaultLighting = false
        v.backgroundColor = UIColor(red:0.015, green:0.03, blue:0.07, alpha:1)
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously  = true
        v.scene = labVM.scene

        // Camera — fixed FOV, position changes for dolly
        let cam = SCNCamera()
        cam.fieldOfView = 60    // NEVER changes — dolly moves camera not lens
        cam.zFar = 100000
        cam.zNear = 0.001
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.name   = "mainCamera"
        labVM.scene.rootNode.addChildNode(camNode)
        v.pointOfView = camNode

        context.coordinator.scnView    = v
        context.coordinator.cameraNode = camNode
        context.coordinator.lastScene  = labVM.scene
        context.coordinator.resetView(nil)  // set initial position

        // ── Gestures ──────────────────────────────────────────────
        // 1-finger orbit
        let orbit = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleOrbit(_:)))
        orbit.minimumNumberOfTouches = 1
        orbit.maximumNumberOfTouches = 1

        // 2-finger pan (truck)
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2

        // Pinch = DOLLY (camera moves, not FOV)
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDolly(_:)))

        // Double-tap = reset
        let dblTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.resetView(_:)))
        dblTap.numberOfTapsRequired = 2

        // Single tap = probe
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.require(toFail: dblTap)

        for g in [orbit, pan, pinch, dblTap, tap] as [UIGestureRecognizer] {
            g.delegate = context.coordinator
            v.addGestureRecognizer(g)
        }

        v.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return v
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {
        let coord = context.coordinator
        if uiView.scene !== labVM.scene {
            coord.cameraNode?.removeFromParentNode()
            uiView.scene = labVM.scene
            if let cam = coord.cameraNode {
                labVM.scene.rootNode.addChildNode(cam)
                uiView.pointOfView = cam
            }
            coord.lastScene = labVM.scene
        }
        if let cam = coord.cameraNode, uiView.pointOfView !== cam {
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

        // Spherical coordinates — camera orbits around `target`
        private var theta:  Float = -0.4   // azimuth
        private var phi:    Float =  0.5   // polar (from Y)
        private var radius: Float = 18.0   // DISTANCE from target — pinch changes this
        private var target  = SIMD3<Float>.zero

        // Gesture start snapshots
        private var sTheta: Float = 0;  private var sPhi:    Float = 0
        private var sRadius: Float = 0; private var sTarget  = SIMD3<Float>.zero

        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        // ── 1-finger: orbit ───────────────────────────────────────
        @objc func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began { sTheta = theta; sPhi = phi }
            if g.state == .changed {
                let t = g.translation(in: v)
                theta = sTheta - Float(t.x) * 0.007
                phi   = max(0.05, min(.pi - 0.05, sPhi - Float(t.y) * 0.007))
                commit()
            }
        }

        // ── 2-finger: pan (truck camera + target) ─────────────────
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began { sTarget = target }
            if g.state == .changed {
                let t = g.translation(in: v)
                let speed = radius * 0.0018
                // Camera-relative right and up vectors
                let right = SIMD3<Float>(cos(theta), 0, -sin(theta))
                let up    = SIMD3<Float>(0, 1, 0)
                target = sTarget
                    - right * Float(t.x) * speed
                    + up    * Float(t.y) * speed
                commit()
            }
        }

        // ── Pinch: DOLLY — camera moves in/out, FOV stays at 60° ──
        @objc func handleDolly(_ g: UIPinchGestureRecognizer) {
            if g.state == .began { sRadius = radius }
            if g.state == .changed {
                // Pinch out (scale > 1) = zoom in = camera moves closer
                // Pinch in  (scale < 1) = zoom out = camera moves farther
                radius = max(0.5, min(500.0, sRadius / Float(g.scale)))
                commit()
            }
        }

        // ── Double-tap: reset ─────────────────────────────────────
        @objc func resetView(_ sender: Any? = nil) {
            theta = -0.4; phi = 0.5; radius = 18.0; target = .zero
            SCNTransaction.begin()
            SCNTransaction.animationDuration = (sender == nil) ? 0.0 : 0.45
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
                    // Fly camera to atom
                    target = SIMD3<Float>(
                        cur.worldPosition.x,
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
        // Camera moves to position on sphere around target.
        // FOV is locked at 60° — only radius changes for zoom.
        func commit() {
            guard let cam = cameraNode else { return }
            let sp = sin(phi);  let cp = cos(phi)
            let st = sin(theta); let ct = cos(theta)
            cam.position = SCNVector3(
                target.x + radius * sp * st,
                target.y + radius * cp,
                target.z + radius * sp * ct)
            cam.look(at: SCNVector3(target.x, target.y, target.z))
        }

        // Allow orbit + pinch simultaneously
        public func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        // ── Drop ──────────────────────────────────────────────────
        public func dropInteraction(
            _ i: UIDropInteraction,
            canHandle s: UIDropSession) -> Bool {
            s.canLoadObjects(ofClass: NSString.self)
        }
        public func dropInteraction(
            _ i: UIDropInteraction,
            sessionDidUpdate s: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }
        public func dropInteraction(
            _ i: UIDropInteraction,
            performDrop s: UIDropSession) {
            s.loadObjects(ofClass: NSString.self) { items in
                guard let sym = items.first as? String else { return }
                Task { @MainActor in
                    if let el = ElementStore.shared.elements.first(
                        where: { $0.elementSymbol == sym }) {
                        self.labVM.addElement(el)
                    }
                }
            }
        }
    }
}
