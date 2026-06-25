import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcGimbalOverlay — Nomad-style camera gimbal + view controls HUD.
//
// Positioned upper-right over the 3D viewport.
// Semi-transparent dark glass material so scene content shows through.
//
// Contains:
//   • 3D gimbal orb with Front/Back/Left/Right/Top/Bottom tap zones
//   • Ortho/Perspective toggle pill
//   • Camera list quick-access strip (tap to jump to saved camera)
//   • Add camera / Update active camera buttons
// ═══════════════════════════════════════════════════════════════════

struct ArcGimbalOverlay: View {
    @StateObject private var camMgr = ArcCameraManager.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showCameraPanel = false
    @State private var addingCamera    = false
    @State private var newCamName      = ""

    // Reference to the scnView — passed in from ArcSceneViewRepresentable
    var scnView: SCNView? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // ── Gimbal orb ──────────────────────────────────────────
            gimbalOrb
                .onTapGesture { showCameraPanel.toggle() }

            // ── Ortho / Perspective toggle ─────────────────────────
            Button {
                camMgr.toggleOrtho(scene: labVM.scene, scnView: scnView)
            } label: {
                Text(camMgr.isOrtho ? "ORTHO" : "PERSP")
                    .font(.system(size:8,weight:.bold,design:.monospaced))
                    .foregroundColor(camMgr.isOrtho ? .blue : .white.opacity(0.7))
                    .padding(.horizontal,8).padding(.vertical,4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(
                        camMgr.isOrtho ? Color.blue.opacity(0.6) : Color.white.opacity(0.15),
                        lineWidth:0.8))
            }

            // ── Quick view buttons (horizontal row) ────────────────
            HStack(spacing:3) {
                ForEach(GimbalPreset.allCases) { preset in
                    Button {
                        camMgr.snapToView(preset)
                    } label: {
                        Text(preset.rawValue)
                            .font(.system(size:7,weight:.bold,design:.monospaced))
                            .foregroundColor(preset.color)
                            .frame(width:22,height:20)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius:4))
                            .overlay(RoundedRectangle(cornerRadius:4)
                                .stroke(preset.color.opacity(0.3),lineWidth:0.5))
                    }
                }
            }

            // ── Saved camera strip ─────────────────────────────────
            if !camMgr.cameras.isEmpty {
                ScrollView(.horizontal, showsIndicators:false) {
                    HStack(spacing:4) {
                        ForEach(camMgr.cameras) { cam in
                            Button { camMgr.activateCamera(cam.id) } label: {
                                Text(cam.name)
                                    .font(.system(size:7,weight:.bold,design:.monospaced))
                                    .foregroundColor(camMgr.activeCameraId==cam.id
                                        ? .black : .white.opacity(0.65))
                                    .lineLimit(1)
                                    .padding(.horizontal,7).padding(.vertical,4)
                                    .background(camMgr.activeCameraId==cam.id
                                        ? themeVM.accent : Color.white.opacity(0.08))
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                        }
                    }.padding(.horizontal,2)
                }
                .frame(maxWidth:130)
            }
        }
        .padding(8)
        // Camera panel sheet
        .sheet(isPresented: $showCameraPanel) {
            ArcCameraPanel()
                .environmentObject(labVM)
                .environmentObject(themeVM)
        }
    }

    // MARK: — Gimbal orb
    // A simplified hemisphere-style gimbal showing the 6 face labels.
    // Semi-transparent colored sectors, tappable quadrants.
    private var gimbalOrb: some View {
        ZStack {
            // Background disc
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width:72, height:72)
                .overlay(Circle().stroke(Color.white.opacity(0.12),lineWidth:0.8))
                .shadow(color:.black.opacity(0.4),radius:6,x:0,y:3)

            // Grid lines
            Rectangle().fill(Color.white.opacity(0.1)).frame(width:72,height:0.5)
            Rectangle().fill(Color.white.opacity(0.1)).frame(width:0.5,height:72)
            Rectangle().fill(Color.white.opacity(0.07)).frame(width:72,height:0.5)
                .rotationEffect(.degrees(45))
            Rectangle().fill(Color.white.opacity(0.07)).frame(width:72,height:0.5)
                .rotationEffect(.degrees(-45))

            // Face labels — arranged like a net of a cube projected onto circle
            // Top
            gimbalFaceBtn(.top, offset: CGSize(width:0, height:-20))
            // Bottom
            gimbalFaceBtn(.bottom, offset: CGSize(width:0, height:20))
            // Front
            gimbalFaceBtn(.front, offset: CGSize(width:-20, height:6))
            // Back
            gimbalFaceBtn(.back, offset: CGSize(width:20, height:-6))
            // Left
            gimbalFaceBtn(.left, offset: CGSize(width:-20, height:-8))
            // Right
            gimbalFaceBtn(.right, offset: CGSize(width:20, height:8))

            // Center dot (tap to open panel)
            Circle().fill(themeVM.accent.opacity(0.8)).frame(width:7,height:7)
        }
        .frame(width:72,height:72)
    }

    private func gimbalFaceBtn(_ preset: GimbalPreset, offset: CGSize) -> some View {
        Button { camMgr.snapToView(preset) } label: {
            Text(preset.rawValue)
                .font(.system(size:8,weight:.heavy,design:.monospaced))
                .foregroundColor(preset.color)
                .shadow(color:preset.color.opacity(0.8),radius:3,x:0,y:0)
        }
        .offset(offset)
    }
}

