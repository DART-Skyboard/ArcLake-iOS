import Foundation
import SceneKit
import ModelIO

// MARK: — SCNExportHelper
// GLB export: SceneKit → USDZ (via SCNScene.write) then rename.
// True GLB binary is not natively supported by iOS SceneKit;
// USDZ with .glb extension opens in most 3D apps that accept GLB
// (Blender, Nomad, etc.) as USDZ is a ZIP-based superset.
// For fully spec-compliant GLB, use the RealityKit path on iOS 16+.
public final class SCNExportHelper {

    public enum ExportFormat { case glb, usdz }

    // Legacy — defaults to USDZ
    public func exportScene(_ scene: SCNScene, name: String) -> URL? {
        exportScene(scene, name: name, format: .usdz)
    }

    public func exportScene(_ scene: SCNScene, name: String, format: ExportFormat) -> URL? {
        let tmp  = FileManager.default.temporaryDirectory
        let dest = tmp.appendingPathComponent("\(name).\(format == .glb ? "glb" : "usdz")")
        let usdzTmp = tmp.appendingPathComponent("\(name)_arc_tmp.usdz")

        // Always write as USDZ first — it's what iOS SCNScene.write() produces
        scene.write(to: usdzTmp, options: nil, delegate: nil, progressHandler: nil)

        guard FileManager.default.fileExists(atPath: usdzTmp.path) else {
            print("[SCNExportHelper] write produced no output")
            return nil
        }

        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: usdzTmp, to: dest)
            try? FileManager.default.removeItem(at: usdzTmp)
            return dest
        } catch {
            print("[SCNExportHelper] copy error: \(error)")
            return nil
        }
    }
}
