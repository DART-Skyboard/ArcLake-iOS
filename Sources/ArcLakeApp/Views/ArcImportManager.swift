import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcImportManager — asset list in a proper List so swipe-to-delete
// works natively (ScrollView doesn't support .swipeActions).
// ═══════════════════════════════════════════════════════════════════

struct ArcImportManagerView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showFilePicker = false
    @State private var refreshID = UUID()   // force list refresh after delete

    private var selNode: String? { labVM.selectedImportedNode }

    private func importedNames() -> [String] {
        labVM.scene.rootNode.childNodes.compactMap { n in
            guard let nm = n.name,
                  nm.hasPrefix("imported_") || nm.hasPrefix("glb_import_"),
                  !n.isHidden else { return nil }
            return nm
        }
    }
    private func displayName(_ raw: String) -> String {
        for p in ["glb_import_", "imported_"] where raw.hasPrefix(p) {
            return String(raw.dropFirst(p.count))
        }
        return raw
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11)).foregroundColor(themeVM.accent)
                Text("IMPORTS")
                    .font(.custom("Orbitron-Bold", size: 11))
                    .foregroundColor(themeVM.accent).tracking(2)
                Spacer()
                Button { showFilePicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text("Add").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(themeVM.accent).clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white.opacity(0.04))

            let assets = importedNames()
            if assets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cube").font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.2))
                    Text("No imported assets")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Tap Add to import a GLB or USDZ file")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(32)
            } else {
                // ── List — required for .swipeActions to work ───────
                List {
                    Section {
                        ForEach(assets, id: \.self) { nm in
                            assetRow(nm)
                                .listRowBackground(Color(red: 0.06, green: 0.09, blue: 0.14))
                                .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                        }
                    } header: {
                        HStack(spacing: 5) {
                            Circle().fill(themeVM.accent).frame(width: 6, height: 6)
                            Text("SCENE")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.45)).tracking(1.5)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .id(refreshID)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                .init(filenameExtension: "glb") ?? .data,
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
                        labVM.importAssetNode(node)
                        refreshID = UUID()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func assetRow(_ nodeName: String) -> some View {
        let isSelected = selNode == nodeName
        HStack(spacing: 8) {
            Image(systemName: "cube.fill")
                .font(.system(size: 10)).foregroundColor(themeVM.accent.opacity(0.8))
            Text(displayName(nodeName))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.9)).lineLimit(1)
            Spacer()
            // Gizmo selector — 4-arrow move icon
            Button {
                labVM.selectedImportedNode = isSelected ? nil : nodeName
            } label: {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? themeVM.accent : .white.opacity(0.35))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        // ── Swipe left → Remove from scene ──────────────────────────
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                labVM.scene.rootNode.childNode(withName: nodeName, recursively: false)?
                    .removeFromParentNode()
                if labVM.selectedImportedNode == nodeName {
                    labVM.selectedImportedNode = nil
                }
                refreshID = UUID()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

// MARK: — Gizmo Overlay
struct ArcGizmoOverlay: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    private var selNode: String? { labVM.selectedImportedNode }

    var body: some View {
        if let name = selNode,
           let node = labVM.scene.rootNode.childNode(withName: name, recursively: false) {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    gizmoPad(node: node)
                        .padding(.trailing, 12).padding(.bottom, 120)
                }
            }
        }
    }

    @ViewBuilder
    private func gizmoPad(node: SCNNode) -> some View {
        VStack(spacing: 4) {
            Text("MOVE")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            HStack(spacing: 4) {
                axisBtn("+X", .red)   { node.simdPosition.x += 0.5 }
                axisBtn("−X", .red)   { node.simdPosition.x -= 0.5 }
            }
            HStack(spacing: 4) {
                axisBtn("Y↑", .green) { node.simdPosition.y += 0.5 }
                axisBtn("Y↓", .green) { node.simdPosition.y -= 0.5 }
            }
            HStack(spacing: 4) {
                axisBtn("+Z", .blue)  { node.simdPosition.z += 0.5 }
                axisBtn("−Z", .blue)  { node.simdPosition.z -= 0.5 }
            }
            Divider().background(Color.white.opacity(0.12))
            HStack(spacing: 4) {
                axisBtn("+S", themeVM.accent) {
                    let s = node.scale
                    node.scale = SCNVector3(s.x * 1.1, s.y * 1.1, s.z * 1.1)
                }
                axisBtn("−S", themeVM.accent) {
                    let s = node.scale
                    node.scale = SCNVector3(s.x * 0.9, s.y * 0.9, s.z * 0.9)
                }
            }
            Button { labVM.selectedImportedNode = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 60, height: 18)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(8)
        .background(Color(red: 0.03, green: 0.06, blue: 0.12).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(themeVM.accent.opacity(0.3), lineWidth: 0.8))
    }

    private func axisBtn(_ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
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
