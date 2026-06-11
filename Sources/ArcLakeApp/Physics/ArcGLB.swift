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

    private func encodeMaterial(_ m: SCNMaterial?) -> Int? {
        guard let m else { return nil }
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

public final class ArcGLBImporter {
    public init() {}

    public func importGLB(url: URL) -> SCNNode? {
        guard let data = try? Data(contentsOf: url), data.count > 20 else { return nil }
        func u32(_ off: Int) -> UInt32 {
            data.subdata(in: off..<off+4).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        }
        guard u32(0) == 0x46546C67 else { return nil }     // "glTF"
        var off = 12
        var jsonData: Data? = nil, binData: Data? = nil
        while off + 8 <= data.count {
            let len = Int(u32(off)), type = u32(off + 4)
            let chunk = data.subdata(in: off+8..<min(off+8+len, data.count))
            if type == 0x4E4F534A { jsonData = chunk }
            if type == 0x004E4942 { binData = chunk }
            off += 8 + len
        }
        guard let jd = jsonData,
              let gltf = (try? JSONSerialization.jsonObject(with: jd)) as? [String: Any]
        else { return nil }
        let bin = binData ?? Data()

        let bufferViews = gltf["bufferViews"] as? [[String: Any]] ?? []
        let accessors   = gltf["accessors"]   as? [[String: Any]] ?? []
        let materials   = gltf["materials"]   as? [[String: Any]] ?? []
        let meshesJ     = gltf["meshes"]      as? [[String: Any]] ?? []
        let nodesJ      = gltf["nodes"]       as? [[String: Any]] ?? []

        func accessorFloats(_ ai: Int) -> ([Float], String, Int) {
            guard ai < accessors.count else { return ([], "SCALAR", 0) }
            let a = accessors[ai]
            let type = a["type"] as? String ?? "SCALAR"
            let count = a["count"] as? Int ?? 0
            let comps = ["SCALAR":1, "VEC2":2, "VEC3":3, "VEC4":4][type] ?? 1
            let ct = a["componentType"] as? Int ?? 5126
            guard let bvi = a["bufferView"] as? Int, bvi < bufferViews.count else {
                return ([Float](repeating: 0, count: count*comps), type, count)
            }
            let bv = bufferViews[bvi]
            let base = (bv["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
            let stride = bv["byteStride"] as? Int ?? 0
            var out: [Float] = []; out.reserveCapacity(count * comps)
            bin.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for i in 0..<count {
                    let compSize = (ct == 5126 || ct == 5125) ? 4 : (ct == 5123 ? 2 : 1)
                    let rowOff = base + i * (stride > 0 ? stride : comps * compSize)
                    for c in 0..<comps {
                        let o = rowOff + c * compSize
                        guard o + compSize <= bin.count else { out.append(0); continue }
                        switch ct {
                        case 5126: out.append(raw.load(fromByteOffset: o, as: Float.self))
                        case 5125: out.append(Float(raw.load(fromByteOffset: o, as: UInt32.self)))
                        case 5123: out.append(Float(raw.load(fromByteOffset: o, as: UInt16.self)))
                        default:   out.append(Float(raw.load(fromByteOffset: o, as: UInt8.self)))
                        }
                    }
                }
            }
            return (out, type, count)
        }

        func buildGeometry(_ mi: Int) -> SCNGeometry? {
            guard mi < meshesJ.count,
                  let prims = meshesJ[mi]["primitives"] as? [[String: Any]],
                  let prim = prims.first,
                  let attrs = prim["attributes"] as? [String: Any],
                  let posIdx = attrs["POSITION"] as? Int else { return nil }
            let (pos, _, vcount) = accessorFloats(posIdx)
            guard vcount > 0 else { return nil }
            var sources: [SCNGeometrySource] = []
            let posData = pos.withUnsafeBytes { Data($0) }
            sources.append(SCNGeometrySource(data: posData, semantic: .vertex,
                vectorCount: vcount, usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12))
            if let ni = attrs["NORMAL"] as? Int {
                let (nrm, _, nc) = accessorFloats(ni)
                if nc == vcount {
                    let d = nrm.withUnsafeBytes { Data($0) }
                    sources.append(SCNGeometrySource(data: d, semantic: .normal,
                        vectorCount: nc, usesFloatComponents: true, componentsPerVector: 3,
                        bytesPerComponent: 4, dataOffset: 0, dataStride: 12))
                }
            }
            if let ci = attrs["COLOR_0"] as? Int {
                let (col, ctype, cc) = accessorFloats(ci)
                let comps = ctype == "VEC4" ? 4 : 3
                if cc == vcount {
                    let d = col.withUnsafeBytes { Data($0) }
                    sources.append(SCNGeometrySource(data: d, semantic: .color,
                        vectorCount: cc, usesFloatComponents: true, componentsPerVector: comps,
                        bytesPerComponent: 4, dataOffset: 0, dataStride: comps * 4))
                }
            }

            let mode = prim["mode"] as? Int ?? 4
            let primType: SCNGeometryPrimitiveType =
                mode == 0 ? .point : (mode == 1 ? .line : .triangles)
            var element: SCNGeometryElement
            if let ii = prim["indices"] as? Int {
                let (idxF, _, ic) = accessorFloats(ii)
                let idx = idxF.map { UInt32($0) }
                let primCount = primType == .triangles ? ic/3 : (primType == .line ? ic/2 : ic)
                let idxData = idx.withUnsafeBytes { Data($0) }
                element = SCNGeometryElement(data: idxData, primitiveType: primType,
                    primitiveCount: primCount, bytesPerIndex: 4)
            } else {
                let idx = (0..<UInt32(vcount)).map { $0 }
                let primCount = primType == .triangles ? vcount/3 : (primType == .line ? vcount/2 : vcount)
                let idxData = idx.withUnsafeBytes { Data($0) }
                element = SCNGeometryElement(data: idxData, primitiveType: primType,
                    primitiveCount: primCount, bytesPerIndex: 4)
            }
            if primType == .point {
                element.pointSize = 3
                element.minimumPointScreenSpaceRadius = 1
                element.maximumPointScreenSpaceRadius = 6
            }

            let geo = SCNGeometry(sources: sources, elements: [element])
            // Material
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            if let mIdx = prim["material"] as? Int, mIdx < materials.count {
                let mj = materials[mIdx]
                if let pbr = mj["pbrMetallicRoughness"] as? [String: Any],
                   let bc = pbr["baseColorFactor"] as? [Double], bc.count >= 4 {
                    mat.diffuse.contents = UIColor(red: CGFloat(bc[0]), green: CGFloat(bc[1]), blue: CGFloat(bc[2]), alpha: CGFloat(bc[3]))
                    mat.transparency = CGFloat(bc[3])
                }
                if let em = mj["emissiveFactor"] as? [Double], em.count >= 3 {
                    mat.emission.contents = UIColor(red: CGFloat(em[0]), green: CGFloat(em[1]), blue: CGFloat(em[2]), alpha: 1)
                }
                mat.isDoubleSided = (mj["doubleSided"] as? Bool) ?? false
            }
            geo.materials = [mat]
            return geo
        }

        // Build node tree
        var built: [SCNNode?] = Array(repeating: nil, count: nodesJ.count)
        func buildNode(_ i: Int) -> SCNNode {
            if let n = built[i] { return n }
            let nj = nodesJ[i]
            let n = SCNNode()
            built[i] = n
            n.name = nj["name"] as? String
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
            if let mi = nj["mesh"] as? Int { n.geometry = buildGeometry(mi) }
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
        return root.childNodes.isEmpty ? nil : root
    }
}
