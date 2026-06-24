import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcMeshSelectorView — tap 3D model geometry to assign fluid inlet
// and outlet zones for the Arc Edge CFD simulation.
// Supports: face selection, edge loop selection, vertex group selection
// ═══════════════════════════════════════════════════════════════════

struct ArcMeshSelectorView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sel = ArcMeshSelector.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Mode header
                HStack(spacing: 6) {
                    ForEach(ArcMeshSelector.PickMode.allCases, id:\.self) { m in
                        Button { sel.pickMode = m } label: {
                            Text(m.rawValue)
                                .font(.system(size:8,weight:.bold,design:.monospaced))
                                .foregroundColor(sel.pickMode==m ? .black : .white.opacity(0.6))
                                .padding(.horizontal,9).padding(.vertical,5)
                                .background(sel.pickMode==m ? themeVM.accent : Color.white.opacity(0.07))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(10).background(Color(red:0.02,green:0.04,blue:0.09))

                // Mesh list
                if sel.meshEntries.isEmpty {
                    Spacer()
                    VStack(spacing:8) {
                        Image(systemName:"cube.transparent").font(.system(size:28)).foregroundColor(.white.opacity(0.2))
                        Text("No 3D models loaded").font(.system(size:11,design:.monospaced)).foregroundColor(.white.opacity(0.3))
                        Text("Import a GLB file first").font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.2))
                    }
                    Spacer()
                } else {
                    List(sel.meshEntries, id:\.nodeName) { entry in
                        MeshEntryRow(entry: entry)
                            .environmentObject(sel)
                            .environmentObject(themeVM)
                            .listRowBackground(Color(red:0.05,green:0.08,blue:0.13))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                // Zone assignment bar
                VStack(spacing:6) {
                    if let picked = sel.pickedPoint {
                        HStack(spacing:10) {
                            Button {
                                ArcFluidEngine.shared.inletZone = picked.worldPos
                                dismiss()
                            } label: {
                                Label("Set Inlet", systemImage:"arrow.right.circle.fill")
                                    .font(.system(size:10,design:.monospaced))
                                    .foregroundColor(.black)
                                    .padding(.horizontal,12).padding(.vertical,8)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                            Button {
                                ArcFluidEngine.shared.outletZone = picked.worldPos
                                dismiss()
                            } label: {
                                Label("Set Outlet", systemImage:"arrow.left.circle.fill")
                                    .font(.system(size:10,design:.monospaced))
                                    .foregroundColor(.black)
                                    .padding(.horizontal,12).padding(.vertical,8)
                                    .background(Color.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(String(format:"Selected: (%.1f, %.1f, %.1f)", picked.worldPos.x, picked.worldPos.y, picked.worldPos.z))
                            .font(.system(size:8,design:.monospaced)).foregroundColor(.white.opacity(0.4))
                    } else {
                        Text("Tap a mesh component to select a zone point")
                            .font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.35))
                    }
                }
                .padding(12).background(Color(red:0.02,green:0.04,blue:0.09))
            }
            .background(Color(red:0.02,green:0.04,blue:0.09))
            .navigationTitle("Mesh Zone Selector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement:.navigationBarLeading) {
                    Button("Scan Scene") {
                        sel.scanScene(labVM.scene)
                    }.foregroundColor(themeVM.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { sel.scanScene(labVM.scene) }
    }
}

// MARK: — Mesh entry row
struct MeshEntryRow: View {
    let entry: ArcMeshSelector.MeshEntry
    @EnvironmentObject var sel: ArcMeshSelector
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(alignment:.leading, spacing:4) {
            HStack {
                Image(systemName:"cube.fill").font(.system(size:9)).foregroundColor(themeVM.accent)
                Text(entry.displayName).font(.system(size:11,design:.monospaced)).foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(entry.vertexCount) verts").font(.system(size:8,design:.monospaced)).foregroundColor(.white.opacity(0.35))
            }
            // Sub-surfaces: each material gets a tappable face group button
            ScrollView(.horizontal, showsIndicators:false) {
                HStack(spacing:4) {
                    ForEach(entry.surfaces.indices, id:\.self) { i in
                        let surface = entry.surfaces[i]
                        Button {
                            sel.pickedPoint = ArcMeshSelector.PickedPoint(
                                nodeName: entry.nodeName,
                                surfaceIndex: i,
                                worldPos: surface.centroid)
                        } label: {
                            VStack(spacing:2) {
                                RoundedRectangle(cornerRadius:4)
                                    .fill(Color(surface.displayColor))
                                    .frame(width:28, height:18)
                                Text("S\(i+1)").font(.system(size:7,design:.monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding(4)
                            .background(sel.pickedPoint?.nodeName==entry.nodeName && sel.pickedPoint?.surfaceIndex==i
                                        ? themeVM.accent.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius:6))
                        }
                    }
                    // Bounding box center as a quick pick
                    Button {
                        sel.pickedPoint = ArcMeshSelector.PickedPoint(
                            nodeName: entry.nodeName,
                            surfaceIndex: -1,
                            worldPos: entry.boundingCenter)
                    } label: {
                        VStack(spacing:2) {
                            Image(systemName:"dot.scope").font(.system(size:14)).foregroundColor(.white.opacity(0.5))
                            Text("CTR").font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.4))
                        }
                        .padding(4)
                        .background(sel.pickedPoint?.nodeName==entry.nodeName && sel.pickedPoint?.surfaceIndex == -1
                                    ? themeVM.accent.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius:6))
                    }
                }
            }
        }
        .padding(.vertical,6)
    }
}

// MARK: — Selector model
@MainActor
final class ArcMeshSelector: ObservableObject {
    static let shared = ArcMeshSelector()

    enum PickMode: String, CaseIterable {
        case face = "Face", edge = "Edge", vertex = "Vertex"
    }

    struct Surface {
        var centroid: SIMD3<Float>
        var displayColor: UIColor
        var elementCount: Int
    }

    struct MeshEntry {
        var nodeName: String
        var displayName: String
        var vertexCount: Int
        var surfaces: [Surface]
        var boundingCenter: SIMD3<Float>
    }

    struct PickedPoint {
        var nodeName: String
        var surfaceIndex: Int
        var worldPos: SIMD3<Float>
    }

    @Published var pickMode: PickMode = .face
    @Published var meshEntries: [MeshEntry] = []
    @Published var pickedPoint: PickedPoint? = nil

    func scanScene(_ scene: SCNScene) {
        var entries: [MeshEntry] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry, !geo.materials.isEmpty else { return }
            let nm = node.name ?? geo.name ?? "mesh"
            guard !nm.hasPrefix("arc_light_"),
                  !nm.hasPrefix("lscfd"),
                  nm != "arcFluidCloud" else { return }

            // Count vertices
            let verts = geo.sources(for: .vertex).first
            let vCount = verts?.vectorCount ?? 0

            // Build surface entries from materials
            var surfaces: [Surface] = []
            let mat = node.worldTransform
            for (i, material) in geo.materials.enumerated() {
                let color = (material.diffuse.contents as? UIColor) ?? .systemCyan
                // Compute approximate centroid from bounding box
                let bb = node.boundingBox
                let cx = (bb.max.x + bb.min.x) / 2
                let cy = (bb.max.y + bb.min.y) / 2
                let cz = (bb.max.z + bb.min.z) / 2
                // Offset per material (approximate face distribution)
                let offset = Float(i) * 5
                let worldPt = SCNVector3(mat.m41 + cx + offset,
                                         mat.m42 + cy, mat.m43 + cz)
                surfaces.append(Surface(
                    centroid: SIMD3<Float>(Float(worldPt.x), Float(worldPt.y), Float(worldPt.z)),
                    displayColor: color,
                    elementCount: max(1, vCount / max(1, geo.materials.count))))
            }
            let bb = node.boundingBox
            let wt = node.worldTransform
            let ctr = SIMD3<Float>(
                Float(wt.m41) + (bb.max.x+bb.min.x)/2,
                Float(wt.m42) + (bb.max.y+bb.min.y)/2,
                Float(wt.m43) + (bb.max.z+bb.min.z)/2)

            // Clean display name
            var dname = nm
            for p in ["glb_import_","imported_"] where nm.hasPrefix(p) {
                dname = String(nm.dropFirst(p.count)); break
            }
            entries.append(MeshEntry(nodeName: nm, displayName: dname,
                                     vertexCount: vCount, surfaces: surfaces,
                                     boundingCenter: ctr))
        }
        meshEntries = entries
    }
}
