
import SwiftUI
import SceneKit

public struct ArcSceneView: UIViewRepresentable {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = labVM.scene
        v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.backgroundColor = UIColor(red:0.015, green:0.03, blue:0.07, alpha:1)
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.showsStatistics = false

        // Camera
        let cam = SCNCamera()
        cam.fieldOfView = 55; cam.zFar = 1000; cam.zNear = 0.01
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 2, 14)
        camNode.look(at: SCNVector3Zero)
        camNode.name = "mainCamera"
        labVM.scene.rootNode.addChildNode(camNode)
        context.coordinator.cameraNode = camNode

        // ── Gestures ─────────────────────────────────────────────
        // 1-finger pan = orbit (standard orbit control behavior)
        let orbit = UIPanGestureRecognizer(target: context.coordinator,
                                            action: #selector(Coordinator.handleOrbit(_:)))
        orbit.minimumNumberOfTouches = 1
        orbit.maximumNumberOfTouches = 1

        // 2-finger pan = pan/translate camera
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2

        // Pinch = zoom
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handlePinch(_:)))

        // Tap = probe atom
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTouchesRequired = 1

        orbit.delegate = context.coordinator
        pan.delegate   = context.coordinator
        pinch.delegate = context.coordinator

        v.addGestureRecognizer(orbit)
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(pinch)
        v.addGestureRecognizer(tap)
        v.addInteraction(UIDropInteraction(delegate: context.coordinator))

        context.coordinator.scnView = v
        return v
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {}
    public func makeCoordinator() -> Coordinator { Coordinator(labVM: labVM) }

    // MARK: — Coordinator
    public final class Coordinator: NSObject,
            UIGestureRecognizerDelegate, UIDropInteractionDelegate {

        let labVM: ArcLabViewModel
        weak var scnView: SCNView?
        var cameraNode: SCNNode?

        private var orbitYaw:   Float = 0
        private var orbitPitch: Float = 0.25
        private var orbitDist:  Float = 14
        private var panTarget   = SIMD3<Float>(0, 0, 0)

        // Gesture start snapshots
        private var startYaw:   Float = 0
        private var startPitch: Float = 0
        private var startDist:  Float = 14
        private var startPan    = SIMD3<Float>(0, 0, 0)

        init(labVM: ArcLabViewModel) { self.labVM = labVM }

        // ── 1-finger orbit ────────────────────────────────────────
        @objc func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            switch g.state {
            case .began:
                startYaw   = orbitYaw
                startPitch = orbitPitch
            case .changed:
                let t = g.translation(in: v)
                let sensitivity: Float = 0.005
                orbitYaw   = startYaw   - Float(t.x) * sensitivity
                orbitPitch = max(-.pi/2 + 0.05, min(.pi/2 - 0.05,
                             startPitch + Float(t.y) * sensitivity))
                updateCamera()
            default: break
            }
        }

        // ── 2-finger pan ──────────────────────────────────────────
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = scnView else { return }
            switch g.state {
            case .began: startPan = panTarget
            case .changed:
                let t = g.translation(in: v)
                let speed = orbitDist * 0.003
                let right = SIMD3<Float>( cos(orbitYaw), 0, -sin(orbitYaw))
                let up    = SIMD3<Float>(0, 1, 0)
                panTarget = startPan
                    - right * Float(t.x) * speed
                    + up    * Float(t.y) * speed
                updateCamera()
            default: break
            }
        }

        // ── Pinch zoom ────────────────────────────────────────────
        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: startDist = orbitDist
            case .changed:
                orbitDist = max(1.5, min(80, startDist / Float(g.scale)))
                updateCamera()
            default: break
            }
        }

        // ── Tap = probe + focus ───────────────────────────────────
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
                    let wp = cur.worldPosition
                    panTarget = SIMD3<Float>(wp.x, wp.y, wp.z)
                    updateCamera()
                    Task { @MainActor in self.labVM.openProbe(for: el) }
                    return
                }
                node = cur.parent
            }
            // Tap empty → reset focus
            panTarget = .zero; updateCamera()
        }

        private func updateCamera() {
            guard let cam = cameraNode else { return }
            let x = orbitDist * cos(orbitPitch) * sin(orbitYaw)
            let y = orbitDist * sin(orbitPitch)
            let z = orbitDist * cos(orbitPitch) * cos(orbitYaw)
            cam.position = SCNVector3(panTarget.x+x, panTarget.y+y, panTarget.z+z)
            cam.look(at: SCNVector3(panTarget.x, panTarget.y, panTarget.z))
        }

        public func gestureRecognizer(_ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        // Drop
        public func dropInteraction(_ i: UIDropInteraction, canHandle s: UIDropSession) -> Bool {
            s.canLoadObjects(ofClass: NSString.self)
        }
        public func dropInteraction(_ i: UIDropInteraction,
            sessionDidUpdate s: UIDropSession) -> UIDropProposal { UIDropProposal(operation: .copy) }
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
