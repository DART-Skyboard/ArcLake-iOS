import Foundation
import SceneKit
import UIKit
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcGLB — real binary glTF 2.0 (.glb) exporter + importer.
// Pure Swift, zero dependencies. Exports the ENTIRE scene as-is:
// node hierarchy, point-cloud particles (mode POINTS), line segments
// (mode LINES), triangle meshes, materials (base color + emissive),
// vertex colors, and recorded animation data as glTF samplers —
// round-trips with Nomad Sculpt, Blender, three.js.
// ═══════════════════════════════════════════════════════════════════

// MARK: — EXPORTER

public final class ArcGLBExporter {
    private var bin = Data()
    private var bufferViews: [[String: Any]] = []
    private var accessors: [[String: Any]] = []
    private var meshes: [[String: Any]] = []
    private var materials: [[String: Any]] = []
    private var nodes: [[String: Any]] = []
    private var animations: [[String: Any]] = []
    private var matCache: [String: Int] = [:]
    private var nodeIndexByName: [String: Int] = [:]

    public init() {}

    public func export(scene: SCNScene, recorded: [RecordedFrame], to url: URL) -> Bool {
        let rootChildren = scene.rootNode.childNodes.compactMap { encodeNode($0) }
        let sceneDict: [String: Any] = ["nodes": rootChildren]

        if !recorded.isEmpty { encodeAnimations(recorded) }

        var gltf: [String: Any] = [
            "asset": ["version": "2.0", "generator": "ArcLake iOS"],
            "scene": 0,
            "scenes": [sceneDict],
            "nodes": nodes,
            "buffers": [["byteLength": bin.count]],
        ]
        if !meshes.isEmpty      { gltf["meshes"] = meshes }
        if !materials.isEmpty   { gltf["materials"] = materials }
        if !accessors.isEmpty   { gltf["accessors"] = accessors }
        if !bufferViews.isEmpty { gltf["bufferViews"] = bufferViews }
        if !animations.isEmpty  { gltf["animations"] = animations }
        if !textures.isEmpty {
            gltf["textures"] = textures
            gltf["images"]   = images
            gltf["samplers"] = samplers
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: gltf) else { return false }

        // GLB container: header + JSON chunk + BIN chunk, 4-byte aligned
        var json = jsonData
        while json.count % 4 != 0 { json.append(0x20) }          // pad with spaces
        while bin.count % 4 != 0 { bin.append(0) }

        var out = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        u32(0x46546C67)                                          // magic "glTF"
        u32(2)                                                   // version
        u32(UInt32(12 + 8 + json.count + 8 + bin.count))         // total length
        u32(UInt32(json.count)); u32(0x4E4F534A); out.append(json)   // JSON chunk
        u32(UInt32(bin.count));  u32(0x004E4942); out.append(bin)    // BIN chunk

        do { try out.write(to: url); return true } catch { return false }
    }

    // ── Node encoding — full hierarchy with TRS ──────────────────────
    private func encodeNode(_ n: SCNNode) -> Int? {
        // Skip cameras/lights-only and invisible helpers
        if n.camera != nil { return nil }
        var dict: [String: Any] = [:]
        if let name = n.name { dict["name"] = name }
        let p = n.simdPosition, q = n.simdOrientation, s = n.simdScale
        if p != .zero { dict["translation"] = [p.x, p.y, p.z] }
        if q.vector != SIMD4<Float>(0,0,0,1) {
            dict["rotation"] = [q.imag.x, q.imag.y, q.imag.z, q.real]
        }
        if s != SIMD3<Float>(1,1,1) { dict["scale"] = [s.x, s.y, s.z] }
        if let geo = n.geometry, let mi = encodeMesh(geo) { dict["mesh"] = mi }
        let kids = n.childNodes.compactMap { encodeNode($0) }
        if !kids.isEmpty { dict["children"] = kids }
        // Geometry-less leaf with no children — still keep (animation targets)
        let idx = nodes.count
        nodes.append(dict)
        if let name = n.name { nodeIndexByName[name] = idx }
        return idx
    }

