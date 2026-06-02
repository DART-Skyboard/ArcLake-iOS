
import Foundation
import SceneKit
import ModelIO

public final class SCNExportHelper {
    public func exportScene(_ scene: SCNScene, name: String) -> URL? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).usdz")
        do {
            try scene.write(to: tmpURL, options: nil, delegate: nil, progressHandler: nil)
            return tmpURL
        } catch {
            print("[GLB Export] Error: \(error)")
            return nil
        }
    }
}
