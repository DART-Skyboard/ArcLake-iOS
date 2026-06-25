import Foundation
import SceneKit
import simd
import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// ArcCameraSystem — Nomad Sculpt-style camera management for ArcLake.
//
// Each ArcCamera stores:
//   • camQ      — quaternion orientation (same as Coordinator.camQ)
//   • radius    — orbit distance from pivot
//   • pivot     — world-space look-at center
//   • fov       — field of view in degrees (default 60°, locked while orbiting)
//   • isOrtho   — orthographic (drafting) vs perspective
//   • name      — user-editable label
//
// The coordinator exposes cameraState: ArcCameraState which is
// read/written to save and restore camera positions.
// ═══════════════════════════════════════════════════════════════════

// MARK: — Camera snapshot
public struct ArcCamera: Identifiable, Codable {
    public var id      = UUID()
    public var name:    String
    public var camQ:    simd_quatf   // stored as 4 floats
    public var radius:  Float
    public var pivot:   SIMD3<Float>
    public var fov:     Double = 60
    public var isOrtho: Bool   = false

    // Codable bridge for simd types
    enum CodingKeys: String, CodingKey {
        case id, name, qx, qy, qz, qw, radius, px, py, pz, fov, isOrtho
    }
    public init(id: UUID = UUID(), name: String, camQ: simd_quatf,
                radius: Float, pivot: SIMD3<Float>, fov: Double = 60, isOrtho: Bool = false) {
        self.id=id; self.name=name; self.camQ=camQ
        self.radius=radius; self.pivot=pivot; self.fov=fov; self.isOrtho=isOrtho
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decode(UUID.self,   forKey:.id)
        name    = try c.decode(String.self, forKey:.name)
        let qx  = try c.decode(Float.self,  forKey:.qx)
        let qy  = try c.decode(Float.self,  forKey:.qy)
        let qz  = try c.decode(Float.self,  forKey:.qz)
        let qw  = try c.decode(Float.self,  forKey:.qw)
        camQ    = simd_quatf(ix:qx, iy:qy, iz:qz, r:qw)
        radius  = try c.decode(Float.self,  forKey:.radius)
        let px  = try c.decode(Float.self,  forKey:.px)
        let py  = try c.decode(Float.self,  forKey:.py)
        let pz  = try c.decode(Float.self,  forKey:.pz)
        pivot   = SIMD3<Float>(px,py,pz)
        fov     = try c.decode(Double.self, forKey:.fov)
        isOrtho = try c.decode(Bool.self,   forKey:.isOrtho)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,          forKey:.id)
        try c.encode(name,        forKey:.name)
        try c.encode(camQ.imag.x, forKey:.qx)
        try c.encode(camQ.imag.y, forKey:.qy)
        try c.encode(camQ.imag.z, forKey:.qz)
        try c.encode(camQ.real,   forKey:.qw)
        try c.encode(radius,      forKey:.radius)
        try c.encode(pivot.x,     forKey:.px)
        try c.encode(pivot.y,     forKey:.py)
        try c.encode(pivot.z,     forKey:.pz)
        try c.encode(fov,         forKey:.fov)
        try c.encode(isOrtho,     forKey:.isOrtho)
    }
}

// MARK: — Live camera state (read/write by Coordinator)
public struct ArcCameraState {
    public var camQ:    simd_quatf
    public var radius:  Float
    public var pivot:   SIMD3<Float>
    public var fov:     Double
    public var isOrtho: Bool
}

// MARK: — Camera manager
@MainActor
public final class ArcCameraManager: ObservableObject {
    public static let shared = ArcCameraManager()

    @Published public var cameras:       [ArcCamera] = []
    @Published public var activeCameraId: UUID? = nil
    @Published public var isOrtho:       Bool   = false
    @Published public var fov:           Double = 60

    // Callback from Coordinator — reads current camera live state
    public var getCameraState: (() -> ArcCameraState)? = nil
    // Callback to Coordinator — sets camera live state (animated)
    public var setCameraState: ((ArcCameraState, Bool) -> Void)? = nil

    private let storageKey = "arcCameras_v1"

