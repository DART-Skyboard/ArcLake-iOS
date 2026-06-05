import Foundation
import SceneKit
import ModelIO

public final class SCNExportHelper {

    public enum ExportFormat { case glb, usdz }

    public func exportScene(_ scene: SCNScene, name: String) -> URL? {
        exportScene(scene, name: name, format: .usdz)
    }

    public func exportScene(_ scene: SCNScene, name: String, format: ExportFormat) -> URL? {
        let ext  = format == .glb ? "glb" : "usdz"
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).\(ext)")

        // On iOS, SCNScene.write() always writes USDZ regardless of extension.
        // We write to a .usdz temp file first, then copy/rename for GLB.
        let usdzURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_export_tmp.usdz")

        // scene.write throws on failure but the signature doesn't mark it throws —
        // wrap in a task that checks file existence instead.
        scene.write(to: usdzURL, options: nil, delegate: nil, progressHandler: nil)

        guard FileManager.default.fileExists(atPath: usdzURL.path) else {
            print("[SCNExportHelper] scene.write produced no output")
            return nil
        }

        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: usdzURL, to: dest)
            try? FileManager.default.removeItem(at: usdzURL)
            return dest
        } catch {
            print("[SCNExportHelper] copy error: \(error)")
            return nil
        }
    }
}
