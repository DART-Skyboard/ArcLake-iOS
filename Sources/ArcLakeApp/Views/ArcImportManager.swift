import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcImportManager — per-tab imported asset list with swipe-to-clear,
// gizmo translate/rotate/scale, and cross-tab visibility for Mantis.
// ═══════════════════════════════════════════════════════════════════

struct ArcImportManagerView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showFilePicker = false

    // Per-tab: (tabIndex, nodeName)
    private var tabsWithAssets: [(Int, String, [String])] {
        var result: [(Int, String, [String])] = []
        let nodes = labVM.scene.rootNode.childNodes
        for (i, name) in labVM.sceneTabs_data.enumerated() {
            let assets = nodes.compactMap { n -> String? in
                guard let nm = n.name,
                      nm.hasPrefix("imported_") || nm.hasPrefix("glb_import_"),
                      !n.isHidden else { return nil }
                // Assets are in the shared scene; group them all under the tab
                // they were imported during (tracked by "arc_tab_\(i)" child marker).
                if n.childNode(withName: "arc_tab_\(i)", recursively: false) != nil {
                    return nm
                }
                return nil
            }
            if !assets.isEmpty { result.append((i, name, assets)) }
        }
        // Fall-through: list ALL imports under the active tab if no tab markers
        if result.isEmpty {
            let all = nodes.compactMap { n -> String? in
                guard let nm = n.name,
                      nm.hasPrefix("imported_") || nm.hasPrefix("glb_import_") else { return nil }
                return nm
            }
            if !all.isEmpty {
                result.append((labVM.activeTabIndex,
                               (labVM.activeTabIndex < labVM.sceneTabs_data.count
                    ? labVM.sceneTabs_data[labVM.activeTabIndex] : "Scene"),
                               all))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11)).foregroundColor(themeVM.accent)
                Text("IMPORTS")
                    .font(.custom("Orbitron-Bold", size: 11))
                    .foregroundColor(themeVM.accent).tracking(2)
                Spacer()
                Button {
                    showFilePicker = true
                } label: {
                    Label("Import", systemImage: "plus")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(themeVM.accent).clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white.opacity(0.04))

            if tabsWithAssets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cube").font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.2))
                    Text("No imported assets")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Import GLB or USDZ files from the button above")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(32)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(tabsWithAssets, id: \.0) { tabIdx, tabName, assets in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(tabIdx == labVM.activeTabIndex
                                              ? themeVM.accent : Color.white.opacity(0.35))
                                        .frame(width: 6, height: 6)
                                    Text(tabName.uppercased())
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.45)).tracking(1.5)
                                }
                                ForEach(assets, id: \.self) { nodeName in
                                    assetRow(nodeName: nodeName)
                                }
                            }
                        }
                    }.padding(12)
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.init(filenameExtension: "glb") ?? .data,
                                  .init(filenameExtension: "gltf") ?? .data,
                                  .init(filenameExtension: "usdz") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            Task {
                if let node = ArcGLBImporter().importGLB(url: url) {
                    await MainActor.run {
                        // Stamp with current tab marker
                        let marker = SCNNode(); marker.name = "arc_tab_\(labVM.activeTabIndex)"
                        node.addChildNode(marker)
                        labVM.importAssetNode(node)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func assetRow(nodeName: String) -> some View {
        let displayName: String = {
            var s = nodeName
            for p in ["glb_import_", "imported_"] where s.hasPrefix(p) { s = String(s.dropFirst(p.count)) }
            return s
        }()
        HStack(spacing: 8) {
            Image(systemName: "cube.fill")
                .font(.system(size: 10)).foregroundColor(themeVM.accent.opacity(0.8))
            Text(displayName)
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
            Spacer()
            // Gizmo select — tap to show the translate gizmo
            Button {
                if labVM.selectedImportedNode == nodeName {
                    labVM.selectedImportedNode = nil
                } else {
                    labVM.selectedImportedNode = nodeName
                }
            } label: {
                Image(systemName: "move.3d")
                    .font(.system(size: 12))
                    .foregroundColor(labVM.selectedImportedNode == nodeName
                                    ? themeVM.accent : .white.opacity(0.4))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(labVM.selectedImportedNode == nodeName
                    ? themeVM.accent.opacity(0.5) : Color.clear, lineWidth: 1))
        // Swipe left to clear from scene
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                labVM.scene.rootNode.childNode(withName: nodeName, recursively: false)?
                    .removeFromParentNode()
                if labVM.selectedImportedNode == nodeName { labVM.selectedImportedNode = nil }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

// MARK: — Translate Gizmo Overlay
// When the user selects an imported node, a 3-axis gizmo appears over the viewport.
struct ArcGizmoOverlay: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        guard let name = labVM.selectedImportedNode,
              let node = labVM.scene.rootNode.childNode(withName: name, recursively: false)
        else { return AnyView(EmptyView()) }
        return AnyView(
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    Spacer()
                    gizmoPad(node: node)
                        .padding(.trailing, 12)
                        .padding(.bottom, 120)
                }
            }
        )
    }

    @ViewBuilder
    private func gizmoPad(node: SCNNode) -> some View {
        VStack(spacing: 4) {
            Text("GIZMO").font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            // Translate arrows
            HStack(spacing: 4) {
                axisButton("X", color: Color.red)  { node.simdPosition.x += 0.5 }
                axisButton("-X", color: Color.red) { node.simdPosition.x -= 0.5 }
            }
            HStack(spacing: 4) {
                axisButton("Y↑", color: Color.green) { node.simdPosition.y += 0.5 }
                axisButton("Y↓", color: Color.green) { node.simdPosition.y -= 0.5 }
            }
            HStack(spacing: 4) {
                axisButton("Z", color: Color.blue)  { node.simdPosition.z += 0.5 }
                axisButton("-Z", color: Color.blue) { node.simdPosition.z -= 0.5 }
            }
            Divider().background(Color.white.opacity(0.12))
            // Scale uniform
            HStack(spacing: 4) {
                axisButton("+S", color: themeVM.accent) {
                    let s = node.scale; node.scale = SCNVector3(s.x*1.1, s.y*1.1, s.z*1.1)
                }
                axisButton("-S", color: themeVM.accent) {
                    let s = node.scale; node.scale = SCNVector3(s.x*0.9, s.y*0.9, s.z*0.9)
                }
            }
            // Deselect
            Button {
                labVM.selectedImportedNode = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 26, height: 18)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(8)
        .background(Color(red:0.03, green:0.06, blue:0.12).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(themeVM.accent.opacity(0.3), lineWidth: 0.8))
    }

    private func axisButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 28, height: 22)
                .background(color.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
