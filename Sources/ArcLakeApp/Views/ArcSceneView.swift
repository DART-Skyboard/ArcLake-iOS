import SwiftUI
import SceneKit

/// ArcLake 3D Viewport
/// Uses SceneKit's built-in allowsCameraControl = true (same as Autumn BRPN scene)
/// → 1-finger drag  = orbit
/// → 2-finger drag  = pan (translate camera + target)
/// → pinch          = dolly (zoom in/out)
/// → double-tap     = reset view
/// → single tap     = probe atom
/// No custom gesture recognizer conflicts. Simple. Reliable.
public struct ArcSceneView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        // ── SceneKit built-in orbit controls (same as Autumn BRPN) ──
        v.allowsCameraControl   = true
        v.autoenablesDefaultLighting = false
        v.backgroundColor = UIColor(red:0.015, green:0.03, blue:0.07, alpha:1)
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously  = true
        v.scene = labVM.scene

        // Camera — positioned for good initial view of atomic scene
        let cam = SCNCamera()
        cam.fieldOfView = 60
        cam.zFar = 100000
        cam.zNear = 0.001
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.name   = "mainCamera"
        camNode.position = SCNVector3(0, 4, 18)
        camNode.look(at: SCNVector3(0, 0, 0))
        labVM.scene.rootNode.addChildNode(camNode)
        v.pointOfView = camNode

        context.coordinator.scnView   = v
        context.coordinator.cameraNode = camNode
        context.coordinator.lastScene  = labVM.scene

        // Single tap for atom probe (double-tap handled by SCNView internally)
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        v.addGestureRecognizer(tap)

        // Drop support
        v.addInteraction(UIDropInteraction(delegate: context.coordinator))

        return v
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {
        let coord = context.coordinator
        // Scene tab switched — migrate camera to new scene
        if uiView.scene !== labVM.scene {
            coord.cameraNode?.removeFromParentNode()
            uiView.scene = labVM.scene
            if let cam = coord.cameraNode {
                labVM.scene.rootNode.addChildNode(cam)
                uiView.pointOfView = cam
            }
            coord.lastScene = labVM.scene
        }
        // Always ensure pointOfView is ours
        if let cam = coord.cameraNode, uiView.pointOfView !== cam {
            uiView.pointOfView = cam
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(labVM: labVM) }

    public final class Coordinator: NSObject, UIDropInteractionDelegate {
        let labVM: ArcLabViewModel
        weak var scnView: SCNView?
        var cameraNode: SCNNode?
        var lastScene: SCNScene?

        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        // ── Single tap: probe atom ────────────────────────────────
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let v = scnView else { return }
            let hits = v.hitTest(g.location(in: v),
                options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = hits.first else { return }
            var node: SCNNode? = hit.node
            while let cur = node {
                if let name = cur.name, name.hasPrefix("atomZ:"),
                   let z = Int(name.dropFirst(6)),
                   let el = ElementStore.shared.elements.first(where: { $0.id == z }) {
                    Task { @MainActor in self.labVM.openProbe(for: el) }
                    return
                }
                node = cur.parent
            }
        }

        // ── Drop interaction ──────────────────────────────────────
        public func dropInteraction(
            _ i: UIDropInteraction,
            canHandle s: UIDropSession) -> Bool {
            s.canLoadObjects(ofClass: NSString.self)
        }
        public func dropInteraction(
            _ i: UIDropInteraction,
            sessionDidUpdate s: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }
        public func dropInteraction(
            _ i: UIDropInteraction,
            performDrop s: UIDropSession) {
            s.loadObjects(ofClass: NSString.self) { items in
                guard let sym = items.first as? String else { return }
                Task { @MainActor in
                    if let el = ElementStore.shared.elements.first(
                        where: { $0.elementSymbol == sym }) {
                        self.labVM.addElement(el)
                    }
                }
            }
        }
    }
}
