
import SwiftUI
import SceneKit
import simd

@MainActor
public final class ArcLabViewModel: ObservableObject {
    @Published public var selectedElements: [ArcElement] = []
    @Published public var activeTab: ArcTab = .molecule
    @Published public var isPeriodicTableVisible = false
    @Published public var isMolCanvasVisible = false
    @Published public var isCFDActive = false
    @Published public var logEntries: [LogEntry] = []
    @Published public var probeTarget: ArcElement? = nil
    @Published public var isOrbitDeltaVisible = false
    @Published public var cfdParticles: [SPHEngine.Particle] = []
    @Published public var alloyComponents: [AlloyComponent] = []

    public let physics = PhysicsState()
    public let sphEngine: SPHEngine
    public let scene = SCNScene()
    private var atomNodes: [Int: SCNNode] = [:]   // z → root node
    private var cfdTimer: Timer?
    private var displayLink: CADisplayLink?

    public init() {
        sphEngine = SPHEngine(physicsState: PhysicsState())
        setupScene()
    }

    // MARK: — Scene setup
    private func setupScene() {
        scene.background.contents = UIColor(red:0.015, green:0.03, blue:0.07, alpha:1)

        // Ambient light — dim
        let ambient = SCNLight(); ambient.type = .ambient
        ambient.intensity = 200; ambient.color = UIColor.white
        let an = SCNNode(); an.light = ambient
        scene.rootNode.addChildNode(an)

        // Key light — cyan tint
        let key = SCNLight(); key.type = .omni
        key.intensity = 600
        key.color = UIColor(red:0.5, green:0.9, blue:1.0, alpha:1)
        let kn = SCNNode(); kn.position = SCNVector3(8, 8, 8); kn.light = key
        scene.rootNode.addChildNode(kn)

        // Floor grid lines (subtle)
        addGridFloor()

        // Start animation loop
        displayLink = CADisplayLink(target: self, selector: #selector(animationTick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func addGridFloor() {
        let gridNode = SCNNode()
        let gridSize: Float = 20
        let step: Float = 2
        var x: Float = -gridSize
        while x <= gridSize {
            let line = SCNCylinder(radius: 0.005, height: CGFloat(gridSize*2))
            line.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.06)
            let ln = SCNNode(geometry: line)
            ln.position = SCNVector3(x, -3, 0)
            ln.eulerAngles.x = .pi/2
            gridNode.addChildNode(ln)
            let line2 = SCNCylinder(radius: 0.005, height: CGFloat(gridSize*2))
            line2.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.06)
            let ln2 = SCNNode(geometry: line2)
            ln2.position = SCNVector3(0, -3, x)
            gridNode.addChildNode(ln2)
            x += step
        }
        scene.rootNode.addChildNode(gridNode)
    }

    @objc private func animationTick() {
        // Animate electron orbits
        for node in atomNodes.values {
            node.childNodes.forEach { shell in
                shell.childNodes.forEach { electron in
                    if electron.name == "electron" {
                        electron.runAction(
                            SCNAction.rotateBy(x: 0, y: 0.04, z: 0, duration: 0),
                            forKey: "orbit")
                    }
                }
            }
        }
    }

    // MARK: — Element management
    public func addElement(_ element: ArcElement) {
        guard !selectedElements.contains(where: { $0.id == element.id }) else { return }
        selectedElements.append(element)
        buildPointCloudAtom(element)
        log("Added \(element.elementName) (Z=\(element.protons))")
    }

    public func removeElement(_ element: ArcElement) {
        selectedElements.removeAll { $0.id == element.id }
        atomNodes[element.id]?.removeFromParentNode()
        atomNodes.removeValue(forKey: element.id)
        log("Removed \(element.elementName)")
    }

    public func clearElements() {
        selectedElements.removeAll()
        atomNodes.values.forEach { $0.removeFromParentNode() }
        atomNodes.removeAll()
        log("Cleared all elements")
    }

    // MARK: — Point cloud atom rendering (matches web app style)
    private func buildPointCloudAtom(_ element: ArcElement) {
        let root = SCNNode()
        root.name = "atomZ:\(element.id)"

        // Position — spread out horizontally
        let idx = Float(selectedElements.count - 1)
        let spacing: Float = 5.0
        let totalWidth = Float(max(1, selectedElements.count - 1)) * spacing
        root.position = SCNVector3(
            idx * spacing - totalWidth / 2,
            0, 0)

        // Nucleus — point cloud sphere using instanced particles
        let nucleusR = Float(element.neutrons) * 0.02 + 0.25
        buildNucleusCloud(root: root, element: element, radius: nucleusR)

        // Electron shells — orbital rings + point electrons
        for (shellIdx, count) in element.electronOrbits.enumerated() {
            let shellR = Float(shellIdx + 1) * 1.2 + nucleusR + 0.3
            buildShellCloud(root: root, shellIdx: shellIdx, count: count,
                           radius: shellR, color: UIColor(element.category.color))
        }

        // Atom label
        let text = SCNText(string: element.elementSymbol, extrusionDepth: 0.01)
        text.font = UIFont.systemFont(ofSize: 0.4, weight: .bold)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.emission.contents = UIColor(red:0.4, green:0.9, blue:1.0, alpha:0.5)
        let labelNode = SCNNode(geometry: text)
        let (minB, maxB) = text.boundingBox
        let tw = maxB.x - minB.x
        labelNode.position = SCNVector3(-tw/2, -(nucleusR + 0.8), 0)
        labelNode.scale = SCNVector3(0.8, 0.8, 0.8)
        root.addChildNode(labelNode)

        scene.rootNode.addChildNode(root)
        atomNodes[element.id] = root
    }

    // Nucleus: dense point cloud sphere
    private func buildNucleusCloud(root: SCNNode, element: ArcElement, radius: Float) {
        let count = min(element.protons * 12 + element.neutrons * 8, 2000)
        let positions = fibonacciSphere(n: count, radius: radius * 0.7)

        // Proton cloud (orange-red)
        let protonGeo = SCNSphere(radius: 0.012)
        protonGeo.firstMaterial?.diffuse.contents = UIColor(red:1.0, green:0.45, blue:0.1, alpha:1)
        protonGeo.firstMaterial?.emission.contents = UIColor(red:0.5, green:0.2, blue:0.0, alpha:1)
        protonGeo.firstMaterial?.lightingModel = .constant

        let neutronGeo = SCNSphere(radius: 0.014)
        neutronGeo.firstMaterial?.diffuse.contents = UIColor(red:0.6, green:0.6, blue:0.7, alpha:1)
        neutronGeo.firstMaterial?.emission.contents = UIColor(red:0.2, green:0.2, blue:0.3, alpha:1)
        neutronGeo.firstMaterial?.lightingModel = .constant

        for (i, pos) in positions.enumerated() {
            let geo = i % 2 == 0 ? protonGeo : neutronGeo
            let n = SCNNode(geometry: geo)
            n.position = SCNVector3(pos.x, pos.y, pos.z)
            root.addChildNode(n)
        }

        // Nucleus glow sphere
        let glowGeo = SCNSphere(radius: CGFloat(radius))
        glowGeo.firstMaterial?.diffuse.contents = UIColor(red:1.0, green:0.5, blue:0.1, alpha:0.08)
        glowGeo.firstMaterial?.emission.contents = UIColor(red:1.0, green:0.4, blue:0.0, alpha:0.12)
        glowGeo.firstMaterial?.isDoubleSided = true
        glowGeo.firstMaterial?.lightingModel = .constant
        let glowNode = SCNNode(geometry: glowGeo)
        root.addChildNode(glowNode)
    }

    // Shell: orbital ring + point electrons
    private func buildShellCloud(root: SCNNode, shellIdx: Int, count: Int,
                                  radius: Float, color: UIColor) {
        // Orbital ring (thin torus)
        let torus = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.008)
        torus.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.25)
        torus.firstMaterial?.emission.contents = color.withAlphaComponent(0.12)
        torus.firstMaterial?.lightingModel = .constant
        let torusNode = SCNNode(geometry: torus)
        // Tilt each shell slightly differently
        torusNode.eulerAngles = SCNVector3(
            Float.pi/2 + Float(shellIdx) * 0.3,
            Float(shellIdx) * 0.5, 0)
        root.addChildNode(torusNode)

        // Point electrons
        let eGeo = SCNSphere(radius: 0.025)
        eGeo.firstMaterial?.diffuse.contents = color
        eGeo.firstMaterial?.emission.contents = color
        eGeo.firstMaterial?.lightingModel = .constant

        for i in 0..<count {
            let angle = Float(i) / Float(max(count,1)) * 2 * .pi
            let eNode = SCNNode(geometry: eGeo)
            eNode.name = "electron"
            eNode.position = SCNVector3(
                cos(angle) * radius,
                0,
                sin(angle) * radius)
            // Orbital animation
            let speed = Double(1.5 + Float(shellIdx) * 0.4 + Float(i) * 0.05)
            let orbit = SCNAction.rotateBy(x: 0, y: CGFloat.pi*2, z: 0, duration: speed)
            eNode.runAction(SCNAction.repeatForever(orbit))
            torusNode.addChildNode(eNode)
        }
    }

    // Fibonacci sphere point distribution
    private func fibonacciSphere(n: Int, radius: Float) -> [SIMD3<Float>] {
        (0..<n).map { i in
            let theta = Float.pi * (3.0 - sqrt(5.0)) * Float(i)
            let y = (1.0 - Float(i)/Float(max(n-1,1))*2.0) * radius
            let r = sqrt(radius*radius - y*y)
            return SIMD3<Float>(cos(theta)*r, y, sin(theta)*r)
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
        isCFDActive = false; cfdTimer?.invalidate(); cfdTimer = nil
        log("CFD stopped")
    }

    public func exportGLB() -> URL? { SCNExportHelper().exportScene(scene, name: "ArcLake_Export") }

    public func log(_ message: String) {
        logEntries.insert(LogEntry(message: message), at: 0)
        if logEntries.count > 200 { logEntries.removeLast() }
    }

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
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: timestamp)
    }
}
public struct AlloyComponent: Identifiable {
    public var id = UUID()
    public var element: ArcElement
    public var percentage: Double
    public var castingOrder: Int
}

private extension UIColor {
    convenience init(_ c: UIColor) { self.init(cgColor: c.cgColor) }
}