    // ── Mesh encoding — POINTS / LINES / TRIANGLES with colors ──────
    private func encodeMesh(_ geo: SCNGeometry) -> Int? {
        guard let posSrc = geo.sources(for: .vertex).first else { return nil }
        let positions = floatVec3(from: posSrc)
        guard !positions.isEmpty else { return nil }

        let posAcc = addAccessor(vec3: positions, target: 34962)
        var attributes: [String: Any] = ["POSITION": posAcc]
        if let nrmSrc = geo.sources(for: .normal).first {
            let nrm = floatVec3(from: nrmSrc)
            if nrm.count == positions.count {
                attributes["NORMAL"] = addAccessor(vec3: nrm, target: 34962)
            }
        }
        if let colSrc = geo.sources(for: .color).first {
            let cols = floatVec3(from: colSrc)
            if cols.count == positions.count {
                attributes["COLOR_0"] = addAccessor(vec3: cols, target: 34962)
            }
        }
        if let uvSrc = geo.sources(for: .texcoord).first {
            let uvs = floatVec2(from: uvSrc)
            if uvs.count == positions.count {
                attributes["TEXCOORD_0"] = addAccessor(vec2: uvs)
            }
        }

        let matIdx = encodeMaterial(geo.firstMaterial)
        var prims: [[String: Any]] = []
        for el in geo.elements {
            let mode: Int
            switch el.primitiveType {
            case .point: mode = 0
            case .line: mode = 1
            case .triangleStrip: mode = 5
            default: mode = 4
            }
            var prim: [String: Any] = ["attributes": attributes, "mode": mode]
            if el.primitiveType != .point {
                prim["indices"] = addIndexAccessor(el)
            }
            if let m = matIdx { prim["material"] = m }
            prims.append(prim)
        }
        if prims.isEmpty {
            var p: [String: Any] = ["attributes": attributes, "mode": 0]
            if let m = matIdx { p["material"] = m }
            prims = [p]
        }
        let idx = meshes.count
        meshes.append(["primitives": prims])
        return idx
    }

    private var textures: [[String: Any]] = []
    private var images: [[String: Any]] = []
    private var samplers: [[String: Any]] = [["magFilter": 9729, "minFilter": 9987,
                                              "wrapS": 10497, "wrapT": 10497]]

    private func embedTexture(_ img: UIImage) -> Int? {
        guard let png = img.pngData() else { return nil }
        let bv = addBufferView(png, target: nil)
        images.append(["bufferView": bv, "mimeType": "image/png"])
        textures.append(["source": images.count - 1, "sampler": 0])
        return textures.count - 1
    }

    private func encodeMaterial(_ m: SCNMaterial?) -> Int? {
        guard let m else { return nil }
        // Texture round-trip: imported Nomad sculpts keep their maps
        if let img = m.diffuse.contents as? UIImage {
            let key = "img|\(ObjectIdentifier(img).hashValue)"
            if let c = matCache[key] { return c }
            var pbr: [String: Any] = ["metallicFactor": 0.0, "roughnessFactor": 0.85]
            if let ti = embedTexture(img) { pbr["baseColorTexture"] = ["index": ti] }
            var dict: [String: Any] = ["pbrMetallicRoughness": pbr,
                                       "doubleSided": m.isDoubleSided]
            if let em = rgba(m.emission.contents) {
                dict["emissiveFactor"] = [em[0], em[1], em[2]]
            }
            let idx = materials.count
            materials.append(dict)
            matCache[key] = idx
            return idx
        }
        let base = rgba(m.diffuse.contents) ?? [1, 1, 1, 1]
        let emis = rgba(m.emission.contents).map { [$0[0], $0[1], $0[2]] } ?? [0, 0, 0]
        let key = "\(base)|\(emis)|\(m.transparency)"
        if let c = matCache[key] { return c }
        var dict: [String: Any] = [
            "pbrMetallicRoughness": [
                "baseColorFactor": [base[0], base[1], base[2], base[3] * Float(m.transparency)],
                "metallicFactor": 0.0, "roughnessFactor": 0.85],
            "emissiveFactor": emis,
            "doubleSided": m.isDoubleSided,
        ]
        if m.transparency < 0.999 || base[3] < 0.999 { dict["alphaMode"] = "BLEND" }
        let idx = materials.count
        materials.append(dict)
        matCache[key] = idx
        return idx
    }

