import SwiftUI
import SceneKit

/// ArcLake 3D Viewport — Free-fly spectator camera
///
/// Controls (no allowsCameraControl — we own everything):
///   1-finger drag        → orbit around target (rotate view)
///   2-finger drag        → truck/pedestal (physically move camera + target
///                          left/right/up/down — like walking sideways)
///   pinch in/out         → dolly (camera moves forward/back along view axis)
///   double-tap           → reset to default view
///   single tap on atom   → probe panel + fly to atom
///
/// The camera NEVER zooms with FOV. It physically moves. fieldOfView is locked
/// at 60° at all times — exactly like a game spectator/free-fly camera.
public struct ArcSceneView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl   = false      // we own all camera movement
        v.autoenablesDefaultLighting = false
        v.backgroundColor = UIColor(red:0.015, green:0.03, blue:0.07, alpha:1)
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously  = true
        v.scene = labVM.scene

        // Camera — 60° FOV locked, never changes
        let cam     = SCNCamera()
        cam.fieldOfView = 60
        cam.zFar    = 500_000
        cam.zNear   = 0.001
        let camNode = SCNNode()
        camNode.camera   = cam
        camNode.name     = "arcCamera"
        labVM.scene.rootNode.addChildNode(camNode)
        v.pointOfView = camNode

        let c = context.coordinator
        c.scnView    = v
        c.camNode    = camNode
        c.lastScene  = labVM.scene
        c.reset()                           // set initial orbit position

        // Gestures
        let orbit = UIPanGestureRecognizer(target:c, action:#selector(Coordinator.orbit(_:)))
        orbit.minimumNumberOfTouches = 1
        orbit.maximumNumberOfTouches = 1

        let truck = UIPanGestureRecognizer(target:c, action:#selector(Coordinator.truck(_:)))
        truck.minimumNumberOfTouches = 2
        truck.maximumNumberOfTouches = 2

        let dolly = UIPinchGestureRecognizer(target:c, action:#selector(Coordinator.dolly(_:)))

        let dbl = UITapGestureRecognizer(target:c, action:#selector(Coordinator.reset))
        dbl.numberOfTapsRequired = 2

        let tap = UITapGestureRecognizer(target:c, action:#selector(Coordinator.tap(_:)))
        tap.numberOfTapsRequired = 1
        tap.require(toFail: dbl)

        for g: UIGestureRecognizer in [orbit, truck, dolly, dbl, tap] {
            g.delegate = c
            v.addGestureRecognizer(g)
        }
        v.addInteraction(UIDropInteraction(delegate: c))
        return v
    }

    public func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        // Tab switched — move camera into new scene
        if v.scene !== labVM.scene {
            c.camNode?.removeFromParentNode()
            v.scene = labVM.scene
            if let cam = c.camNode {
                labVM.scene.rootNode.addChildNode(cam)
                v.pointOfView = cam
            }
            c.lastScene = labVM.scene
        }
        if let cam = c.camNode, v.pointOfView !== cam {
            v.pointOfView = cam
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(labVM: labVM) }

    // MARK: — Coordinator
    public final class Coordinator: NSObject,
        UIGestureRecognizerDelegate, UIDropInteractionDelegate {

        let labVM: ArcLabViewModel
        weak var scnView: SCNView?
        var camNode: SCNNode?
        var lastScene: SCNScene?

        // Spherical orbit state (camera orbits around `target`)
        private var theta:  Float =  0.4    // azimuth
        private var phi:    Float =  0.6    // polar angle from Y
        private var radius: Float = 20.0    // distance — dolly changes this
        private var target  = SIMD3<Float>.zero

        // Gesture snapshots captured at .began
        private var θ0: Float = 0;  private var φ0:  Float = 0
        private var r0: Float = 0;  private var tgt0 = SIMD3<Float>.zero

        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        // ── 1-finger orbit (rotate around target) ─────────────────
        @objc func orbit(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            switch g.state {
            case .began:  θ0 = theta; φ0 = phi
            case .changed:
                let d = g.translation(in: v)
                theta = θ0 - Float(d.x) * 0.007
                phi   = max(0.05, min(.pi - 0.05, φ0 - Float(d.y) * 0.007))
                commit()
            default: break
            }
        }

        // ── 2-finger truck/pedestal (move camera + target) ────────
        // This physically translates the camera's position in world space —
        // left/right/up/down like walking sideways in a game.
        @objc func truck(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            switch g.state {
            case .began:  tgt0 = target
            case .changed:
                let d     = g.translation(in: v)
                let speed = radius * 0.0016
                // Camera-relative right and world-up vectors
                let right = SIMD3<Float>( cos(theta), 0, -sin(theta))
                let up    = SIMD3<Float>(0, 1, 0)
                target = tgt0
                    - right * Float(d.x) * speed
                    + up    * Float(d.y) * speed
                commit()
            default: break
            }
        }

        // ── Pinch dolly (camera physically moves forward/back) ────
        // scale > 1 = fingers spread = zoom in = camera closer
        // scale < 1 = fingers pinch  = zoom out = camera farther
        @objc func dolly(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:  r0 = radius
            case .changed:
                // Divide — spreading fingers REDUCES radius (closer)
                radius = max(0.3, min(1_000, r0 / Float(g.scale)))
                commit()
            default: break
            }
        }

        // ── Double-tap: reset view ────────────────────────────────
        @objc func reset() {
            theta = 0.4; phi = 0.6; radius = 20.0; target = .zero
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            commit()
            SCNTransaction.commit()
        }

        // ── Single tap: probe atom ────────────────────────────────
        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = scnView else { return }
            let hits = v.hitTest(g.location(in: v),
                options:[.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = hits.first else { return }
            var n: SCNNode? = hit.node
            while let cur = n {
                if let name = cur.name, name.hasPrefix("atomZ:"),
                   let z  = Int(name.dropFirst(6)),
                   let el = ElementStore.shared.elements.first(where:{ $0.id == z }) {
                    let wp = cur.worldPosition
                    target = SIMD3<Float>(wp.x, wp.y, wp.z)
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = 0.35
                    commit()
                    SCNTransaction.commit()
                    Task { @MainActor in self.labVM.openProbe(for: el) }
                    return
                }
                n = cur.parent
            }
        }

        // ── Place camera on sphere around target ──────────────────
        // fieldOfView stays 60° — only position changes
        func commit() {
            guard let cam = camNode else { return }
            let sp = sin(phi);  let cp = cos(phi)
            let st = sin(theta); let ct = cos(theta)
            cam.position = SCNVector3(
                target.x + radius * sp * st,
                target.y + radius * cp,
                target.z + radius * sp * ct)
            cam.look(at: SCNVector3(target.x, target.y, target.z))
        }

        public func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        // Drop
        public func dropInteraction(_ i: UIDropInteraction,
            canHandle s: UIDropSession) -> Bool { s.canLoadObjects(ofClass:NSString.self) }
        public func dropInteraction(_ i: UIDropInteraction,
            sessionDidUpdate s: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation:.copy) }
        public func dropInteraction(_ i: UIDropInteraction, performDrop s: UIDropSession) {
            s.loadObjects(ofClass:NSString.self) { items in
                guard let sym = items.first as? String else { return }
                Task { @MainActor in
                    if let el = ElementStore.shared.elements.first(
                        where:{$0.elementSymbol == sym}) { self.labVM.addElement(el) }
                }
            }
        }
    }
}
