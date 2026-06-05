import SwiftUI
import SceneKit
import ARKit
import RealityKit

// MARK: — ArcSceneView v6
// Camera controls matching Nomad Sculpt / professional 3D viewport standard:
//
//   1-finger drag       → ORBIT   (tumble camera around pivot)
//   2-finger drag       → PAN     (truck/pedestal — physically move camera+pivot)
//   Pinch               → DOLLY   (camera moves closer/farther, FOV locked at 60°)
//   Double-tap          → RESET   (return to default view, animated)
//   Single tap on atom  → FOCUS   (fly pivot to atom, open probe panel)
//
// FOV is locked at 60° — never changes. Only camera position moves.

public struct ArcSceneView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl   = false
        v.autoenablesDefaultLighting = false
        v.backgroundColor = UIColor(red:0.013, green:0.027, blue:0.065, alpha:1)
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously  = true
        v.preferredFramesPerSecond = 60
        v.scene = labVM.scene

        // Camera with bloom for particle glow
        let cam = SCNCamera()
        cam.fieldOfView      = 60          // LOCKED — dolly moves camera not lens
        cam.zFar             = 500_000
        cam.zNear            = 0.001
        cam.bloomIntensity   = 0.8
        cam.bloomThreshold   = 0.65
        cam.bloomBlurRadius  = 5.0
        cam.motionBlurIntensity = 0.2

        let camNode = SCNNode()
        camNode.camera = cam
        camNode.name   = "arcCamera"
        labVM.scene.rootNode.addChildNode(camNode)
        v.pointOfView = camNode

        let c = context.coordinator
        c.scnView   = v
        c.camNode   = camNode
        c.lastScene = labVM.scene
        c.resetView()                       // set initial position

        // ── Gestures ─────────────────────────────────────────────
        // 1-finger orbit
        let orbit = UIPanGestureRecognizer(target:c, action:#selector(Coordinator.handleOrbit(_:)))
        orbit.minimumNumberOfTouches = 1
        orbit.maximumNumberOfTouches = 1

        // 2-finger pan (truck/pedestal)
        let pan = UIPanGestureRecognizer(target:c, action:#selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2

        // Pinch dolly
        let pinch = UIPinchGestureRecognizer(target:c, action:#selector(Coordinator.handleDolly(_:)))

        // Double-tap reset
        let dbl = UITapGestureRecognizer(target:c, action:#selector(Coordinator.resetView))
        dbl.numberOfTapsRequired = 2

        // Single-tap probe
        let tap = UITapGestureRecognizer(target:c, action:#selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.require(toFail: dbl)

        for g: UIGestureRecognizer in [orbit, pan, pinch, dbl, tap] {
            g.delegate = c
            v.addGestureRecognizer(g)
        }

        v.addInteraction(UIDropInteraction(delegate: c))
        return v
    }

    public func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        guard let cam = c.camNode else { return }

        if v.scene !== labVM.scene {
            // Always detach from old scene before adding to new one
            cam.removeFromParentNode()
            v.scene = labVM.scene
            labVM.scene.rootNode.addChildNode(cam)
            v.pointOfView = cam
            c.lastScene = labVM.scene
        }

        // Re-set pointOfView every update — cheap and prevents frozen camera
        // after auth changes re-create the SwiftUI view hierarchy
        if v.pointOfView !== cam {
            cam.removeFromParentNode()
            labVM.scene.rootNode.addChildNode(cam)
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

        // Spherical coordinates of camera relative to pivot
        private var theta:  Float = 0.4       // azimuth
        private var phi:    Float = 0.6       // polar angle from Y-up
        private var radius: Float = 20.0      // distance (dolly changes this)
        private var pivot   = SIMD3<Float>.zero

        // Gesture start snapshots
        private var θ0: Float = 0;  private var φ0: Float = 0
        private var r0: Float = 0;  private var roll0: Float = 0
        private var pivot0 = SIMD3<Float>.zero

        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        // ── 1-finger: ORBIT ──────────────────────────────────────
        // Tumbles camera around pivot — standard 3D viewport feel
        @objc func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began { θ0 = theta; φ0 = phi }
            if g.state == .changed {
                let d = g.translation(in: v)
                // Sensitivity tuned to Nomad Sculpt feel
                theta = θ0 - Float(d.x) * 0.006
                phi   = max(0.02, min(.pi - 0.02, φ0 - Float(d.y) * 0.006))
                commit()
            }
        }

        // ── 2-finger: PAN (truck/pedestal) ───────────────────────
        // Physically moves camera + pivot through world space.
        // Speed proportional to distance so close/far feel consistent.
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began { pivot0 = pivot }
            if g.state == .changed {
                let d = g.translation(in: v)
                let speed = radius * 0.0014

                // Camera's local right and up vectors at current orientation
                let right = SIMD3<Float>( cos(theta),  0, -sin(theta))
                let fwd   = SIMD3<Float>(-sin(theta) * sin(phi),
                                          cos(phi),
                                          -cos(theta) * sin(phi))
                let up    = cross(fwd, right)  // true camera-up

                pivot = pivot0
                    - right * Float(d.x) * speed
                    + up    * Float(d.y) * speed
                commit()
            }
        }

        // ── Pinch: DOLLY ─────────────────────────────────────────
        // Camera physically moves along look axis. FOV stays at 60°.
        // Pinch OUT (scale > 1) = zoom in = closer
        // Pinch IN  (scale < 1) = zoom out = farther
        @objc func handleDolly(_ g: UIPinchGestureRecognizer) {
            if g.state == .began { r0 = radius }
            if g.state == .changed {
                radius = max(0.3, min(1_000, r0 / Float(g.scale)))
                commit()
            }
        }

        // ── Double-tap: RESET ────────────────────────────────────
        @objc func resetView() {
            theta = 0.4;  phi = 0.6;  radius = 20.0
            pivot = .zero
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            commit()
            SCNTransaction.commit()
        }

        // ── Single-tap: FOCUS on atom ────────────────────────────
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let v = scnView else { return }
            let hits = v.hitTest(g.location(in: v),
                options:[.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = hits.first else { return }
            var n: SCNNode? = hit.node
            while let cur = n {
                if let name = cur.name, name.hasPrefix("atomZ:"),
                   let z  = Int(name.dropFirst(6)),
                   let el = ElementStore.shared.elements.first(where:{ $0.id == z }) {
                    // Fly pivot to atom
                    let wp = cur.worldPosition
                    pivot = SIMD3<Float>(wp.x, wp.y, wp.z)
                    // Also pull camera closer so atom fills view nicely
                    radius = min(radius, 8.0)
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = 0.35
                    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
                    commit()
                    SCNTransaction.commit()
                    Task { @MainActor in self.labVM.openProbe(for: el) }
                    return
                }
                n = cur.parent
            }
        }

        // ── Place camera on sphere around pivot ───────────────────
        // Converts spherical (theta, phi, radius) + roll into a camera transform.
        // FOV stays at 60° always.
        func commit() {
            guard let cam = camNode else { return }
            let sp = sin(phi),  cp = cos(phi)
            let st = sin(theta), ct = cos(theta)

            // Camera position on sphere
            cam.position = SCNVector3(
                pivot.x + radius * sp * st,
                pivot.y + radius * cp,
                pivot.z + radius * sp * ct)

            // Look at pivot, then apply roll rotation
            cam.look(at: SCNVector3(pivot.x, pivot.y, pivot.z))


        }

        // All gestures can fire simultaneously
        public func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        // Drop support
        public func dropInteraction(_ i: UIDropInteraction,
            canHandle s: UIDropSession) -> Bool { s.canLoadObjects(ofClass:NSString.self) }
        public func dropInteraction(_ i: UIDropInteraction,
            sessionDidUpdate _: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation:.copy) }
        public func dropInteraction(_ i: UIDropInteraction, performDrop s: UIDropSession) {
            s.loadObjects(ofClass:NSString.self) { items in
                guard let sym = items.first as? String else { return }
                Task { @MainActor in
                    if let el = ElementStore.shared.elements.first(
                        where:{$0.elementSymbol==sym}) { self.labVM.addElement(el) }
                }
            }
        }
    }
}

// MARK: — AR Scene View (RealityKit)
struct ArcARView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame:.zero, cameraMode:.ar, automaticallyConfigureSession:true)
        arView.environment.background = .cameraFeed()
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        arView.session.run(config, options:[.resetTracking,.removeExistingAnchors])
        spawnAtomEntities(in: arView)
        let tap = UITapGestureRecognizer(target:context.coordinator,
            action:#selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    private func spawnAtomEntities(in arView: ARView) {
        for (idx, el) in labVM.selectedElements.enumerated() {
            let mesh   = MeshResource.generateSphere(radius: 0.04)
            let mat    = SimpleMaterial(color: el.category.color.withAlphaComponent(0.85),
                                        isMetallic: true)
            let entity = ModelEntity(mesh: mesh, materials: [mat])
            let anchor = AnchorEntity(world: SIMD3<Float>(
                Float(idx) * 0.12 - Float(labVM.selectedElements.count) * 0.06,
                0, -0.5))
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }
    }

    final class Coordinator: NSObject {
        var arView: ARView?
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let av = arView else { return }
            let results = av.raycast(from: g.location(in: av),
                allowing:.estimatedPlane, alignment:.any)
            if let hit = results.first {
                let mesh = MeshResource.generateSphere(radius: 0.018)
                let mat  = SimpleMaterial(color: .cyan, isMetallic: false)
                let e    = ModelEntity(mesh: mesh, materials: [mat])
                let anchor = AnchorEntity(world: hit.worldTransform.columns.3.xyz)
                anchor.addChild(e); av.scene.addAnchor(anchor)
            }
        }
    }
}