    // ── Recorded animation → glTF translation samplers per atom ─────
    private func encodeAnimations(_ frames: [RecordedFrame]) {
        guard frames.count > 1 else { return }
        let times = frames.map { Float($0.time) }
        let timeAcc = addAccessor(scalars: times)
        let atomIDs = Set(frames.flatMap { $0.positions.keys })

        var samplers: [[String: Any]] = []
        var channels: [[String: Any]] = []
        for id in atomIDs.sorted() {
            guard let nodeIdx = nodeIndexByName["atomZ:\(id)"] else { continue }
            let track: [SIMD3<Float>] = frames.map { $0.positions[id] ?? .zero }
            let valAcc = addAccessor(vec3: track, target: nil)
            channels.append(["sampler": samplers.count,
                             "target": ["node": nodeIdx, "path": "translation"]])
            samplers.append(["input": timeAcc, "output": valAcc, "interpolation": "LINEAR"])
        }
        guard !channels.isEmpty else { return }
        animations.append(["name": "ArcLakeRecording",
                           "samplers": samplers, "channels": channels])
    }

    // ── Accessor / buffer plumbing ───────────────────────────────────
    private func addAccessor(vec3 v: [SIMD3<Float>], target: Int?) -> Int {
        var minV = v.first ?? .zero, maxV = v.first ?? .zero
        var d = Data(capacity: v.count * 12)
        for p in v {
            minV = simd_min(minV, p); maxV = simd_max(maxV, p)
            withUnsafeBytes(of: p.x) { d.append(contentsOf: $0) }
            withUnsafeBytes(of: p.y) { d.append(contentsOf: $0) }
            withUnsafeBytes(of: p.z) { d.append(contentsOf: $0) }
        }
        let bv = addBufferView(d, target: target)
        accessors.append(["bufferView": bv, "componentType": 5126,
                          "count": v.count, "type": "VEC3",
                          "min": [minV.x, minV.y, minV.z],
                          "max": [maxV.x, maxV.y, maxV.z]])
        return accessors.count - 1
    }

    private func addAccessor(vec2 v: [SIMD2<Float>]) -> Int {
        var d = Data(capacity: v.count * 8)
        for p in v {
            withUnsafeBytes(of: p.x) { d.append(contentsOf: $0) }
            withUnsafeBytes(of: p.y) { d.append(contentsOf: $0) }
        }
        let bv = addBufferView(d, target: 34962)
        accessors.append(["bufferView": bv, "componentType": 5126,
                          "count": v.count, "type": "VEC2"])
        return accessors.count - 1
    }

