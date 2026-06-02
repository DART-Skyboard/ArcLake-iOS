
import SwiftUI
import SceneKit

public struct ArcSceneView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = labVM.scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = UIColor(red:0.02, green:0.04, blue:0.08, alpha:1)
        scnView.antialiasingMode = .multisampling4X
        scnView.rendersContinuously = true
        scnView.showsStatistics = false

        // Camera — zoomed out to see atoms properly
        let cam = SCNCamera()
        cam.fieldOfView = 55
        cam.zFar = 500
        cam.zNear = 0.01
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 3, 14)
        camNode.look(at: SCNVector3Zero)
        labVM.scene.rootNode.addChildNode(camNode)

        // Tap to probe
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        // Drop target
        scnView.addInteraction(UIDropInteraction(delegate: context.coordinator))

        return scnView
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {}
    public func makeCoordinator() -> Coordinator { Coordinator(labVM: labVM) }

    public final class Coordinator: NSObject, UIDropInteractionDelegate {
        let labVM: ArcLabViewModel
        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? SCNView else { return }
            let hits = v.hitTest(g.location(in: v), options: nil)
            if let node = hits.first?.node {
                // Walk up to find atom group
                var n: SCNNode? = node
                while let cur = n {
                    if let name = cur.name, name.hasPrefix("atomZ:"),
                       let z = Int(name.dropFirst(6)),
                       let el = ElementStore.shared.elements.first(where: { $0.id == z }) {
                        Task { @MainActor in self.labVM.openProbe(for: el) }
                        return
                    }
                    n = cur.parent
                }
            }
        }

        public func dropInteraction(_ i: UIDropInteraction, canHandle s: UIDropSession) -> Bool {
            s.canLoadObjects(ofClass: NSString.self)
        }
        public func dropInteraction(_ i: UIDropInteraction, sessionDidUpdate s: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }
        public func dropInteraction(_ i: UIDropInteraction, performDrop s: UIDropSession) {
            s.loadObjects(ofClass: NSString.self) { items in
                guard let sym = items.first as? String else { return }
                Task { @MainActor in
                    if let el = ElementStore.shared.elements.first(where: { $0.elementSymbol == sym }) {
                        self.labVM.addElement(el)
                    }
                }
            }
        }
    }
}
