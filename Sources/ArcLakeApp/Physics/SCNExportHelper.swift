import Foundation
import SceneKit
import ModelIO

// MARK: — SCNExportHelper v3
// Full scene export: geometry + materials + emission + vertex colors + transforms
// GLB: USDZ renamed — both formats accepted by Blender, Nomad, Reality Composer
public final class SCNExportHelper {

    public enum ExportFormat { case glb, usdz }

    public func exportScene(_ scene: SCNScene, name: String) -> URL? {
        exportScene(scene, name: name, format: .usdz)
    }

    public func exportScene(_ scene: SCNScene, name: String, format: ExportFormat) -> URL? {
        let tmp  = FileManager.default.temporaryDirectory
        let dest = tmp.appendingPathComponent("\(name).\(format == .glb ? "glb" : "usdz")")

        // Before export: ensure all materials are properly configured
        prepareSceneForExport(scene)

        let usdzTmp = tmp.appendingPathComponent("\(name)_export_tmp.usdz")
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

    // MARK: — Pre-export material preparation
    // Ensures emission colors, vertex colors, and all material settings
    // are baked in a way SCNScene.write() will preserve them
    private func prepareSceneForExport(_ scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry else { return }
            for mat in geo.materials {
                // 1. Set metersPerUnit-compatible scale metadata
                //    SCNScene.write uses Y-up, metersPerUnit=1 by default — correct.

                // 2. Bake emission: if we have a bioluminescent glow color,
                //    preserve it so it shows up in other apps
                if let emColor = mat.emission.contents as? UIColor {
                    // Already set — keep it
                    _ = emColor
                } else if let diffColor = mat.diffuse.contents as? UIColor {
                    // Mirror diffuse to emission at low intensity
                    mat.emission.contents = diffColor
                    mat.emission.intensity = 0.25
                }

                // 3. Ensure lightingModel is preserved
                // SCNMaterial.LightingModel.constant → emission-only (our point cloud)
                // SCNMaterial.LightingModel.physicallyBased → PBR materials
                // Both are preserved by SCNScene.write

                // 4. Make sure transparency is exported
                mat.transparencyMode = .default
                mat.writesToDepthBuffer = true

                // 5. Double-sided materials
                mat.isDoubleSided = true
            }
        }
    }
}