    public func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ArcCamera].self, from: data) {
            cameras = decoded
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(cameras) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: — Add current view as new camera
    public func addCamera(name: String? = nil) {
        guard let state = getCameraState?() else { return }
        let n = name ?? "Camera \(cameras.count + 1)"
        let cam = ArcCamera(name: n, camQ: state.camQ, radius: state.radius,
                            pivot: state.pivot, fov: state.fov, isOrtho: state.isOrtho)
        cameras.append(cam)
        activeCameraId = cam.id
        save()
    }

    // MARK: — Update existing camera to current view
    public func updateCamera(_ id: UUID) {
        guard let state = getCameraState?(),
              let idx = cameras.firstIndex(where:{$0.id==id}) else { return }
        cameras[idx].camQ   = state.camQ
        cameras[idx].radius = state.radius
        cameras[idx].pivot  = state.pivot
        cameras[idx].fov    = state.fov
        cameras[idx].isOrtho = state.isOrtho
        save()
    }

    // MARK: — Activate a saved camera
    public func activateCamera(_ id: UUID, animated: Bool = true) {
        guard let cam = cameras.first(where:{$0.id==id}) else { return }
        activeCameraId = id
        isOrtho = cam.isOrtho
        fov     = cam.fov
        let state = ArcCameraState(camQ:cam.camQ, radius:cam.radius, pivot:cam.pivot,
                                    fov:cam.fov, isOrtho:cam.isOrtho)
        setCameraState?(state, animated)
    }

    // MARK: — Delete
    public func deleteCamera(_ id: UUID) {
        cameras.removeAll(where:{$0.id==id})
        if activeCameraId == id { activeCameraId = nil }
        save()
    }

    public func renameCamera(_ id: UUID, name: String) {
        if let idx = cameras.firstIndex(where:{$0.id==id}) {
            cameras[idx].name = name; save()
        }
    }

    // MARK: — Reset to default view (not any saved camera)
    public func resetToDefault() {
        // Coordinator.defaultQ is the initial view angle — replicate it here
        let defQ = simd_normalize(
            simd_quatf(angle:  0.52, axis: SIMD3<Float>(0,1,0)) *
            simd_quatf(angle: -0.38, axis: SIMD3<Float>(1,0,0)))
        let state = ArcCameraState(camQ: defQ, radius: 20, pivot: .zero,
                                    fov: 60, isOrtho: false)
        isOrtho = false; fov = 60
        setCameraState?(state, true)
    }

    // MARK: — Cube drag (real-time orbit via gimbal drag)
    private var cubeDragQ0: simd_quatf = simd_quatf(ix:0,iy:0,iz:0,r:1)

    public func beginCubeDrag() {
        if let state = getCameraState?() { cubeDragQ0 = state.camQ }
    }

    public func dragCube(dx: Float, dy: Float) {
        guard let current = getCameraState?() else { return }
        let spd: Float = 0.006
        let right = current.camQ.act(SIMD3<Float>(1,0,0))
        let qYaw   = simd_quatf(angle: -dx * spd, axis: SIMD3<Float>(0,1,0))
        let qPitch = simd_quatf(angle: -dy * spd, axis: right)
        let newQ   = simd_normalize(qYaw * qPitch * current.camQ)
        let state  = ArcCameraState(camQ: newQ, radius: current.radius,
                                     pivot: current.pivot, fov: current.fov,
                                     isOrtho: current.isOrtho)
        setCameraState?(state, false)  // no animation during drag
    }

    public func endCubeDrag() {}

    // MARK: — Snap to standard view
    public func snapToView(_ preset: GimbalPreset) {
        guard let current = getCameraState?() else { return }
        let q: simd_quatf
        switch preset {
        case .front:  q = simd_quatf(angle:0,         axis:SIMD3(0,1,0))
        case .back:   q = simd_quatf(angle:.pi,        axis:SIMD3(0,1,0))
        case .left:   q = simd_quatf(angle:-.pi/2,     axis:SIMD3(0,1,0))
        case .right:  q = simd_quatf(angle: .pi/2,     axis:SIMD3(0,1,0))
        case .top:    q = simd_quatf(angle:-.pi/2,     axis:SIMD3(1,0,0))
        case .bottom: q = simd_quatf(angle: .pi/2,     axis:SIMD3(1,0,0))
        }
        let state = ArcCameraState(camQ: simd_normalize(q), radius: current.radius,
                                    pivot: current.pivot, fov: fov, isOrtho: isOrtho)
        setCameraState?(state, true)
    }

    // MARK: — Toggle ortho/perspective
    public func toggleOrtho(scene: SCNScene, scnView: SCNView?) {
        isOrtho.toggle()
        if let cam = scnView?.pointOfView?.camera {
            cam.usesOrthographicProjection = isOrtho
            if isOrtho {
                // Set orthoScale to approximately match current perspective view
                if let state = getCameraState?() {
                    cam.orthographicScale = Double(state.radius) * 0.5
                }
            }
        }
    }
}

// MARK: — Gimbal view presets
public enum GimbalPreset: String, CaseIterable, Identifiable {
    case front="F", back="B", left="L", right="R", top="T", bottom="Bot"
    public var id: String { rawValue }
    var fullName: String {
        switch self {
        case .front: return "Front"; case .back: return "Back"
        case .left:  return "Left";  case .right: return "Right"
        case .top:   return "Top";   case .bottom: return "Bottom"
        }
    }
    var color: Color {
        switch self {
        case .front:  return .green
        case .back:   return Color(red:0.1,green:0.6,blue:0.1)
        case .left:   return .red
        case .right:  return Color(red:0.6,green:0.1,blue:0.1)
        case .top:    return .blue
        case .bottom: return Color(red:0.1,green:0.1,blue:0.6)
        }
    }
}
