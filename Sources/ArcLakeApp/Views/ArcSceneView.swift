import SwiftUI
import SceneKit
import ARKit
import RealityKit

// MARK: — ArcSceneView v5
// SceneKit 3D viewport with:
//   • Free-fly camera (1-finger orbit, 2-finger truck, pinch dolly)
//   • Metal-backed point shader for glow rendering
//   • AR mode via RealityKit ARView
//   • GLB/USDZ import
//   • 3D grid centered at origin

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
        // Enable Metal for better particle rendering
        v.scene = labVM.scene

        let cam = SCNCamera()
        cam.fieldOfView = 60
        cam.zFar   = 500_000
        cam.zNear  = 0.001
        // Bloom for glow effect on particles
        cam.bloomIntensity   = 0.85
        cam.bloomThreshold   = 0.7
        cam.bloomBlurRadius  = 6.0
        // Motion blur for animation
        cam.motionBlurIntensity = 0.25

        let camNode = SCNNode()
        camNode.camera = cam
        camNode.name   = "arcCamera"
        labVM.scene.rootNode.addChildNode(camNode)
        v.pointOfView = camNode

        let c = context.coordinator
        c.scnView   = v
        c.camNode   = camNode
        c.lastScene = labVM.scene
        c.resetView()

        // Gestures
        let orbit = UIPanGestureRecognizer(target:c, action:#selector(Coordinator.orbit(_:)))
        orbit.minimumNumberOfTouches = 1; orbit.maximumNumberOfTouches = 1

        let truck = UIPanGestureRecognizer(target:c, action:#selector(Coordinator.truck(_:)))
        truck.minimumNumberOfTouches = 2; truck.maximumNumberOfTouches = 2

        let dolly = UIPinchGestureRecognizer(target:c, action:#selector(Coordinator.dolly(_:)))
        let dbl   = UITapGestureRecognizer(target:c, action:#selector(Coordinator.resetView))
        dbl.numberOfTapsRequired = 2
        let tap   = UITapGestureRecognizer(target:c, action:#selector(Coordinator.tap(_:)))
        tap.numberOfTapsRequired = 1
        tap.require(toFail: dbl)

        for g: UIGestureRecognizer in [orbit, truck, dolly, dbl, tap] {
            g.delegate = c; v.addGestureRecognizer(g)
        }
        v.addInteraction(UIDropInteraction(delegate: c))
        return v
    }

    public func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        if v.scene !== labVM.scene {
            c.camNode?.removeFromParentNode()
            v.scene = labVM.scene
            if let cam = c.camNode {
                labVM.scene.rootNode.addChildNode(cam)
                v.pointOfView = cam
            }
            c.lastScene = labVM.scene
        }
        if let cam = c.camNode, v.pointOfView !== cam { v.pointOfView = cam }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(labVM: labVM) }

    // MARK: — Coordinator
    public final class Coordinator: NSObject,
        UIGestureRecognizerDelegate, UIDropInteractionDelegate {

        let labVM: ArcLabViewModel
        weak var scnView: SCNView?
        var camNode: SCNNode?
        var lastScene: SCNScene?

        private var theta:  Float = 0.4
        private var phi:    Float = 0.6
        private var radius: Float = 20.0
        private var target  = SIMD3<Float>.zero

        private var θ0: Float=0; private var φ0:  Float=0
        private var r0: Float=0; private var tgt0 = SIMD3<Float>.zero

        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        @objc func orbit(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            switch g.state {
            case .began: θ0=theta; φ0=phi
            case .changed:
                let d=g.translation(in:v)
                theta=θ0 - Float(d.x)*0.007
                phi=max(0.05,min(.pi-0.05, φ0-Float(d.y)*0.007))
                commit()
            default: break
            }
        }

        @objc func truck(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            switch g.state {
            case .began: tgt0=target
            case .changed:
                let d=g.translation(in:v); let s=radius*0.0016
                let right=SIMD3<Float>(cos(theta),0,-sin(theta))
                target=tgt0 - right*Float(d.x)*s + SIMD3<Float>(0,1,0)*Float(d.y)*s
                commit()
            default: break
            }
        }

        @objc func dolly(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: r0=radius
            case .changed: radius=max(0.3,min(1000, r0/Float(g.scale))); commit()
            default: break
            }
        }

        @objc func resetView() {
            theta=0.4; phi=0.6; radius=20.0; target = .zero
            SCNTransaction.begin(); SCNTransaction.animationDuration=0.4
            commit(); SCNTransaction.commit()
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = scnView else { return }
            let hits = v.hitTest(g.location(in:v),
                options:[.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = hits.first else { return }
            var n: SCNNode? = hit.node
            while let cur = n {
                if let name=cur.name, name.hasPrefix("atomZ:"),
                   let z=Int(name.dropFirst(6)),
                   let el=ElementStore.shared.elements.first(where:{$0.id==z}) {
                    target=SIMD3<Float>(cur.worldPosition.x,cur.worldPosition.y,cur.worldPosition.z)
                    SCNTransaction.begin(); SCNTransaction.animationDuration=0.35
                    commit(); SCNTransaction.commit()
                    Task { @MainActor in self.labVM.openProbe(for: el) }
                    return
                }
                n=cur.parent
            }
        }

        func commit() {
            guard let cam=camNode else { return }
            let sp=sin(phi); let cp=cos(phi)
            let st=sin(theta); let ct=cos(theta)
            cam.position=SCNVector3(
                target.x+radius*sp*st,
                target.y+radius*cp,
                target.z+radius*sp*ct)
            cam.look(at:SCNVector3(target.x,target.y,target.z))
        }

        public func gestureRecognizer(_:UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _:UIGestureRecognizer)->Bool{true}

        public func dropInteraction(_:UIDropInteraction,canHandle s:UIDropSession)->Bool{
            s.canLoadObjects(ofClass:URL.self) || s.canLoadObjects(ofClass:NSString.self)
        }
        public func dropInteraction(_:UIDropInteraction,
            sessionDidUpdate _:UIDropSession)->UIDropProposal{UIDropProposal(operation:.copy)}
        public func dropInteraction(_:UIDropInteraction,performDrop s:UIDropSession){
            s.loadObjects(ofClass:NSString.self){items in
                guard let sym=items.first as? String else{return}
                Task{@MainActor in
                    if let el=ElementStore.shared.elements.first(where:{$0.elementSymbol==sym}){
                        self.labVM.addElement(el)
                    }
                }
            }
        }
    }
}

// MARK: — AR Scene View (RealityKit)
// Presents the active scene in AR using RealityKit ARView.
// Atoms are spawned as RealityKit ModelEntity point clouds anchored to a surface.
struct ArcARView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: true)
        arView.environment.background = .cameraFeed()

        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection   = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Render existing atoms as RealityKit entities
        spawnAtomEntities(in: arView)

        // Tap to place anchor
        let tap = UITapGestureRecognizer(target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        context.coordinator.arView = arView
        context.coordinator.labVM = labVM
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    private func spawnAtomEntities(in arView: ARView) {
        // Spawn a compact atom sphere per element, laid out horizontally
        for (idx, el) in labVM.selectedElements.enumerated() {
            let mesh   = MeshResource.generateSphere(radius: 0.04)
            let mat    = SimpleMaterial(color: el.category.color.withAlphaComponent(0.85),
                                        isMetallic: true)
            let entity = ModelEntity(mesh: mesh, materials: [mat])
            entity.name = "ar_atom_\(el.id)"

            // Add point light for glow
            let light = PointLight()
            var comp = PointLightComponent(color: el.category.color,
                intensity: 800, attenuationRadius: 0.8)
            entity.components.set(comp)

            let anchor = AnchorEntity(world: SIMD3<Float>(
                Float(idx) * 0.12 - Float(labVM.selectedElements.count) * 0.06,
                0, -0.5))
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }
    }

    final class Coordinator: NSObject {
        var arView: ARView?
        var labVM: ArcLabViewModel?

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let av = arView else { return }
            let loc = g.location(in: av)
            let results = av.raycast(from: loc, allowing: .estimatedPlane, alignment: .any)
            guard let first = results.first else { return }
            // Place a small anchor sphere at tap location
            let mesh = MeshResource.generateSphere(radius: 0.02)
            let mat  = SimpleMaterial(color: .cyan, isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [mat])
            let anchor = AnchorEntity(world: first.worldTransform.columns.3.xyz)
            anchor.addChild(entity)
            av.scene.addAnchor(anchor)
        }
    }
}

// MARK: — 3D Asset Import
struct ArcAssetImporter: UIViewControllerRepresentable {
    let onLoad: (SCNNode) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            UTType("com.pixar.universal-scene-description-mobile") ?? .data,
            UTType("com.pixar.universal-scene-description") ?? .data,
            UTType("model/gltf-binary") ?? .data,
            UTType(filenameExtension:"glb") ?? .data,
            UTType(filenameExtension:"usdz") ?? .data,
            UTType(filenameExtension:"obj") ?? .data,
            UTType(filenameExtension:"dae") ?? .data,
        ].compactMap { $0 }
        let vc = UIDocumentPickerViewController(forOpeningContentTypes:types, asCopy:true)
        vc.allowsMultipleSelection = false
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onLoad: onLoad) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onLoad: (SCNNode) -> Void
        init(onLoad: @escaping (SCNNode) -> Void) { self.onLoad = onLoad }

        func documentPicker(_: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            do {
                let scene = try SCNScene(url: url, options: [
                    .checkConsistency: true,
                    .convertToYUp: true,
                    .convertUnitsToMeters: 1.0
                ])
                let root = scene.rootNode.clone()
                root.name = "imported_\(url.lastPathComponent)"
                // Auto-scale: fit inside 10-unit bounding box
                let bbox = root.boundingBox
                let size = max(bbox.max.x-bbox.min.x,
                               max(bbox.max.y-bbox.min.y, bbox.max.z-bbox.min.z))
                if size > 0 { let s = 6.0/Float(size); root.scale=SCNVector3(s,s,s) }
                DispatchQueue.main.async { self.onLoad(root) }
            } catch {
                print("ArcAssetImporter: failed to load \(url.lastPathComponent): \(error)")
            }
        }
    }
}

import UniformTypeIdentifiers

// MARK: — SIMD helper
extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
