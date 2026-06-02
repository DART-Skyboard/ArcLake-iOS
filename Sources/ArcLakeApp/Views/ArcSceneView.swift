
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
        scnView.backgroundColor = UIColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1)
        scnView.showsStatistics = false
        scnView.antialiasingMode = .multisampling4X
        scnView.rendersContinuously = true

        // Camera
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zFar = 200
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 2, 8)
        cameraNode.look(at: SCNVector3Zero)
        labVM.scene.rootNode.addChildNode(cameraNode)

        // Tap gesture — probe / drop target
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        // Drop target for elements dragged from periodic table
        scnView.addInteraction(UIDropInteraction(delegate: context.coordinator))

        return scnView
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(labVM: labVM)
    }

    public final class Coordinator: NSObject, UIDropInteractionDelegate {
        let labVM: ArcLabViewModel

        init(labVM: ArcLabViewModel) {
            self.labVM = labVM
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            let hits = scnView.hitTest(location, options: nil)
            if let firstHit = hits.first {
                // Find which atom was tapped
                var node: SCNNode? = firstHit.node
                while let n = node {
                    if let group = labVM.atomGroupFor(node: n) {
                        Task { @MainActor in
                            self.labVM.openProbe(for: group.element)
                        }
                        break
                    }
                    node = n.parent
                }
            }
        }

        // MARK: — Drop interaction (from periodic table)
        public func dropInteraction(_ interaction: UIDropInteraction,
                                    canHandle session: UIDropSession) -> Bool {
            session.canLoadObjects(ofClass: NSString.self)
        }

        public func dropInteraction(_ interaction: UIDropInteraction,
                                    sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }

        public func dropInteraction(_ interaction: UIDropInteraction,
                                    performDrop session: UIDropSession) {
            session.loadObjects(ofClass: NSString.self) { items in
                guard let symbol = items.first as? String else { return }
                Task { @MainActor in
                    if let element = ElementStore.shared.elements.first(where: { $0.elementSymbol == symbol }) {
                        self.labVM.addElement(element)
                        self.labVM.log("Dropped \(symbol) into 3D scene")
                    }
                }
            }
        }
    }
}

extension ArcLabViewModel {
    func atomGroupFor(node: SCNNode) -> AtomGroup? {
        // Match node to atom group
        nil // filled by scene lookup
    }
}