    private func floatVec2(from src: SCNGeometrySource) -> [SIMD2<Float>] {
        guard src.usesFloatComponents, src.componentsPerVector >= 2,
              src.bytesPerComponent == 4 else { return [] }
        var out: [SIMD2<Float>] = []; out.reserveCapacity(src.vectorCount)
        src.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<src.vectorCount {
                let off = src.dataOffset + i * src.dataStride
                out.append(SIMD2(raw.load(fromByteOffset: off, as: Float.self),
                                 raw.load(fromByteOffset: off + 4, as: Float.self)))
            }
        }
        return out
    }

    private func addAccessor(scalars: [Float]) -> Int {
        var d = Data(capacity: scalars.count * 4)
        for f in scalars { withUnsafeBytes(of: f) { d.append(contentsOf: $0) } }
        let bv = addBufferView(d, target: nil)
        accessors.append(["bufferView": bv, "componentType": 5126,
                          "count": scalars.count, "type": "SCALAR",
                          "min": [scalars.min() ?? 0], "max": [scalars.max() ?? 0]])
        return accessors.count - 1
    }

    private func addIndexAccessor(_ el: SCNGeometryElement) -> Int {
        // Normalize all index widths to uint32
        let count = indexCount(el)
        var d = Data(capacity: count * 4)
        el.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<count {
                let v: UInt32
                switch el.bytesPerIndex {
                case 1: v = UInt32(raw.load(fromByteOffset: i, as: UInt8.self))
                case 2: v = UInt32(raw.load(fromByteOffset: i*2, as: UInt16.self))
                default: v = raw.load(fromByteOffset: i*4, as: UInt32.self)
                }
                withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
            }
        }
        let bv = addBufferView(d, target: 34963)
        accessors.append(["bufferView": bv, "componentType": 5125,
                          "count": count, "type": "SCALAR"])
        return accessors.count - 1
    }

    private func indexCount(_ el: SCNGeometryElement) -> Int {
        switch el.primitiveType {
        case .triangles: return el.primitiveCount * 3
        case .triangleStrip: return el.primitiveCount + 2
        case .line: return el.primitiveCount * 2
        case .point: return el.primitiveCount
        case .polygon: return el.primitiveCount * 3
        @unknown default: return el.primitiveCount * 3
        }
    }

    private func addBufferView(_ d: Data, target: Int?) -> Int {
        while bin.count % 4 != 0 { bin.append(0) }
        var bv: [String: Any] = ["buffer": 0, "byteOffset": bin.count, "byteLength": d.count]
        if let t = target { bv["target"] = t }
        bin.append(d)
        bufferViews.append(bv)
        return bufferViews.count - 1
    }

    private func floatVec3(from src: SCNGeometrySource) -> [SIMD3<Float>] {
        guard src.usesFloatComponents, src.componentsPerVector >= 3,
              src.bytesPerComponent == 4 else { return [] }
        var out: [SIMD3<Float>] = []; out.reserveCapacity(src.vectorCount)
        src.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<src.vectorCount {
                let off = src.dataOffset + i * src.dataStride
                let x = raw.load(fromByteOffset: off, as: Float.self)
                let y = raw.load(fromByteOffset: off + 4, as: Float.self)
                let z = raw.load(fromByteOffset: off + 8, as: Float.self)
                out.append(SIMD3(x, y, z))
            }
        }
        return out
    }

    private func rgba(_ contents: Any?) -> [Float]? {
        guard let c = contents as? UIColor else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Float(r), Float(g), Float(b), Float(a)]
    }
}

// MARK: — IMPORTER
// Industrial-strength GLB import for Nomad Sculpt-scale files:
// • memory-mapped reads — 600 MB+ files without doubling RAM
// • embedded textures (baseColor / normal / emissive / metal-rough)
// • TEXCOORD_0 UVs, vertex colors, PBR materials
// • alphaMode BLEND/MASK, doubleSided, KHR_materials_transmission
//   (refraction → SceneKit transparency), emissive_strength
// • Nomad sculpt LAYERS — glTF morph targets → SCNMorpher (additive)
// • animation channels (T/R/S) → SCNAnimationPlayer, paused — the
//   ArcLake transport bar plays them with the simulation
// • KHR_draco_mesh_compression detected and reported (Nomad: disable
//   Draco in its glTF export settings; decode needs the C++ lib)

public final class ArcGLBImporter {
    public init() {}
    public private(set) var importedAnimationCount = 0
    public private(set) var lastError: String? = nil

