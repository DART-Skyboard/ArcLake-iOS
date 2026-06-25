import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcGimbalOverlay — Single clean camera controls HUD (top-right).
//
// Layout (top to bottom, right-aligned):
//   1. Orientation cube — drag or tap faces/edges to orbit.
//      Faces: Front(green) Back Left Right Top Bottom.
//      Tap a face → snap to that orthographic view.
//      Tap an edge → rotate 45° toward adjacent face.
//      Drag on cube → real-time orbit.
//   2. Two icon buttons below cube:
//      ↺  Reset — returns to default viewport (not any saved camera)
//      📷 Camera — opens camera save/restore panel
// ═══════════════════════════════════════════════════════════════════

struct ArcGimbalOverlay: View {
    @StateObject private var camMgr = ArcCameraManager.shared
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showCameraPanel = false
    @State private var dragStart: CGPoint = .zero
    @State private var isDraggingCube = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // ── Orientation cube ───────────────────────────────────
            orientationCube
                .frame(width: 76, height: 76)

            // ── Two control buttons ────────────────────────────────
            HStack(spacing: 6) {
                // Reset to default view
                controlBtn(icon: "arrow.counterclockwise", color: .white.opacity(0.7)) {
                    camMgr.resetToDefault()
                }
                // Camera panel
                controlBtn(icon: "camera", color: themeVM.accent) {
                    showCameraPanel = true
                }
            }
        }
        .sheet(isPresented: $showCameraPanel) {
            ArcCameraPanel().environmentObject(themeVM)
        }
    }

    // MARK: — Orientation cube
    // A minimal 3D-like cube projection with tappable face areas
    // and draggable rotation (passes deltas to camera manager)
    private var orientationCube: some View {
        ZStack {
            // Outer ring — drag handle
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 76, height: 76)
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.8))

            // Cube faces — projected isometric-style layout
            // Each quadrant represents a face; edges are between them
            cubeFace(.top,    x:  0,  y: -23, w: 32, h: 18)
            cubeFace(.front,  x: -19, y:  2,  w: 28, h: 22)
            cubeFace(.right,  x:  19, y:  2,  w: 28, h: 22)
            cubeFace(.bottom, x:  0,  y:  22, w: 32, h: 16)
            cubeFace(.left,   x: -19, y: -12, w: 20, h: 16)
            cubeFace(.back,   x:  19, y: -12, w: 20, h: 16)

            // Center world-origin dot
            Circle().fill(Color.white.opacity(0.6)).frame(width: 5, height: 5)
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { val in
                    if !isDraggingCube {
                        isDraggingCube = true
                        dragStart = val.location
                        camMgr.beginCubeDrag()
                    }
                    let dx = Float(val.location.x - dragStart.x)
                    let dy = Float(val.location.y - dragStart.y)
                    dragStart = val.location
                    camMgr.dragCube(dx: dx, dy: dy)
                }
                .onEnded { _ in isDraggingCube = false; camMgr.endCubeDrag() }
        )
    }

    @ViewBuilder
    private func cubeFace(_ preset: GimbalPreset, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Button {
            camMgr.snapToView(preset)
        } label: {
            Text(preset.rawValue)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(preset.color)
                .shadow(color: preset.color.opacity(0.9), radius: 4)
                .frame(width: w, height: h)
                .background(preset.color.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .offset(x: x, y: y)
    }

    private func controlBtn(icon: String, color: Color, action: @escaping ()->Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 32, height: 28)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.7))
        }
    }
}

