import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcSceneOutliner — Nomad Sculpt-style scene panel for ArcLake.
//
// Lists all imported 3D assets and their named sub-components.
// Tap a component to select it (highlights in scene + opens material).
// Multi-select supported. Visibility toggle per component.
//
// Material editor: color picker, roughness, metalness, opacity,
// blend mode (Opaque/Subsurface/Blending/Additive), emission.
// Vertex shader preview spheres (clay + metallic).
//
// Also drives CFD component configuration when Fluid tab is active.
// ═══════════════════════════════════════════════════════════════════

// MARK: — Scene item model
struct ArcSceneItem: Identifiable {
    let id: UUID
    var name: String
    var displayName: String
    var vertexCount: Int
    var isVisible: Bool = true
    var isSelected: Bool = false
    var parentAsset: String    // the glb_import_ root name
    var node: SCNNode?         // weak reference via name lookup

    // Material state (live — applied directly to SCNMaterial)
    var color: Color = .white
    var roughness: Double = 0.5
    var metalness: Double = 0.0
    var opacity: Double = 1.0
    var emission: Color = .black
    var blendMode: ArcBlendMode = .opaque
}

// MARK: — Outliner ViewModel
@MainActor
final class ArcSceneOutlinerVM: ObservableObject {
    static let shared = ArcSceneOutlinerVM()

    @Published var assets:  [String: [ArcSceneItem]] = [:]  // parentAsset → items
    @Published var assetOrder: [String] = []
    @Published var selectedIds: Set<UUID> = []
    @Published var activeAsset: String? = nil

    func scan(_ scene: SCNScene) {
        var newAssets: [String: [ArcSceneItem]] = [:]
        var order: [String] = []
        var seenNames = Set<String>()

        scene.rootNode.enumerateChildNodes { node, _ in
            // Find import root nodes
            guard let nm = node.name else { return }
            if nm.hasPrefix("glb_import_") || nm.hasPrefix("imported_") {
                let displayAsset = nm.hasPrefix("glb_import_")
                    ? String(nm.dropFirst("glb_import_".count))
                    : String(nm.dropFirst("imported_".count))
                if newAssets[nm] == nil {
                    newAssets[nm] = []
                    order.append(nm)
                }
                // Enumerate children of this import root
                node.enumerateChildNodes { child, _ in
                    guard let childNm = child.name, child.geometry != nil,
                          !childNm.hasPrefix("arc_light_"), childNm != "arcFluidCloud",
                          !seenNames.contains(nm + ":" + childNm) else { return }
                    seenNames.insert(nm + ":" + childNm)
                    let vCount = child.geometry?.sources(for:.vertex).first?.vectorCount ?? 0
                    let mat = child.geometry?.firstMaterial
                    let baseColor = (mat?.diffuse.contents as? UIColor) ?? .white
                    var swColor = Color(baseColor)
                    // Keep existing selection/material state
                    let existing = self.assets[nm]?.first(where:{$0.name==childNm})
                    let item = ArcSceneItem(
                        id: existing?.id ?? UUID(),
                        name: childNm, displayName: childNm,
                        vertexCount: vCount, isVisible: !child.isHidden,
                        isSelected: existing?.isSelected ?? false,
                        parentAsset: nm, node: child,
                        color: existing?.color ?? swColor,
                        roughness: existing?.roughness ?? Double((mat?.roughness.contents as? CGFloat) ?? 0.5),
                        metalness: existing?.metalness ?? Double((mat?.metalness.contents as? CGFloat) ?? 0.0),
                        opacity:   existing?.opacity   ?? 1.0,
                        blendMode: existing?.blendMode ?? .opaque)
                    newAssets[nm, default: []].append(item)
                }
            }
        }
        assets = newAssets
        assetOrder = order
        if activeAsset == nil { activeAsset = order.first }
    }

    func select(_ id: UUID, multi: Bool = false) {
        if !multi { selectedIds.removeAll() }
        if selectedIds.contains(id) { selectedIds.remove(id) }
        else { selectedIds.insert(id) }
        // Update isSelected flags
        for asset in assets.keys {
            for i in 0..<(assets[asset]?.count ?? 0) {
                assets[asset]?[i].isSelected = selectedIds.contains(assets[asset]![i].id)
            }
        }
    }

    func toggleVisibility(_ id: UUID, in scene: SCNScene) {
        for asset in assets.keys {
            guard let idx = assets[asset]?.firstIndex(where:{$0.id==id}) else { continue }
            let nm = assets[asset]![idx].name
            assets[asset]?[idx].isVisible.toggle()
            let vis = assets[asset]![idx].isVisible
            scene.rootNode.enumerateChildNodes { node, _ in
                if node.name == nm { node.isHidden = !vis }
            }
        }
    }