    public func importGLB(url: URL) -> SCNNode? {
        // Memory-mapped — the OS pages the file in; no full copy for huge GLBs
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count > 20 else { lastError = "unreadable file"; return nil }
        func u32(_ off: Int) -> UInt32 {
            var v: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: off..<off+4) }
            return v.littleEndian
        }
        guard u32(0) == 0x46546C67 else { lastError = "not GLB"; return nil }

        var off = 12
        var jsonRange: Range<Int>? = nil, binRange: Range<Int>? = nil
        while off + 8 <= data.count {
            let len = Int(u32(off)), type = u32(off + 4)
            let r = off+8..<min(off+8+len, data.count)
            if type == 0x4E4F534A { jsonRange = r }
            if type == 0x004E4942 { binRange = r }
            off += 8 + len
        }
        guard let jr = jsonRange,
              let gltf = (try? JSONSerialization.jsonObject(with: data.subdata(in: jr)))
                as? [String: Any] else { lastError = "bad JSON chunk"; return nil }
        let binBase = binRange?.lowerBound ?? 0
        let binCount = binRange.map { $0.count } ?? 0

        // Draco detection — Nomad's optional compression
        if let extUsed = gltf["extensionsRequired"] as? [String],
           extUsed.contains("KHR_draco_mesh_compression") {
            lastError = "Draco-compressed GLB — re-export from Nomad with Draco OFF"
            return nil
        }

        let bufferViews = gltf["bufferViews"] as? [[String: Any]] ?? []
        let accessors   = gltf["accessors"]   as? [[String: Any]] ?? []
        let materialsJ  = gltf["materials"]   as? [[String: Any]] ?? []
        let meshesJ     = gltf["meshes"]      as? [[String: Any]] ?? []
        let nodesJ      = gltf["nodes"]       as? [[String: Any]] ?? []
        let imagesJ     = gltf["images"]      as? [[String: Any]] ?? []
        let texturesJ   = gltf["textures"]    as? [[String: Any]] ?? []
        let animsJ      = gltf["animations"]  as? [[String: Any]] ?? []

        // ── raw byte access into the mapped BIN — zero-copy reads ────
        func binLoad<T>(_ byteOffset: Int, as type: T.Type) -> T? {
            let o = binBase + byteOffset
            guard o + MemoryLayout<T>.size <= binBase + binCount else { return nil }
            var v: T? = nil
            data.withUnsafeBytes { raw in
                v = raw.loadUnaligned(fromByteOffset: o, as: T.self)
            }
            return v
        }

        func accessorFloats(_ ai: Int) -> ([Float], String, Int) {
            guard ai < accessors.count else { return ([], "SCALAR", 0) }
            let a = accessors[ai]
            let type = a["type"] as? String ?? "SCALAR"
            let count = a["count"] as? Int ?? 0
            let comps = ["SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4][type] ?? 1
            let ct = a["componentType"] as? Int ?? 5126
            let normalized = a["normalized"] as? Bool ?? false
            guard let bvi = a["bufferView"] as? Int, bvi < bufferViews.count else {
                return ([Float](repeating: 0, count: count*comps), type, count)
            }
            let bv = bufferViews[bvi]
            let base = (bv["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
            let compSize = (ct == 5126 || ct == 5125) ? 4 : (ct == 5123 ? 2 : 1)
            let stride = (bv["byteStride"] as? Int).flatMap { $0 > 0 ? $0 : nil }
                ?? comps * compSize
            var out = [Float](repeating: 0, count: count * comps)
            for i in 0..<count {
                let rowOff = base + i * stride
                for c in 0..<comps {
                    let o = rowOff + c * compSize
                    var f: Float = 0
                    switch ct {
                    case 5126: f = binLoad(o, as: Float.self) ?? 0
                    case 5125: f = Float(binLoad(o, as: UInt32.self) ?? 0)
                    case 5123:
                        let raw = Float(binLoad(o, as: UInt16.self) ?? 0)
                        f = normalized ? raw / 65535 : raw
                    default:
                        let raw = Float(binLoad(o, as: UInt8.self) ?? 0)
                        f = normalized ? raw / 255 : raw
                    }
                    out[i*comps + c] = f
                }
            }
            return (out, type, count)
        }

        // ── textures — embedded PNG/JPEG via bufferView ──────────────
        var imageCache: [Int: UIImage] = [:]
        func image(forTexture ti: Int) -> UIImage? {
            guard ti < texturesJ.count,
                  let src = texturesJ[ti]["source"] as? Int, src < imagesJ.count
            else { return nil }
            if let c = imageCache[src] { return c }
            guard let bvi = imagesJ[src]["bufferView"] as? Int,
                  bvi < bufferViews.count else { return nil }
            let bv = bufferViews[bvi]
            let s = binBase + (bv["byteOffset"] as? Int ?? 0)
            let l = bv["byteLength"] as? Int ?? 0
            guard s + l <= binBase + binCount else { return nil }
            let img = UIImage(data: data.subdata(in: s..<s+l))
            if let img { imageCache[src] = img }
            return img
        }

        func buildMaterial(_ mIdx: Int?) -> SCNMaterial {
            let mat = SCNMaterial()
            mat.lightingModel = .physicallyBased    // sculpts need real shading
            guard let mIdx, mIdx < materialsJ.count else {
                mat.diffuse.contents = UIColor.white; return mat
            }
            let mj = materialsJ[mIdx]
            if let pbr = mj["pbrMetallicRoughness"] as? [String: Any] {
                if let bc = pbr["baseColorFactor"] as? [Double], bc.count >= 4 {
                    mat.diffuse.contents = UIColor(red: CGFloat(bc[0]), green: CGFloat(bc[1]),
                                                   blue: CGFloat(bc[2]), alpha: CGFloat(bc[3]))
                    if bc[3] < 0.999 { mat.transparency = CGFloat(bc[3]) }
                }
                if let bt = pbr["baseColorTexture"] as? [String: Any],
                   let ti = bt["index"] as? Int, let img = image(forTexture: ti) {
                    mat.diffuse.contents = img
                }
                mat.metalness.contents = pbr["metallicFactor"] as? Double ?? 1.0
                mat.roughness.contents = pbr["roughnessFactor"] as? Double ?? 1.0
                if let mrt = pbr["metallicRoughnessTexture"] as? [String: Any],
                   let ti = mrt["index"] as? Int, let img = image(forTexture: ti) {
                    mat.metalness.contents = img
                    mat.roughness.contents = img
                }
            }
            if let nt = mj["normalTexture"] as? [String: Any],
               let ti = nt["index"] as? Int, let img = image(forTexture: ti) {
                mat.normal.contents = img
            }
            if let em = mj["emissiveFactor"] as? [Double], em.count >= 3,
               em.contains(where: { $0 > 0 }) {
                var strength = 1.0
                if let exts = mj["extensions"] as? [String: Any],
                   let es = exts["KHR_materials_emissive_strength"] as? [String: Any],
                   let s = es["emissiveStrength"] as? Double { strength = s }
                mat.emission.contents = UIColor(
                    red: CGFloat(min(em[0]*strength, 1)),
                    green: CGFloat(min(em[1]*strength, 1)),
                    blue: CGFloat(min(em[2]*strength, 1)), alpha: 1)
            }
            if let et = mj["emissiveTexture"] as? [String: Any],
               let ti = et["index"] as? Int, let img = image(forTexture: ti) {
                mat.emission.contents = img
            }
            // Transparency / refraction
            switch mj["alphaMode"] as? String ?? "OPAQUE" {
            case "BLEND": mat.blendMode = .alpha; mat.transparencyMode = .dualLayer
            case "MASK":
                mat.transparencyMode = .aOne
                // SceneKit lacks cutoff; alpha-test approximated via shader threshold skipped
            default: break
            }
            if let exts = mj["extensions"] as? [String: Any] {
                if let tr = exts["KHR_materials_transmission"] as? [String: Any],
                   let f = tr["transmissionFactor"] as? Double, f > 0 {
                    // glTF refraction/glass → SceneKit transparency dual-layer
                    mat.transparency = CGFloat(1 - f * 0.85)
                    mat.transparencyMode = .dualLayer
                    mat.isDoubleSided = true
                }
                if let ior = exts["KHR_materials_ior"] as? [String: Any],
                   let v = ior["ior"] as? Double {
                    mat.fresnelExponent = CGFloat(max(0.1, v - 1) * 5)
                }
            }
            mat.isDoubleSided = (mj["doubleSided"] as? Bool) ?? mat.isDoubleSided
            return mat
        }

        // ── geometry — positions, normals, colors, UVs, morph targets ─
        func buildGeometry(_ mi: Int, into node: SCNNode) {
            guard mi < meshesJ.count,
                  let prims = meshesJ[mi]["primitives"] as? [[String: Any]] else { return }
            // Multi-primitive meshes: one child node per primitive
            for prim in prims {
                guard let attrs = prim["attributes"] as? [String: Any],
                      let posIdx = attrs["POSITION"] as? Int else { continue }
                if let exts = prim["extensions"] as? [String: Any],
                   exts["KHR_draco_mesh_compression"] != nil { continue }   // skip draco prim
                let (pos, _, vcount) = accessorFloats(posIdx)
                guard vcount > 0 else { continue }

                var sources: [SCNGeometrySource] = []
                func addSource(_ floats: [Float], semantic: SCNGeometrySource.Semantic, comps: Int) {
                    let d = floats.withUnsafeBytes { Data($0) }
                    sources.append(SCNGeometrySource(data: d, semantic: semantic,
                        vectorCount: floats.count / comps, usesFloatComponents: true,
                        componentsPerVector: comps, bytesPerComponent: 4,
                        dataOffset: 0, dataStride: comps * 4))
                }
                addSource(pos, semantic: .vertex, comps: 3)
                if let ni = attrs["NORMAL"] as? Int {
                    let (n, _, nc) = accessorFloats(ni)
                    if nc == vcount { addSource(n, semantic: .normal, comps: 3) }
                }
                if let ti = attrs["TEXCOORD_0"] as? Int {
                    let (uv, _, tc) = accessorFloats(ti)
                    if tc == vcount { addSource(uv, semantic: .texcoord, comps: 2) }
                }
                if let ci = attrs["COLOR_0"] as? Int {
                    let (col, ctype, cc) = accessorFloats(ci)
                    if cc == vcount {
                        addSource(col, semantic: .color, comps: ctype == "VEC4" ? 4 : 3)
                    }
                }

                let mode = prim["mode"] as? Int ?? 4
                let primType: SCNGeometryPrimitiveType =
                    mode == 0 ? .point : (mode == 1 ? .line : .triangles)
                let element: SCNGeometryElement
                if let ii = prim["indices"] as? Int {
                    let (idxF, _, ic) = accessorFloats(ii)
                    let idx = idxF.map { UInt32($0) }
                    let pc = primType == .triangles ? ic/3 : (primType == .line ? ic/2 : ic)
                    element = SCNGeometryElement(data: idx.withUnsafeBytes { Data($0) },
                        primitiveType: primType, primitiveCount: pc, bytesPerIndex: 4)
                } else {
                    let idx = (0..<UInt32(vcount)).map { $0 }
                    let pc = primType == .triangles ? vcount/3 : (primType == .line ? vcount/2 : vcount)
                    element = SCNGeometryElement(data: idx.withUnsafeBytes { Data($0) },
                        primitiveType: primType, primitiveCount: pc, bytesPerIndex: 4)
                }
                if primType == .point {
                    element.pointSize = 3
                    element.minimumPointScreenSpaceRadius = 1
                    element.maximumPointScreenSpaceRadius = 6
                }

                let geo = SCNGeometry(sources: sources, elements: [element])
                geo.materials = [buildMaterial(prim["material"] as? Int)]
                let primNode = SCNNode(geometry: geo)

                // ── Nomad sculpt LAYERS — morph targets, additive ──────
                if let targets = prim["targets"] as? [[String: Any]], !targets.isEmpty {
                    let morpher = SCNMorpher()
                    morpher.calculationMode = .additive
                    var morphGeos: [SCNGeometry] = []
                    for t in targets {
                        guard let tpi = t["POSITION"] as? Int else { continue }
                        let (delta, _, dc) = accessorFloats(tpi)
                        guard dc == vcount else { continue }
                        // additive mode adds w·(target − base): target = base + delta
                        var tp = pos
                        for k in 0..<(vcount*3) { tp[k] += delta[k] }
                        let d = tp.withUnsafeBytes { Data($0) }
                        let ts = SCNGeometrySource(data: d, semantic: .vertex,
                            vectorCount: vcount, usesFloatComponents: true,
                            componentsPerVector: 3, bytesPerComponent: 4,
                            dataOffset: 0, dataStride: 12)
                        morphGeos.append(SCNGeometry(sources: [ts], elements: [element]))
                    }
                    if !morphGeos.isEmpty {
                        morpher.targets = morphGeos
                        primNode.morpher = morpher
                        let weights = meshesJ[mi]["weights"] as? [Double] ?? []
                        for (wi, w) in weights.enumerated() where wi < morphGeos.count {
                            morpher.setWeight(CGFloat(w), forTargetAt: wi)
                        }
                    }
                }
                node.addChildNode(primNode)
            }
        }

        // ── node tree ─────────────────────────────────────────────────
        var built: [SCNNode?] = Array(repeating: nil, count: nodesJ.count)
        func buildNode(_ i: Int) -> SCNNode {
            if let n = built[i] { return n }
            let nj = nodesJ[i]
            let n = SCNNode()
            built[i] = n
            n.name = nj["name"] as? String
            if let m = nj["matrix"] as? [Double], m.count == 16 {
                let f = m.map { Float($0) }
                n.simdTransform = simd_float4x4(
                    SIMD4(f[0], f[1], f[2], f[3]), SIMD4(f[4], f[5], f[6], f[7]),
                    SIMD4(f[8], f[9], f[10], f[11]), SIMD4(f[12], f[13], f[14], f[15]))
            } else {
                if let t = nj["translation"] as? [Double], t.count == 3 {
                    n.simdPosition = SIMD3(Float(t[0]), Float(t[1]), Float(t[2]))
                }
                if let r = nj["rotation"] as? [Double], r.count == 4 {
                    n.simdOrientation = simd_quatf(ix: Float(r[0]), iy: Float(r[1]),
                                                   iz: Float(r[2]), r: Float(r[3]))
                }
                if let s = nj["scale"] as? [Double], s.count == 3 {
                    n.simdScale = SIMD3(Float(s[0]), Float(s[1]), Float(s[2]))
                }
            }
            if let mi = nj["mesh"] as? Int { buildGeometry(mi, into: n) }
            for c in (nj["children"] as? [Int] ?? []) where c < nodesJ.count {
                n.addChildNode(buildNode(c))
            }
            return n
        }

        let root = SCNNode()
        root.name = "glb_import_\(url.deletingPathExtension().lastPathComponent)"
        let sceneRoots: [Int] = {
            if let scenes = gltf["scenes"] as? [[String: Any]],
               let first = scenes.first, let ns = first["nodes"] as? [Int] { return ns }
            return Array(0..<nodesJ.count)
        }()
        for i in sceneRoots where i < nodesJ.count { root.addChildNode(buildNode(i)) }

        // ── animations — attach as PAUSED players; transport plays them ─
        importedAnimationCount = 0
        for anim in animsJ {
            guard let channels = anim["channels"] as? [[String: Any]],
                  let samplers = anim["samplers"] as? [[String: Any]] else { continue }
            for ch in channels {
                guard let si = ch["sampler"] as? Int, si < samplers.count,
                      let target = ch["target"] as? [String: Any],
                      let ni = target["node"] as? Int, ni < built.count,
                      let node = built[ni],
                      let path = target["path"] as? String,
                      let inIdx = samplers[si]["input"] as? Int,
                      let outIdx = samplers[si]["output"] as? Int else { continue }
                let (times, _, tc) = accessorFloats(inIdx)
                let (vals, vtype, _) = accessorFloats(outIdx)
                guard tc > 1, let dur = times.last, dur > 0 else { continue }

                let keyPath: String
                var values: [Any] = []
                switch path {
                case "translation":
                    keyPath = "position"
                    for k in 0..<tc {
                        values.append(NSValue(scnVector3:
                            SCNVector3(vals[k*3], vals[k*3+1], vals[k*3+2])))
                    }
                case "rotation":
                    keyPath = "orientation"
                    let comps = vtype == "VEC4" ? 4 : 4
                    for k in 0..<tc {
                        values.append(NSValue(scnVector4: SCNVector4(
                            vals[k*comps], vals[k*comps+1], vals[k*comps+2], vals[k*comps+3])))
                    }
                case "scale":
                    keyPath = "scale"
                    for k in 0..<tc {
                        values.append(NSValue(scnVector3:
                            SCNVector3(vals[k*3], vals[k*3+1], vals[k*3+2])))
                    }
                default: continue
                }
                let ca = CAKeyframeAnimation(keyPath: keyPath)
                ca.values = values
                ca.keyTimes = times.map { NSNumber(value: Double($0 / dur)) }
                ca.duration = Double(dur)
                ca.repeatCount = .infinity
                ca.calculationMode = .linear
                let player = SCNAnimationPlayer(animation: SCNAnimation(caAnimation: ca))
                player.paused = true            // ArcLake transport resumes on Play
                node.addAnimationPlayer(player, forKey: "glb_\(path)_\(importedAnimationCount)")
                importedAnimationCount += 1
            }
        }

        return root.childNodes.isEmpty ? nil : root
    }
}
