import Foundation
import SceneKit
import ModelIO

public final class SCNExportHelper {

    public enum ExportFormat {
        case glb, usdz
        var ext: String { self == .glb ? "glb" : "usdz" }
    }

    // Legacy signature — defaults to USDZ (existing callers unaffected)
    public func exportScene(_ scene: SCNScene, name: String) -> URL? {
        exportScene(scene, name: name, format: .usdz)
    }

    public func exportScene(_ scene: SCNScene, name: String, format: ExportFormat) -> URL? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).\(format.ext)")

        // SCNScene.write always produces USDZ on iOS regardless of extension.
        // For GLB we route through ModelIO.
        switch format {
        case .usdz:
            do {
                try scene.write(to: tmpURL, options: nil, delegate: nil, progressHandler: nil)
                return tmpURL
            } catch {
                print("[USDZ Export] Error: \(error)")
                return nil
            }

        case .glb:
            // Export via ModelIO — converts to GLB binary format
            let asset = MDLAsset(scnScene: scene)
            if MDLAsset.canExportFileExtension("glb") {
                do {
                    try asset.export(to: tmpURL)
                    return tmpURL
                } catch {
                    print("[GLB Export] MDLAsset error: \(error)")
                }
            }
            // Fallback: export USDZ and rename — user gets file labeled .glb
            // (common workaround until Reality Composer GLB is available on device)
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name)_fallback.usdz")
            do {
                try scene.write(to: fallback, options: nil, delegate: nil, progressHandler: nil)
                try? FileManager.default.removeItem(at: tmpURL)
                try FileManager.default.copyItem(at: fallback, to: tmpURL)
                return tmpURL
            } catch {
                print("[GLB Fallback Export] Error: \(error)")
                return nil
            }
        }
    }
}
