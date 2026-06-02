
import SwiftUI
import SceneKit
import Combine

@MainActor
public final class ArcLabViewModel: ObservableObject {

    // MARK: — Published state
    @Published public var selectedElements: [ArcElement] = []
    @Published public var activeTab: ArcTab = .molecule
    @Published public var isPeriodicTableVisible = false
    @Published public var isMolCanvasVisible = false
    @Published public var isCFDActive = false
    @Published public var logEntries: [LogEntry] = []
    @Published public var probeTarget: ArcElement? = nil
    @Published public var isOrbitDeltaVisible = false
    @Published public var sceneMode: SceneMode = .atomic

    // Physics
    public let physics = PhysicsState()
    public let sphEngine: SPHEngine

    // 3D scene
    public let scene = SCNScene()
    private var atomGroups: [AtomGroup] = []
    private var displayLink: CADisplayLink?

    // CFD
    @Published public var cfdParticles: [SPHEngine.Particle] = []
    private var cfdTimer: Timer?

    // Alloy system
    @Published public var alloyComponents: [AlloyComponent] = []

    public init() {
        sphEngine = SPHEngine(physicsState: PhysicsState())
        setupScene()
    }

    // MARK: — Scene setup
    private func setupScene() {
        scene.background.contents = UIColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 400
        ambient.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let omni = SCNLight()
        omni.type = .omni
        omni.intensity = 800
        omni.color = UIColor(red: 0, green: 0.9, blue: 1, alpha: 1)
        let omniNode = SCNNode()
        omniNode.position = SCNVector3(5, 5, 5)
        omniNode.light = omni
        scene.rootNode.addChildNode(omniNode)
    }

    // MARK: — Element management
    public func addElement(_ element: ArcElement) {
        guard !selectedElements.contains(where: { $0.id == element.id }) else { return }
        selectedElements.append(element)
        buildAtomGroup(for: element)
        log("Added \(element.elementName) (Z=\(element.protons))")
    }

    public func removeElement(_ element: ArcElement) {
        selectedElements.removeAll { $0.id == element.id }
        removeAtomGroup(for: element)
        log("Removed \(element.elementName)")
    }

    public func clearElements() {
        selectedElements.removeAll()
        atomGroups.forEach { $0.node.removeFromParentNode() }
        atomGroups.removeAll()
        log("Cleared all elements")
    }

    // MARK: — 3D atom building
    private func buildAtomGroup(for element: ArcElement) {
        let group = AtomGroup(element: element)
        atomGroups.append(group)
        scene.rootNode.addChildNode(group.node)

        // Position offset by element index
        let idx = Float(selectedElements.count - 1)
        group.node.position = SCNVector3(idx * 3.0 - Float(selectedElements.count) * 1.5, 0, 0)
    }

    private func removeAtomGroup(for element: ArcElement) {
        if let idx = atomGroups.firstIndex(where: { $0.element.id == element.id }) {
            atomGroups[idx].node.removeFromParentNode()
            atomGroups.remove(at: idx)
        }
    }

    // MARK: — CFD
    public func startCFD() {
        guard let first = selectedElements.first else { return }
        isCFDActive = true
        sphEngine.initializeForElement(first, count: physics.activeTab.particleCount)
        cfdTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sphEngine.tick()
                self?.cfdParticles = self?.sphEngine.particles ?? []
            }
        }
        log("CFD started — Tab \(physics.activeTabIndex + 1)")
    }

    public func stopCFD() {
        isCFDActive = false
        cfdTimer?.invalidate()
        cfdTimer = nil
        log("CFD stopped")
    }

    // MARK: — GLB export
    public func exportGLB() -> URL? {
        let exporter = SCNExportHelper()
        return exporter.exportScene(scene, name: "ArcLake_Export")
    }

    // MARK: — Log
    public func log(_ message: String) {
        let entry = LogEntry(message: message)
        logEntries.insert(entry, at: 0)
        if logEntries.count > 200 { logEntries.removeLast() }
    }

    // MARK: — Probe
    public func openProbe(for element: ArcElement) {
        probeTarget = element
        isOrbitDeltaVisible = true
    }
}

// MARK: — Supporting types
public enum ArcTab: String, CaseIterable {
    case molecule = "Molecule"
    case physics  = "Physics"
    case math     = "Math"
    case arc      = "Arc"
    case env      = "Env"
    case log      = "Log"

    var icon: String {
        switch self {
        case .molecule: return "atom"
        case .physics:  return "waveform.path"
        case .math:     return "function"
        case .arc:      return "circle.and.line.horizontal"
        case .env:      return "cloud.fill"
        case .log:      return "list.bullet"
        }
    }
}

public enum SceneMode { case atomic, cfd, mol2D }

public struct LogEntry: Identifiable {
    public let id = UUID()
    public let message: String
    public let timestamp = Date()
    public var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}

public struct AlloyComponent: Identifiable {
    public var id = UUID()
    public var element: ArcElement
    public var percentage: Double
    public var castingOrder: Int
}

// MARK: — AtomGroup: 3D atom node
public final class AtomGroup {
    public let element: ArcElement
    public let node: SCNNode

    public init(element: ArcElement) {
        self.element = element
        self.node = SCNNode()
        build()
    }

    private func build() {
        // Nucleus: neutron-first packing (n⁰ → p⁺ → K → L → M...)
        let nucleusRadius = Float(element.neutrons) * 0.05 + 0.15
        let nucleusGeo = SCNSphere(radius: CGFloat(nucleusRadius))
        nucleusGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1)
        nucleusGeo.firstMaterial?.emission.contents = UIColor(red: 0.4, green: 0.2, blue: 0.0, alpha: 1)
        nucleusGeo.firstMaterial?.specular.contents = UIColor.white
        node.addChildNode(SCNNode(geometry: nucleusGeo))

        // Electron shells
        for (shellIdx, electronCount) in element.electronOrbits.enumerated() {
            let shellRadius = Float(shellIdx + 1) * 0.6 + nucleusRadius
            addShell(radius: shellRadius, electronCount: electronCount,
                    color: element.category.color)
        }

        // Atom label
        let text = SCNText(string: element.elementSymbol, extrusionDepth: 0.02)
        text.font = UIFont.systemFont(ofSize: 0.3, weight: .bold)
        text.firstMaterial?.diffuse.contents = UIColor.white
        let labelNode = SCNNode(geometry: text)
        labelNode.position = SCNVector3(-0.15, -nucleusRadius - 0.4, 0)
        node.addChildNode(labelNode)
    }

    private func addShell(radius: Float, electronCount: Int, color: UIColor) {
        // Shell ring
        let torus = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.015)
        torus.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.3)
        torus.firstMaterial?.emission.contents = color.withAlphaComponent(0.1)
        let shellNode = SCNNode(geometry: torus)
        shellNode.eulerAngles.x = .pi / 2
        node.addChildNode(shellNode)

        // Electrons evenly distributed
        for i in 0..<electronCount {
            let angle = Float(i) / Float(electronCount) * 2 * .pi
            let eSphere = SCNSphere(radius: 0.04)
            eSphere.firstMaterial?.diffuse.contents = color
            eSphere.firstMaterial?.emission.contents = color
            let eNode = SCNNode(geometry: eSphere)
            eNode.position = SCNVector3(cos(angle) * radius, 0, sin(angle) * radius)
            // Orbit animation
            let orbit = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0,
                duration: Double(2.0 + Float(i) * 0.3))
            eNode.runAction(SCNAction.repeatForever(orbit))
            node.addChildNode(eNode)
        }
    }
}