    func applyMaterial(_ item: ArcSceneItem, to scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.name == item.name, let mat = node.geometry?.firstMaterial else { return }
            let uiColor = UIColor(item.color)
            mat.diffuse.contents = uiColor
            mat.roughness.contents = CGFloat(item.roughness)
            mat.metalness.contents = CGFloat(item.metalness)
            mat.transparency = item.opacity
            mat.lightingModel = item.metalness > 0.3 ? .physicallyBased : .physicallyBased
            mat.emission.contents = UIColor(item.emission)
            switch item.blendMode {
            case .opaque:     mat.transparencyMode = .default; mat.writesToDepthBuffer = true
            case .blending:   mat.transparencyMode = .default; mat.writesToDepthBuffer = false
            case .additive:   mat.transparencyMode = .default; mat.writesToDepthBuffer = false
            case .subsurface: mat.roughness.contents = CGFloat(item.roughness * 0.6)
            case .refraction: mat.transparencyMode = .default
            }
        }
    }

    func updateItem(_ id: UUID, _ mutate: (inout ArcSceneItem)->Void) {
        for asset in assets.keys {
            guard let idx = assets[asset]?.firstIndex(where:{$0.id==id}) else { continue }
            mutate(&assets[asset]![idx])
        }
    }
}

// MARK: — Main Outliner View
struct ArcSceneOutliner: View {
    @StateObject private var vm = ArcSceneOutlinerVM.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var editingItem: ArcSceneItem? = nil
    @State private var multiSelect = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text("SCENE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45)).tracking(2)
                Spacer()
                Button {
                    withAnimation { multiSelect.toggle() }
                } label: {
                    Image(systemName: multiSelect ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(multiSelect ? themeVM.accent : .white.opacity(0.4))
                }
                Button {
                    vm.scan(labVM.scene)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                        .foregroundColor(themeVM.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if vm.assetOrder.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent").font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No 3D models in scene")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.3))
                    Text("Use Imports → Add or restore a default")
                        .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.2))
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(vm.assetOrder, id: \.self) { assetKey in
                            assetSection(assetKey)
                        }
                        Spacer(minLength: 20)
                    }.padding(.horizontal, 8).padding(.top, 2)
                }
            }
        }
        .onAppear { vm.scan(labVM.scene) }
        .sheet(item: $editingItem) { item in
            ArcMaterialEditor(item: item) { updated in
                vm.updateItem(updated.id) { $0 = updated }
                vm.applyMaterial(updated, to: labVM.scene)
                editingItem = nil
            }
            .environmentObject(labVM)
            .environmentObject(themeVM)
        }
    }

    @ViewBuilder
    private func assetSection(_ assetKey: String) -> some View {
        let items = vm.assets[assetKey] ?? []
        let displayName = assetKey.hasPrefix("glb_import_")
            ? String(assetKey.dropFirst("glb_import_".count))
            : assetKey

        VStack(spacing: 0) {
            // Asset header
            HStack(spacing: 6) {
                Image(systemName: "cube.fill").font(.system(size: 10)).foregroundColor(themeVM.accent)
                Text(displayName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeVM.accent)
                Spacer()
                Text("\(items.count) objects")
                    .font(.system(size: 7, design: .monospaced)).foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(themeVM.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Component rows
            ForEach(items) { item in
                componentRow(item, assetKey: assetKey)
            }
        }
    }

    @ViewBuilder
    private func componentRow(_ item: ArcSceneItem, assetKey: String) -> some View {
        let isSelected = vm.selectedIds.contains(item.id)
        HStack(spacing: 8) {
            // Color swatch (material preview dot)
            Circle()
                .fill(item.color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))

            // Name + vertex count
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                    .lineLimit(1)
                Text("\(item.vertexCount.formatted()) verts")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(isSelected ? .black.opacity(0.6) : .white.opacity(0.3))
            }
            Spacer()

            // CFD role badge if wired
            if let role = ArcCombustionFlow.componentRoles[item.displayName] {
                Text(roleBadge(role))
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.8))
            }

            // Visibility toggle
            Button {
                vm.toggleVisibility(item.id, in: labVM.scene)
            } label: {
                Image(systemName: item.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .black.opacity(0.6) : .white.opacity(0.35))
            }

            // Material edit
            Button {
                editingItem = item
            } label: {
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .black.opacity(0.7) : themeVM.accent.opacity(0.7))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(isSelected ? themeVM.accent : Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            vm.select(item.id, multi: multiSelect)
            // Also set tappedCFDComponent for CFD config
            labVM.tappedCFDComponent = item.name
        }
    }

    private func roleBadge(_ role: ArcCombustionFlow.ComponentRole) -> String {
        switch role {
        case .combustionChamber:   return "CHAMBER"
        case .tank(let f):         return f.rawValue.uppercased()
        case .channel:             return "CHANNEL"
        case .pressureChamber:     return "PRESSURE"
        }
    }
}