// MARK: — Camera panel sheet
struct ArcCameraPanel: View {
    @StateObject private var camMgr = ArcCameraManager.shared
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newCamName = ""
    @State private var editingId: UUID? = nil
    @State private var editName   = ""

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    // Projection mode
                    card("PROJECTION") {
                        HStack(spacing: 6) {
                            modeBtn("Perspective", icon:"perspective",  isActive: !camMgr.isOrtho) { camMgr.isOrtho = false }
                            modeBtn("Orthographic", icon:"squareshape", isActive:  camMgr.isOrtho) { camMgr.isOrtho = true  }
                        }
                        HStack {
                            Text("FOV").font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.5))
                                .frame(width:28)
                            Slider(value: $camMgr.fov, in: 10...120).tint(themeVM.accent)
                            Text(String(format:"%.0f°", camMgr.fov))
                                .font(.system(size:9,design:.monospaced)).foregroundColor(themeVM.accent)
                                .frame(width:34, alignment:.trailing)
                        }
                        // Keyboard shortcuts note
                        Text("Keyboard: O = ortho/persp  ·  Numpad 1/3/7 = front/right/top  ·  Numpad 0 = saved cam")
                            .font(.system(size:6,design:.monospaced)).foregroundColor(.white.opacity(0.25))
                            .multilineTextAlignment(.center)
                    }

                    // Standard views
                    card("STANDARD VIEWS") {
                        LazyVGrid(columns: Array(repeating:GridItem(.flexible()),count:3), spacing:6) {
                            ForEach(GimbalPreset.allCases) { p in
                                Button { camMgr.snapToView(p); dismiss() } label: {
                                    VStack(spacing:2) {
                                        Text(p.rawValue).font(.system(size:14,weight:.heavy)).foregroundColor(p.color)
                                        Text(p.fullName).font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.4))
                                    }
                                    .frame(maxWidth:.infinity).padding(.vertical,8)
                                    .background(p.color.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius:8))
                                }
                            }
                        }
                    }

                    // Add camera
                    card("SAVE CAMERA") {
                        HStack(spacing:8) {
                            TextField("Camera name…", text:$newCamName)
                                .font(.system(size:11,design:.monospaced)).foregroundColor(.white)
                                .padding(8).background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius:8))
                            Button {
                                camMgr.addCamera(name: newCamName.isEmpty ? nil : newCamName)
                                newCamName = ""
                            } label: {
                                Image(systemName:"plus.circle.fill").font(.system(size:24)).foregroundColor(themeVM.accent)
                            }
                        }
                        Text("Saves current position, orientation, FOV and projection")
                            .font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.3))
                    }

                    // Saved cameras
                    if !camMgr.cameras.isEmpty {
                        card("SAVED CAMERAS") {
                            VStack(spacing:5) {
                                ForEach(camMgr.cameras) { cam in cameraRow(cam) }
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

    @ViewBuilder
    private func cameraRow(_ cam: ArcCamera) -> some View {
        let isActive = camMgr.activeCameraId == cam.id
        HStack(spacing:8) {
            Circle().fill(isActive ? themeVM.accent : .white.opacity(0.2)).frame(width:6,height:6)
            if editingId == cam.id {
                TextField("Name", text:$editName, onCommit:{
                    camMgr.renameCamera(cam.id, name:editName); editingId=nil })
                    .font(.system(size:11,design:.monospaced)).foregroundColor(.white)
                    .padding(4).background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:6))
            } else {
                Text(cam.name)
                    .font(.system(size:11,design:.monospaced))
                    .foregroundColor(isActive ? themeVM.accent : .white.opacity(0.8))
                    .onTapGesture { editingId=cam.id; editName=cam.name }
            }
            Spacer()
            if cam.isOrtho { Text("ORTHO").font(.system(size:6,weight:.bold,design:.monospaced))
                .foregroundColor(.blue).padding(.horizontal,4).padding(.vertical,2)
                .background(Color.blue.opacity(0.12)).clipShape(Capsule()) }
            Button { camMgr.updateCamera(cam.id) } label: {
                Image(systemName:"arrow.clockwise").font(.system(size:12)).foregroundColor(.orange) }
            Button { camMgr.activateCamera(cam.id); dismiss() } label: {
                Image(systemName:"video.fill").font(.system(size:12)).foregroundColor(themeVM.accent) }
            Button { camMgr.deleteCamera(cam.id) } label: {
                Image(systemName:"trash").font(.system(size:11)).foregroundColor(.red.opacity(0.7)) }
        }
        .padding(.vertical,6).padding(.horizontal,10)
        .background(isActive ? themeVM.accent.opacity(0.08) : Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius:8))
    }

    private func modeBtn(_ label:String, icon:String, isActive:Bool, action:@escaping()->Void)->some View {
        Button(action:action) {
            HStack(spacing:5) {
                Image(systemName:icon).font(.system(size:10))
                Text(label).font(.system(size:9,weight:.bold,design:.monospaced))
            }
            .foregroundColor(isActive ? .black : .white.opacity(0.5))
            .frame(maxWidth:.infinity).padding(.vertical,8)
            .background(isActive ? themeVM.accent : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius:8))
        }
    }

    private func card<C:View>(_ title:String, @ViewBuilder content:()->C)->some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            content()
        }.padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:12))
    }
}
