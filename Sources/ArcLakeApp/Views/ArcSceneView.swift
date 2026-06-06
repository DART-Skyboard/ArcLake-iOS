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
        private var lastOrbitTranslation = CGPoint.zero

        @objc func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began {
                lastOrbitTranslation = .zero
            }
            if g.state == .changed {
                let cur = g.translation(in: v)
                // Per-frame delta — no accumulation lag, no damping
                let dx = Float(cur.x - lastOrbitTranslation.x)
                let dy = Float(cur.y - lastOrbitTranslation.y)
                lastOrbitTranslation = cur

                theta -= dx * 0.006
                phi    = max(0.02, min(.pi - 0.02, phi - dy * 0.006))
                commit()
            }
        }

        // ── 2-finger: PAN (truck/pedestal) ───────────────────────
        // Physically moves camera + pivot through world space.
        // Speed proportional to distance so close/far feel consistent.
        // Last translation snapshot — lets us compute per-frame delta (no damping)
        private var lastPanTranslation = CGPoint.zero

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            if g.state == .began {
                lastPanTranslation = .zero
            }
            if g.state == .changed {
                let cur = g.translation(in: v)
                // Delta since last frame — 1:1 with finger, zero damping
                let dx = Float(cur.x - lastPanTranslation.x)
                let dy = Float(cur.y - lastPanTranslation.y)
                lastPanTranslation = cur

                let speed = radius * 0.0014

                // Camera local axes
                let right = SIMD3<Float>( cos(theta),  0, -sin(theta))
                let fwd   = SIMD3<Float>(-sin(theta) * sin(phi),
                                          cos(phi),
                                          -cos(theta) * sin(phi))
                let up    = cross(fwd, right)

                // X: right/left same as before
                // Y: INVERTED — drag up (negative dy) → camera moves down (scene appears to move up)
                pivot = pivot
                    - right * dx * speed
                    - up    * dy * speed   // note: minus dy = inverted vertical
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
// MARK: — ArcAssetImporter v4
// Accepts USDZ, USDC, GLB, OBJ, DAE, STL
// Auto-sanitizes Nomad/Blender exports:
//   • Fixes texture paths with spaces (Nomad Sculpt issue)
//   • Handles any metersPerUnit value correctly
//   • Fixes "dummy.usdc" primary file naming
//   • Unlimited file size — background async loading
struct ArcAssetImporter: UIViewControllerRepresentable {
    let onLoad: (SCNNode) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            UTType(filenameExtension: "usdz") ?? .data,
            UTType(filenameExtension: "usdc") ?? .data,
            UTType(filenameExtension: "usda") ?? .data,
            UTType(filenameExtension: "glb")  ?? .data,
            UTType(filenameExtension: "gltf") ?? .data,
            UTType(filenameExtension: "obj")  ?? .data,
            UTType(filenameExtension: "dae")  ?? .data,
            UTType(filenameExtension: "stl")  ?? .data,
        ].compactMap { $0 }
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onLoad: onLoad) }

    // MARK: — Coordinator
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onLoad: (SCNNode) -> Void
        init(onLoad: @escaping (SCNNode) -> Void) { self.onLoad = onLoad }

        func documentPicker(_: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // All loading is async — never blocks UI regardless of file size
            Task.detached(priority: .userInitiated) {
                await self.loadAsset(url: url)
            }
        }

        private func loadAsset(url: URL) async {
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "glb", "gltf":
                await loadGLB(url: url)
            case "usdz":
                // Sanitize first (fixes Nomad spaces, metersPerUnit, primary name)
                let sanitized = await sanitizeUSDZ(url: url)
                await loadUSD(url: sanitized ?? url)
            default:
                await loadUSD(url: url)
            }
        }

        // MARK: — USDZ Sanitizer
        // Fixes all known Nomad Sculpt export issues in-app automatically
        private func sanitizeUSDZ(url: URL) async -> URL? {
            return await Task.detached(priority: .utility) { () -> URL? in
                let fm = FileManager.default
                let tmp = fm.temporaryDirectory
                let outURL = tmp.appendingPathComponent(
                    url.deletingPathExtension().lastPathComponent + "_sanitized.usdz")

                // Check if sanitization is needed
                guard let zip = try? Foundation.FileHandle(forReadingAtPath: url.path) else {
                    return nil
                }
                zip.closeFile()

                // Extract USDZ (it's a zip)
                let workDir = tmp.appendingPathComponent("arc_usdz_work_\(UUID().uuidString)")
                try? fm.createDirectory(at: workDir, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: workDir) }

                // Use Process to unzip
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-o", url.path, "-d", workDir.path]
                try? unzip.run(); unzip.waitUntilExit()

                // Find the primary USDC/USDA
                guard let files = try? fm.contentsOfDirectory(atPath: workDir.path) else { return nil }
                let usdcFiles = files.filter { $0.hasSuffix(".usdc") || $0.hasSuffix(".usda") }
                guard let primaryName = usdcFiles.first else { return nil }
                let primaryURL = workDir.appendingPathComponent(primaryName)

                // Read metersPerUnit from the USD stage
                var needsMetricFix = false
                var needsPathFix   = false

                if let stageContent = try? String(contentsOf: primaryURL, encoding: .ascii) {
                    needsMetricFix = stageContent.contains("metersPerUnit = 100") ||
                                     stageContent.contains("metersPerUnit = 10")
                }

                // Check for spaces in texture paths (binary search)
                if let data = try? Data(contentsOf: primaryURL) {
                    // Look for space-containing path patterns in raw bytes
                    let spacePattern = Data(" ".utf8)
                    if data.range(of: spacePattern) != nil {
                        needsPathFix = true
                    }
                }

                if !needsMetricFix && !needsPathFix && primaryName != "dummy.usdc" {
                    // No fixes needed — return nil to use original
                    return nil
                }

                // Fix via pxr Python — write a fix script and run it
                let scriptURL = workDir.appendingPathComponent("fix_usd.py")
                let fixScript = """
import sys
sys.path.insert(0, '/usr/local/lib/python3.12/dist-packages')
try:
    from pxr import Usd, UsdGeom, Sdf
    stage = Usd.Stage.Open('\(primaryURL.path)')
    mpu = UsdGeom.GetStageMetersPerUnit(stage)
    if mpu >= 10:
        UsdGeom.SetStageMetersPerUnit(stage, 0.01)
    for prim in stage.Traverse():
        for attr in prim.GetAttributes():
            val = attr.Get()
            if isinstance(val, Sdf.AssetPath) and ' ' in val.path:
                new_path = val.path.replace(' ', '_')
                import re
                new_path = re.sub(r'[A-Za-z0-9]+ \\d+ ', lambda m: m.group(0).replace(' ', '_'), new_path)
                attr.Set(Sdf.AssetPath(new_path))
    stage.Export('\(primaryURL.path)')
    print('USD_FIX_OK')
except Exception as e:
    print(f'USD_FIX_ERROR: {e}')
"""
                try? fixScript.write(to: scriptURL, atomically: true, encoding: .utf8)
                let py = Process()
                py.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                py.arguments = [scriptURL.path]
                let pipe = Pipe()
                py.standardOutput = pipe
                try? py.run(); py.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8) ?? ""
                if output.contains("USD_FIX_ERROR") {
                    print("[ArcImport] USD fix error: \(output)")
                }

                // Rename texture folders/files to remove spaces
                if let textureDir = try? fm.contentsOfDirectory(atPath: workDir.path)
                    .filter({ !$0.hasSuffix(".usdc") && !$0.hasSuffix(".py") }).first {
                    let texRoot = workDir.appendingPathComponent(textureDir)
                    if var subs = try? fm.contentsOfDirectory(atPath: texRoot.path) {
                        for sub in subs where sub.contains(" ") {
                            let oldURL = texRoot.appendingPathComponent(sub)
                            let newURL = texRoot.appendingPathComponent(sub.replacingOccurrences(of: " ", with: "_"))
                            try? fm.moveItem(at: oldURL, to: newURL)
                        }
                        // Rename subfolder itself
                        subs = (try? fm.contentsOfDirectory(atPath: texRoot.path)) ?? []
                        for sub in subs {
                            if sub.contains(" ") {
                                let oldURL = texRoot.appendingPathComponent(sub)
                                let newURL = texRoot.appendingPathComponent(sub.replacingOccurrences(of: " ", with: "_"))
                                try? fm.moveItem(at: oldURL, to: newURL)
                            }
                        }
                    }
                    // Also rename the textures folder if it has spaces
                    if textureDir.contains(" ") {
                        let oldDir = workDir.appendingPathComponent(textureDir)
                        let newDir = workDir.appendingPathComponent(textureDir.replacingOccurrences(of: " ", with: "_"))
                        try? fm.moveItem(at: oldDir, to: newDir)
                    }
                }

                // Repack as valid USDZ (primary file first, uncompressed ZIP_STORED)
                let repackScript = """
import zipfile, os
out = '\(outURL.path)'
work = '\(workDir.path)'
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_STORED) as z:
    primary = '\(primaryURL.lastPathComponent)'
    z.write(os.path.join(work, primary), primary)
    for root, dirs, files in os.walk(work):
        for f in sorted(files):
            if f == primary or f.endswith('.py'): continue
            full = os.path.join(root, f)
            arc  = os.path.relpath(full, work)
            z.write(full, arc)
print('REPACK_OK')
"""
                let repackURL = workDir.appendingPathComponent("repack.py")
                try? repackScript.write(to: repackURL, atomically: true, encoding: .utf8)
                let py2 = Process()
                py2.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                py2.arguments = [repackURL.path]
                try? py2.run(); py2.waitUntilExit()

                return fm.fileExists(atPath: outURL.path) ? outURL : nil
            }.value
        }

        // MARK: — USD Load (any unit, any size)
        private func loadUSD(url: URL) async {
            await MainActor.run { } // yield to let UI stay responsive
            let options: [SCNSceneSource.LoadingOption: Any] = [
                .convertToYUp:          true,
                .convertUnitsToMeters:  1.0,    // handles any metersPerUnit
                .checkConsistency:      false,   // allow non-strict USDZ
                .flattenScene:          false,
                .createNormalsIfAbsent: true,
            ]
            do {
                let scene = try SCNScene(url: url, options: options)
                let root  = scene.rootNode.clone()
                root.name = "imported_\(url.deletingPathExtension().lastPathComponent)"
                applyMaterialFix(root)
                normalizeScale(root)
                await MainActor.run { self.onLoad(root) }
            } catch {
                print("[ArcImport] USD load error: \(error)")
            }
        }

        // MARK: — GLB Load via ModelIO
        private func loadGLB(url: URL) async {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_arc.usdz")
            do {
                let asset = MDLAsset(url: url)
                asset.loadTextures()
                try asset.export(to: tmp)
                await loadUSD(url: tmp)
                try? FileManager.default.removeItem(at: tmp)
            } catch {
                print("[ArcImport] GLB→USD error: \(error), trying direct load")
                await loadUSD(url: url)
            }
        }

        // MARK: — Material fix: emission + double-sided
        private func applyMaterialFix(_ node: SCNNode) {
            node.enumerateChildNodes { child, _ in
                guard let geo = child.geometry else { return }
                for mat in geo.materials {
                    if mat.diffuse.contents != nil && mat.emission.contents == nil {
                        mat.emission.contents = mat.diffuse.contents
                        mat.emission.intensity = 0.25
                    }
                    mat.isDoubleSided = true
                    mat.lightingModel = .physicallyBased
                }
            }
        }

        // MARK: — Scale normalization
        private func normalizeScale(_ root: SCNNode) {
            let bbox = root.boundingBox
            let sz   = max(bbox.max.x - bbox.min.x,
                           max(bbox.max.y - bbox.min.y, bbox.max.z - bbox.min.z))
            // Only normalize if size is extreme (< 0.1m or > 50m after unit conversion)
            guard sz > 0 else { return }
            if sz < 0.1 || sz > 50 {
                let s = 6.0 / Float(sz)
                root.scale = SCNVector3(s, s, s)
            }
        }
    }
}

import UniformTypeIdentifiers
extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x,y,z) }
}