// MARK: — 3D Asset Import
struct ArcAssetImporter: UIViewControllerRepresentable {
    let onLoad: (SCNNode) -> Void
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {
        let types: [UTType] = [
            UTType(filenameExtension:"usdz") ?? .data,
            UTType(filenameExtension:"glb")  ?? .data,
            UTType(filenameExtension:"obj")  ?? .data,
            UTType(filenameExtension:"dae")  ?? .data,
        ].compactMap{$0}
        let vc = UIDocumentPickerViewController(forOpeningContentTypes:types, asCopy:true)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_:UIDocumentPickerViewController, context:Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onLoad:onLoad) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onLoad: (SCNNode) -> Void
        init(onLoad:@escaping(SCNNode)->Void){self.onLoad=onLoad}
        func documentPicker(_:UIDocumentPickerViewController, didPickDocumentsAt urls:[URL]) {
            guard let url = urls.first else { return }
            do {
                let scene = try SCNScene(url:url, options:[
                    .convertToYUp:true, .convertUnitsToMeters:1.0])
                let root = scene.rootNode.clone(); root.name="imported_\(url.lastPathComponent)"
                let bbox = root.boundingBox
                let sz = max(bbox.max.x-bbox.min.x,
                             max(bbox.max.y-bbox.min.y, bbox.max.z-bbox.min.z))
                if sz > 0 { let s=6.0/Float(sz); root.scale=SCNVector3(s,s,s) }
                DispatchQueue.main.async { self.onLoad(root) }
            } catch { print("Import failed: \(error)") }
        }
    }
}

import UniformTypeIdentifiers
extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x,y,z) }
}