// MARK: — Material Editor (Nomad-style)
struct ArcMaterialEditor: View {
    @State private var item: ArcSceneItem
    let onApply: (ArcSceneItem) -> Void
    @EnvironmentObject var themeVM: ArcThemeViewModel

    init(item: ArcSceneItem, onApply: @escaping (ArcSceneItem)->Void) {
        self._item = State(initialValue: item)
        self.onApply = onApply
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Preview spheres (like Nomad's two-sphere preview)
                    previewSpheres

                    // Blend mode
                    card("SURFACE TYPE") {
                        HStack(spacing: 4) {
                            ForEach(ArcBlendMode.allCases) { mode in
                                Button { item.blendMode = mode } label: {
                                    Text(mode.rawValue)
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(item.blendMode==mode ? .black : .white.opacity(0.55))
                                        .padding(.horizontal, 7).padding(.vertical, 5)
                                        .background(item.blendMode==mode ? themeVM.accent : Color.white.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Color picker
                    card("COLOR") {
                        VStack(spacing: 10) {
                            ColorPicker("Diffuse Color", selection: $item.color, supportsOpacity: false)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                            ColorPicker("Emission", selection: $item.emission, supportsOpacity: false)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    // PBR properties
                    card("MATERIAL PROPERTIES") {
                        VStack(spacing: 8) {
                            matSlider("Roughness",  val: $item.roughness,  color: .blue)
                            matSlider("Metalness",  val: $item.metalness,  color: .gray)
                            matSlider("Opacity",    val: $item.opacity,    color: .white)
                        }
                    }

                    // Quick presets
                    card("MATERIAL PRESETS") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            matPreset("Matte",      roughness:0.95, metalness:0.0,  color:.white)
                            matPreset("Glossy",     roughness:0.1,  metalness:0.0,  color:.white)
                            matPreset("Metal",      roughness:0.2,  metalness:1.0,  color:.init(red:0.8,green:0.8,blue:0.9))
                            matPreset("Gold",       roughness:0.15, metalness:1.0,  color:.init(red:1,green:0.84,blue:0.1))
                            matPreset("Carbon",     roughness:0.5,  metalness:0.3,  color:.init(red:0.15,green:0.15,blue:0.15))
                            matPreset("Ceramic",    roughness:0.3,  metalness:0.0,  color:.init(red:0.95,green:0.92,blue:0.88))
                        }
                    }

                    // Apply
                    Button { onApply(item) } label: {
                        Text("APPLY MATERIAL")
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                            .foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(themeVM.accent).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Spacer(minLength: 20)
                }
                .padding(12)
            }
            .background(Color(red:0.02,green:0.04,blue:0.09))
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    // Two preview spheres: clay + metallic, like Nomad
    private var previewSpheres: some View {
        HStack(spacing: 12) {
            Spacer()
            // Clay preview
            ZStack {
                let c = UIColor(item.color)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(c))
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(Double(1.0 - item.roughness) * 0.35))
                    )
                VStack { Spacer(); Text("clay").font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.5)) }
            }
            // Metallic preview
            ZStack {
                let c = UIColor(item.color)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(c))
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors:[.white.opacity(0.5),.clear], startPoint:.topLeading, endPoint:.bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(Double(item.roughness) * 0.3))
                    )
                VStack { Spacer(); Text("metal").font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.5)) }
            }
            Spacer()
        }
        .frame(height: 96)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func matSlider(_ label: String, val: Binding<Double>, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                .frame(width: 70, alignment: .leading)
            Slider(value: val, in: 0...1).tint(color)
            Text(String(format: "%.2f", val.wrappedValue))
                .font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.accent)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func matPreset(_ name: String, roughness: Double, metalness: Double, color: Color) -> some View {
        Button {
            item.roughness = roughness; item.metalness = metalness; item.color = color
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(color)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity((1.0 - roughness) * 0.4 + metalness * 0.2))
                        )
                        .frame(height: 36)
                }
                Text(name).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.65))
            }
        }
    }

    private func card<C:View>(_ title: String, @ViewBuilder content: ()->C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            content()
        }.padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