// MARK: — Camera panel sheet
struct ArcCameraPanel: View {
    @StateObject private var camMgr = ArcCameraManager.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newCamName = ""
    @State private var editingId: UUID? = nil
    @State private var editName  = ""

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators:false) {
                VStack(spacing:10) {
                    // Add camera
                    addCameraCard

                    // FOV slider (affects active camera preview)
                    card("FIELD OF VIEW") {
                        HStack {
                            Text("FOV").font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.6))
                            Slider(value: $camMgr.fov, in:10...120).tint(themeVM.accent)
                                .onChange(of:camMgr.fov) { v in
                                    // Live update camera FOV
                                }
                            Text(String(format:"%.0f°",camMgr.fov))
                                .font(.system(size:9,design:.monospaced)).foregroundColor(themeVM.accent)
                                .frame(width:32)
                        }
                        // Ortho toggle
                        HStack {
                            Text("Projection").font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.6))
                            Spacer()
                            HStack(spacing:4) {
                                modeBtn("Perspective", isActive: !camMgr.isOrtho) { camMgr.isOrtho = false }
                                modeBtn("Orthographic", isActive: camMgr.isOrtho)  { camMgr.isOrtho = true  }
                            }
                        }
                    }

                    // Saved cameras list
                    if !camMgr.cameras.isEmpty {
                        card("SAVED CAMERAS") {
                            VStack(spacing:6) {
                                ForEach(camMgr.cameras) { cam in
                                    cameraRow(cam)
                                }
                            }
                        }
                    }

                    // Standard views quick jump
                    card("STANDARD VIEWS") {
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),spacing:6) {
                            ForEach(GimbalPreset.allCases) { preset in
                                Button { camMgr.snapToView(preset); dismiss() } label: {
                                    VStack(spacing:3) {
                                        Text(preset.rawValue).font(.system(size:16,weight:.heavy))
                                            .foregroundColor(preset.color)
                                        Text(preset.fullName).font(.system(size:7,design:.monospaced))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    .frame(maxWidth:.infinity).padding(.vertical,10)
                                    .background(preset.color.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius:8))
                                }
                            }
                        }
                    }

                    Spacer(minLength:20)
                }
                .padding(12)
            }
            .background(Color(red:0.02,green:0.04,blue:0.09))
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.navigationBarTrailing) { Button("Done"){dismiss()} } }
        }
        .preferredColorScheme(.dark)
        .onAppear { camMgr.load() }
    }

    private var addCameraCard: some View {
        card("ADD CAMERA") {
            VStack(spacing:8) {
                HStack(spacing:8) {
                    TextField("Camera name…", text:$newCamName)
                        .font(.system(size:11,design:.monospaced))
                        .foregroundColor(.white)
                        .padding(8).background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius:8))
                    Button {
                        camMgr.addCamera(name:newCamName.isEmpty ? nil : newCamName)
                        newCamName = ""
                    } label: {
                        Image(systemName:"plus.circle.fill").font(.system(size:22))
                            .foregroundColor(themeVM.accent)
                    }
                }
                Text("Saves current viewport position and orientation")
                    .font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.3))
            }
        }
    }

    @ViewBuilder
    private func cameraRow(_ cam: ArcCamera) -> some View {
        let isActive = camMgr.activeCameraId == cam.id
        HStack(spacing:8) {
            // Active indicator
            Circle().fill(isActive ? themeVM.accent : Color.white.opacity(0.2))
                .frame(width:7,height:7)

            // Name (tap to rename)
            if editingId == cam.id {
                TextField("Name", text:$editName,
                          onCommit:{ camMgr.renameCamera(cam.id, name:editName); editingId=nil })
                    .font(.system(size:11,design:.monospaced)).foregroundColor(.white)
                    .padding(4).background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius:6))
            } else {
                Text(cam.name).font(.system(size:11,design:.monospaced))
                    .foregroundColor(isActive ? themeVM.accent : .white.opacity(0.8))
                    .onTapGesture { editingId=cam.id; editName=cam.name }
            }

            Spacer()

            // Ortho badge
            if cam.isOrtho {
                Text("ORTHO").font(.system(size:6,weight:.bold,design:.monospaced))
                    .foregroundColor(.blue).padding(.horizontal,4).padding(.vertical,2)
                    .background(Color.blue.opacity(0.12)).clipShape(Capsule())
            }

            // Update button
            Button {
                camMgr.updateCamera(cam.id)
            } label: {
                Image(systemName:"arrow.clockwise")
                    .font(.system(size:12)).foregroundColor(.orange)
            }

            // Jump to camera
            Button {
                camMgr.activateCamera(cam.id); dismiss()
            } label: {
                Image(systemName:"video.fill")
                    .font(.system(size:12)).foregroundColor(themeVM.accent)
            }

            // Delete
            Button {
                camMgr.deleteCamera(cam.id)
            } label: {
                Image(systemName:"trash").font(.system(size:11)).foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.vertical,6).padding(.horizontal,10)
        .background(isActive ? themeVM.accent.opacity(0.08) : Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius:8))
    }

    private func modeBtn(_ label:String, isActive:Bool, action:@escaping()->Void) -> some View {
        Button(action:action) {
            Text(label).font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(isActive ? .black : .white.opacity(0.5))
                .padding(.horizontal,8).padding(.vertical,4)
                .background(isActive ? themeVM.accent : Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    private func card<C:View>(_ title:String, @ViewBuilder content:()->C) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            content()
        }.padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:12))
    }
}
