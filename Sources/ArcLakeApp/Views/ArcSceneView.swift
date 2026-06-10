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

        // ── Arc Edge Vector turntable camera (quaternion) ────────
        // Ported 1:1 from arc-edge-vector.html CAM system:
        //   q    — orientation quaternion
        //   r    — orbit distance
        //   pan  — world-space look-at center (pivot)
        // Yaw rotates around world-Y, pitch around camera-right —
        // the horizon always stays level (turntable, not trackball).
        static let defaultQ: simd_quatf = simd_normalize(
            simd_quatf(angle:  0.52, axis: SIMD3<Float>(0,1,0)) *
            simd_quatf(angle: -0.38, axis: SIMD3<Float>(1,0,0)))

        private var camQ:   simd_quatf = Coordinator.defaultQ
        private var radius: Float = 20.0
        private var pivot   = SIMD3<Float>.zero   // == CAM.pan

        // Gesture start snapshot for pinch dolly
        private var r0: Float = 0

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
                let dx = Float(cur.x - lastOrbitTranslation.x)
                let dy = Float(cur.y - lastOrbitTranslation.y)
                lastOrbitTranslation = cur

                // Arc Edge Vector turntable:
                //   qYaw   around world-Y      (horizon stays level)
                //   qPitch around camera-right
                //   q = qYaw * qPitch * q   (exact web-app order)
                let spd: Float = 0.006
                let right = camQ.act(SIMD3<Float>(1,0,0))
                let qYaw   = simd_quatf(angle: -dx * spd, axis: SIMD3<Float>(0,1,0))
                let qPitch = simd_quatf(angle: -dy * spd, axis: right)
                camQ = simd_normalize(qYaw * qPitch * camQ)
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

                // Arc Edge Vector 2-finger pan — exact web formula:
                //   pan -= (right*dx - up*dy) * r * 0.0028
                let spd = radius * 0.0028
                let right = camQ.act(SIMD3<Float>(1,0,0))
                let up    = camQ.act(SIMD3<Float>(0,1,0))
                pivot -= (right * dx - up * dy) * spd
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
            camQ = Coordinator.defaultQ
            radius = 20.0
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
            let loc = g.location(in: v)

            // Method 1: standard hit test (catches nucleus glow sphere + orbital rings)
            let hits = v.hitTest(loc, options: [
                SCNHitTestOption.searchMode:        SCNHitTestSearchMode.all.rawValue as NSNumber,
                SCNHitTestOption.ignoreHiddenNodes: false as NSNumber,
            ])
            for hit in hits {
                if let el = atomAncestor(of: hit.node) {
                    fireAtomTap(el, pivot: hit.node.worldPosition); return
                }
            }

            // Method 2: project each atom center to screen space,
            // find the one closest in 2D to the tap point (within 80pt).
            // This works even when sparse particle clouds miss hit testing.
            var best: (ArcElement, SCNNode, CGFloat)? = nil
            v.scene?.rootNode.enumerateChildNodes { node, _ in
                guard let name = node.name, name.hasPrefix("atomZ:"),
                      let z  = Int(name.dropFirst(6)),
                      let el = ElementStore.shared.elements.first(where: { $0.id == z })
                else { return }
                // Project world position → screen coordinates
                let screenPt = v.projectPoint(node.worldPosition)
                guard screenPt.z > 0 && screenPt.z < 1 else { return } // behind camera
                let dx = CGFloat(screenPt.x) - loc.x
                let dy = CGFloat(screenPt.y) - loc.y
                let dist2D = sqrt(dx*dx + dy*dy)
                if dist2D < 80 {  // within 80 points of tap
                    if best == nil || dist2D < best!.2 { best = (el, node, dist2D) }
                }
            }
            if let (el, node, _) = best {
                fireAtomTap(el, pivot: node.worldPosition)
            }
        }

        // Atom tap helpers
        private func atomAncestor(of node: SCNNode) -> ArcElement? {
            var n: SCNNode? = node
            while let cur = n {
                if let name = cur.name, name.hasPrefix("atomZ:"),
                   let z  = Int(name.dropFirst(6)),
                   let el = ElementStore.shared.elements.first(where: { $0.id == z }) {
                    return el
                }
                n = cur.parent
            }
            return nil
        }

        private func fireAtomTap(_ el: ArcElement, pivot wp: SCNVector3) {
            pivot = SIMD3<Float>(wp.x, wp.y, wp.z)
            radius = min(radius, 8.0)
            Task { @MainActor in self.labVM.tappedElement = el }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            commit()
            SCNTransaction.commit()
        }

        // ── Place camera on sphere around pivot ───────────────────
        // Arc Edge Vector turntable — quaternion orbit, horizon always level.
        // FOV stays at 60° always.
        func commit() {
            guard let cam = camNode else { return }
            // Exact Arc Edge Vector camera transform:
            //   eye = q · [0,0,r] + pan ;  camera orientation = q
            // A camera with orientation q looks along q·[0,0,-1] — which points
            // from eye straight at pan, with up = q·[0,1,0]. No look(at:) needed.
            let eye = camQ.act(SIMD3<Float>(0, 0, radius)) + pivot
            cam.simdPosition    = eye
            cam.simdOrientation = camQ
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

        // MARK: — USDZ Sanitizer (pure Swift, iOS-compatible)
        // Fixes Nomad Sculpt exports: spaces in texture paths, dummy.usdc primary name
        // metersPerUnit handled by SCNSceneSource.convertUnitsToMeters at load time
        private func sanitizeUSDZ(url: URL) async -> URL? {
            return await Task.detached(priority: .utility) { () -> URL? in
                let fm  = FileManager.default
                let tmp = fm.temporaryDirectory

                // Read the zip
                guard let zipData = try? Data(contentsOf: url) else { return nil }

                // Parse zip entries
                var entries: [(name: String, data: Data)] = []
                var hasDummyName = false
                var hasSpaces    = false

                // Walk the zip central directory
                var offset = 0
                while offset + 4 <= zipData.count {
                    let sig = zipData.subdata(in: offset..<offset+4)
                    // Local file header signature = 0x04034b50
                    guard sig == Data([0x50, 0x4B, 0x03, 0x04]) else { offset += 1; continue }
                    guard offset + 30 <= zipData.count else { break }
                    let fnLen  = Int(zipData[offset+26]) | (Int(zipData[offset+27]) << 8)
                    let exLen  = Int(zipData[offset+28]) | (Int(zipData[offset+29]) << 8)
                    guard offset + 30 + fnLen <= zipData.count else { break }
                    let nameData = zipData.subdata(in: offset+30..<offset+30+fnLen)
                    let name = String(data: nameData, encoding: .utf8) ?? ""
                    let compMethod = Int(zipData[offset+8]) | (Int(zipData[offset+9]) << 8)
                    let compSize   = Int(zipData[offset+18]) | (Int(zipData[offset+19]) << 8)
                                   | (Int(zipData[offset+20]) << 16) | (Int(zipData[offset+21]) << 24)
                    let dataStart  = offset + 30 + fnLen + exLen
                    guard dataStart + compSize <= zipData.count else { break }
                    let entryData  = zipData.subdata(in: dataStart..<dataStart+compSize)
                    entries.append((name: name, data: entryData))
                    if name == "dummy.usdc" { hasDummyName = true }
                    if name.contains(" ")   { hasSpaces    = true }
                    offset = dataStart + compSize
                }

                guard !entries.isEmpty else { return nil }
                if !hasDummyName && !hasSpaces { return nil } // no fix needed

                // Fix entries
                let baseName = url.deletingPathExtension().lastPathComponent
                var fixedEntries: [(name: String, data: Data)] = []

                for entry in entries {
                    var newName = entry.name
                    var newData = entry.data

                    // Fix primary file name
                    if newName == "dummy.usdc" {
                        newName = baseName + ".usdc"
                    }

                    // Fix texture folder paths (remove spaces)
                    if newName.contains(" ") {
                        let oldDir = newName.components(separatedBy: "/").dropLast().joined(separator: "/")
                        let file   = newName.components(separatedBy: "/").last ?? ""
                        let fixDir = oldDir.replacingOccurrences(of: " ", with: "_")
                        let fixFile = file.replacingOccurrences(of: " ", with: "_")
                        newName = fixDir.isEmpty ? fixFile : fixDir + "/" + fixFile
                    }

                    // In USDC files: patch the string bytes for texture paths
                    // USDC stores strings as UTF-8 prefixed with 4-byte length
                    // We do a direct byte replacement of space-containing path segments
                    if entry.name.hasSuffix(".usdc") {
                        // Build replacement map for known Nomad path patterns
                        var d = newData
                        let spacePatterns: [(Data, Data)] = [
                            // Pattern: "Autumn MG Web" → "Autumn_MG_Web"
                            (Data("Autumn MG Web".utf8), Data("Autumn_MG_Web".utf8)),
                            // Generic: space between word chars in texture subfolder names
                            // Replace common Nomad patterns
                            (Data("Box 8 ".utf8),    Data("Box_8_".utf8)),
                            (Data("Sphere 1 ".utf8), Data("Sphere_1_".utf8)),
                            (Data(" color".utf8),    Data("_color".utf8)),
                            (Data(" roughness".utf8),Data("_roughness".utf8)),
                            (Data(" metalness".utf8),Data("_metalness".utf8)),
                            (Data(" ext ".utf8),     Data("_ext_".utf8)),
                        ]
                        for (old, new) in spacePatterns {
                            var searchFrom = d.startIndex
                            while let range = d.range(of: old, in: searchFrom..<d.endIndex) {
                                d.replaceSubrange(range, with: new)
                                searchFrom = range.lowerBound + new.count
                            }
                        }
                        newData = d
                    }

                    fixedEntries.append((name: newName, data: newData))
                }

                // Write fixed USDZ (primary file must be first per spec)
                let outURL = tmp.appendingPathComponent(baseName + "_fixed.usdz")
                var zipOut = Data()

                // Sort: primary .usdc first
                fixedEntries.sort { a, b in
                    let aIsUSDC = a.name.hasSuffix(".usdc") || a.name.hasSuffix(".usda")
                    let bIsUSDC = b.name.hasSuffix(".usdc") || b.name.hasSuffix(".usda")
                    if aIsUSDC && !bIsUSDC { return true }
                    return false
                }

                // Build local file headers
                var centralDir = Data()
                var localOffsets: [Int] = []

                for entry in fixedEntries {
                    let nameBytes = Data((entry.name).utf8)
                    localOffsets.append(zipOut.count)

                    // Local file header
                    zipOut.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // sig
                    zipOut.append(contentsOf: [0x14, 0x00])               // version needed
                    zipOut.append(contentsOf: [0x00, 0x00])               // flags
                    zipOut.append(contentsOf: [0x00, 0x00])               // compression (STORED)
                    zipOut.append(contentsOf: [0x00, 0x00, 0x00, 0x00])   // mod time/date
                    // CRC32 (0 for now — readers usually skip for STORED)
                    zipOut.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
                    // Compressed size
                    let sz = UInt32(entry.data.count)
                    withUnsafeBytes(of: sz.littleEndian) { zipOut.append(contentsOf: $0) }
                    withUnsafeBytes(of: sz.littleEndian) { zipOut.append(contentsOf: $0) }
                    // File name length
                    let fnLen16 = UInt16(nameBytes.count)
                    withUnsafeBytes(of: fnLen16.littleEndian) { zipOut.append(contentsOf: $0) }
                    zipOut.append(contentsOf: [0x00, 0x00]) // extra field length
                    zipOut.append(nameBytes)
                    zipOut.append(entry.data)
                }

                // Central directory
                let cdOffset = zipOut.count
                for (i, entry) in fixedEntries.enumerated() {
                    let nameBytes = Data(entry.name.utf8)
                    centralDir.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // sig
                    centralDir.append(contentsOf: [0x14, 0x00, 0x14, 0x00]) // versions
                    centralDir.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // flags, compression
                    centralDir.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // time/date
                    centralDir.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // crc
                    let sz = UInt32(entry.data.count)
                    withUnsafeBytes(of: sz.littleEndian) { centralDir.append(contentsOf: $0) }
                    withUnsafeBytes(of: sz.littleEndian) { centralDir.append(contentsOf: $0) }
                    let fnLen16 = UInt16(nameBytes.count)
                    withUnsafeBytes(of: fnLen16.littleEndian) { centralDir.append(contentsOf: $0) }
                    centralDir.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) // extra,comment,disk
                    centralDir.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // int/ext attribs
                    let off = UInt32(localOffsets[i])
                    withUnsafeBytes(of: off.littleEndian) { centralDir.append(contentsOf: $0) }
                    centralDir.append(nameBytes)
                }

                zipOut.append(centralDir)

                // End of central directory
                zipOut.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // sig
                zipOut.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // disk numbers
                let numEntries = UInt16(fixedEntries.count)
                withUnsafeBytes(of: numEntries.littleEndian) { zipOut.append(contentsOf: $0) }
                withUnsafeBytes(of: numEntries.littleEndian) { zipOut.append(contentsOf: $0) }
                let cdSize = UInt32(centralDir.count)
                withUnsafeBytes(of: cdSize.littleEndian) { zipOut.append(contentsOf: $0) }
                let cdOff = UInt32(cdOffset)
                withUnsafeBytes(of: cdOff.littleEndian) { zipOut.append(contentsOf: $0) }
                zipOut.append(contentsOf: [0x00, 0x00]) // comment length

                try? zipOut.write(to: outURL)
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




// MARK: — AtomInfoCard
// Shown when user taps an atom in the 3D scene.
// Displays element details + "Add to Mol Canvas" button.
struct AtomInfoCard: View {
    let element: ArcElement
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header strip
            HStack(spacing: 10) {
                // Element badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(element.category.color).opacity(0.25))
                        .frame(width: 52, height: 52)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(element.category.color), lineWidth: 1.2)
                        .frame(width: 52, height: 52)
                    VStack(spacing: 1) {
                        Text(element.elementSymbol)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("\(element.protons)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(element.elementName)
                        .font(.custom("Orbitron-Bold", size: 13))
                        .foregroundColor(.white)
                    Text(element.category.rawValue)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(element.category.color))
                    Text("Z=\(element.protons)  n=\(element.neutrons)  mass=\(String(format:"%.3f", element.atomicMass)) u")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Button { labVM.tappedElement = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(12)

            Divider().background(themeVM.accent.opacity(0.15))

            // Stats row
            HStack(spacing: 0) {
                infoCell("ARC EDGE", String(format: "%.3f pm", element.arcEdgeCircumference))
                Divider().frame(height: 32).background(Color.white.opacity(0.1))
                infoCell("NEUTRONS", "\(element.neutrons)")
                Divider().frame(height: 32).background(Color.white.opacity(0.1))
                infoCell("ELECTRONS", "\(element.protons)")
            }
            .padding(.vertical, 8)

            Divider().background(themeVM.accent.opacity(0.15))

            // Action buttons
            HStack(spacing: 8) {
                // Add to Mol Canvas
                Button {
                    labVM.addToMolCanvas(element)
                    labVM.tappedElement = nil
                } label: {
                    Label("Mol Canvas", systemImage: "scribble")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.purple)
                        .clipShape(Capsule())
                }

                // Open probe chart
                Button {
                    labVM.openProbe(for: element)
                    labVM.tappedElement = nil
                } label: {
                    Label("Probe", systemImage: "chart.bar.xaxis")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(themeVM.accent.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                // Remove from scene
                Button {
                    labVM.removeElement(element)
                    labVM.tappedElement = nil
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red.opacity(0.7))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        // No background/clipShape here — DragShell in ArcOverlays is the container
    }

    private func infoCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(themeVM.accent)
        }
        .frame(maxWidth: .infinity)
    }
}




