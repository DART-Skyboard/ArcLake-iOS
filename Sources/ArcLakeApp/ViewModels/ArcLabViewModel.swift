
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

    // ── Particle resolution — pts per component (proton/neutron/electron)
    // Default 30, user-adjustable in Physics tab
    @Published public var ptsPerComponent: Int = 30
    @Published public var isNodeEditorVisible = false
    @Published public var showGrid = true
    @Published public var showFloor = false
    @Published public var showAxisLabels = true
    @Published public var periodicTableMode: PeriodicTableMode = .addToScene
    @Published public var molAtoms: [MolAtomNode] = []
    @Published public var molBonds: [MolBond] = []
    @Published public var deltaConnections: [DeltaConnection] = []
    @Published public var selectedMolAtomId: UUID? = nil
    @Published public var molBondMode: Int = 1
    @Published public var molDeltaMode: Bool = false
    @Published public var molLabelMode: Bool = false
    @Published public var sceneTabs_data: [String] = ["Scene 1"]
    @Published public var sceneTabsCFD: [Bool] = [false]
    @Published public var activeTabIndex: Int = 0

    public let physics = PhysicsState()
    public let sphEngine: SPHEngine

    // MARK: — Per-tab scene state
    // Each tab has its own SCNScene, elements, and atom nodes
    private struct TabState {
        var scene: SCNScene
        var elements: [ArcElement]
        var atomNodes: [Int: SCNNode]
        var atomPositions: [Int: SIMD3<Float>]
        var isCFDActive: Bool
        init() {
            scene = SCNScene()
            elements = []
            atomNodes = [:]
            atomPositions = [:]
            isCFDActive = false
        }
    }
    private var tabStates: [TabState] = [TabState()]

    // The active scene (bound to ArcSceneView)
    @Published public var scene: SCNScene = SCNScene()
    private var atomNodes: [Int: SCNNode] {
        get { tabStates[safe: activeTabIndex]?.atomNodes ?? [:] }
        set { if activeTabIndex < tabStates.count { tabStates[activeTabIndex].atomNodes = newValue } }
    }
    private var atomPositions: [Int: SIMD3<Float>] {
        get { tabStates[safe: activeTabIndex]?.atomPositions ?? [:] }
        set { if activeTabIndex < tabStates.count { tabStates[activeTabIndex].atomPositions = newValue } }
    }
    private var cfdTimer: Timer?
    private var displayLink: CADisplayLink?

    public init() {
        sphEngine = SPHEngine(physicsState: PhysicsState())
        // Setup the first tab's scene
        tabStates[0].scene = SCNScene()
        setupSceneBase(tabStates[0].scene)
        scene = tabStates[0].scene
    }

    // MARK: — Scene setup
    private func setupSceneBase(_ s: SCNScene) {
        s.background.contents = UIColor(red:0.015, green:0.03, blue:0.07, alpha:1)
        let ambient = SCNLight(); ambient.type = .ambient
        ambient.intensity = 180; ambient.color = UIColor.white
        let an = SCNNode(); an.light = ambient
        s.rootNode.addChildNode(an)
        let key = SCNLight(); key.type = .omni; key.intensity = 500
        key.color = UIColor(red:0.5, green:0.9, blue:1.0, alpha:1)
        let kn = SCNNode(); kn.position = SCNVector3(8,8,8); kn.light = key
        s.rootNode.addChildNode(kn)
        addGridFloor(to: s)
    }

    private func addGridFloor(to s: SCNScene? = nil) {
        let target = s ?? scene
        let g = SCNNode(); g.name = "grid"
        let gridSize: Int = 24        // number of lines each side
        let step: Float   = 1.5       // spacing between lines
        let extent: Float = Float(gridSize) * step
        let lineR: CGFloat = 0.007

        for i in stride(from: -gridSize, through: gridSize, by: 1) {
            let offset = Float(i) * step
            let isMajor = i % 4 == 0
            let alpha: CGFloat = isMajor ? 0.18 : 0.06
            let color = UIColor.cyan.withAlphaComponent(alpha)

            // X-axis lines (run along X)
            let xLine = SCNCylinder(radius: lineR, height: CGFloat(extent * 2))
            xLine.firstMaterial?.diffuse.contents  = color
            xLine.firstMaterial?.emission.contents = color
            xLine.firstMaterial?.lightingModel = .constant
            xLine.firstMaterial?.writesToDepthBuffer = false
            let xNode = SCNNode(geometry: xLine)
            xNode.position = SCNVector3(0, 0, offset)
            xNode.eulerAngles = SCNVector3(0, 0, .pi/2)
            g.addChildNode(xNode)

            // Z-axis lines (run along Z)
            let zLine = SCNCylinder(radius: lineR, height: CGFloat(extent * 2))
            zLine.firstMaterial?.diffuse.contents  = color
            zLine.firstMaterial?.emission.contents = color
            zLine.firstMaterial?.lightingModel = .constant
            zLine.firstMaterial?.writesToDepthBuffer = false
            let zNode = SCNNode(geometry: zLine)
            zNode.position = SCNVector3(offset, 0, 0)
            g.addChildNode(zNode)
        }

        // X axis — red
        let xAxis = SCNCylinder(radius: 0.018, height: CGFloat(extent * 2))
        xAxis.firstMaterial?.emission.contents = UIColor(red:1,green:0.2,blue:0.2,alpha:0.55)
        xAxis.firstMaterial?.lightingModel = .constant
        let xAxisNode = SCNNode(geometry: xAxis); xAxisNode.eulerAngles.z = .pi/2
        g.addChildNode(xAxisNode)

        // Z axis — blue
        let zAxis = SCNCylinder(radius: 0.018, height: CGFloat(extent * 2))
        zAxis.firstMaterial?.emission.contents = UIColor(red:0.2,green:0.4,blue:1,alpha:0.55)
        zAxis.firstMaterial?.lightingModel = .constant
        g.addChildNode(SCNNode(geometry: zAxis))  // already along Y, rotate not needed... 
        // Actually Z axis needs rotation
        let zAxisNode = SCNNode(geometry: zAxis); zAxisNode.eulerAngles.x = .pi/2
        g.addChildNode(zAxisNode)

        // Y axis — green
        let yAxis = SCNCylinder(radius: 0.018, height: CGFloat(extent * 2))
        yAxis.firstMaterial?.emission.contents = UIColor(red:0.2,green:1,blue:0.3,alpha:0.55)
        yAxis.firstMaterial?.lightingModel = .constant
        g.addChildNode(SCNNode(geometry: yAxis))

        g.position = SCNVector3(0, 0, 0)
        target.rootNode.addChildNode(g)
    }

    // MARK: — Element management
    public func addElement(_ element: ArcElement) {
        guard !selectedElements.contains(where: { $0.id == element.id }) else { return }
        selectedElements.append(element)
        // Sync to tab state
        if activeTabIndex < tabStates.count {
            tabStates[activeTabIndex].elements = selectedElements
        }
        let pos = physicsPosition(for: element, index: selectedElements.count - 1)
        atomPositions[element.id] = pos
        buildPointCloudAtom(element, at: pos)
        log("Added \(element.elementName) (Z=\(element.protons))")
    }

    public func removeElement(_ element: ArcElement) {
        selectedElements.removeAll { $0.id == element.id }
        atomNodes[element.id]?.removeFromParentNode()
        atomNodes.removeValue(forKey: element.id)
        atomPositions.removeValue(forKey: element.id)
        log("Removed \(element.elementName)")
    }

    // MARK: — 3D Asset Import
    public func importAssetNode(_ node: SCNNode) {
        scene.rootNode.addChildNode(node)
        log("Imported asset: \(node.name ?? "model")")
    }

    public func clearElements() {
        selectedElements.removeAll()
        atomNodes.values.forEach { $0.removeFromParentNode() }
        if activeTabIndex < tabStates.count {
            tabStates[activeTabIndex].elements = []
            tabStates[activeTabIndex].atomNodes = [:]
            tabStates[activeTabIndex].atomPositions = [:]
        }
        log("Cleared all elements")
    }

    // Rebuild all atoms when particle resolution changes
    // MARK: — Scene Tabs (wrappers for RootView)
    public var sceneTabs: [(id: Int, name: String, isCFDMode: Bool)] {
        sceneTabs_data.enumerated().map { (i, name) in
            (id: i, name: name, isCFDMode: sceneTabsCFD[safe: i] ?? false)
        }
    }

    public func switchTab(_ index: Int) {
        guard index < sceneTabs_data.count else { return }
        // Save current CFD state
        if activeTabIndex < tabStates.count {
            tabStates[activeTabIndex].isCFDActive = isCFDActive
        }
        // Stop CFD if running
        if isCFDActive { stopCFD() }

        activeTabIndex = index

        // Ensure tab state exists
        while tabStates.count <= index {
            var newState = TabState()
            newState.scene = SCNScene()
            setupSceneBase(newState.scene)
            tabStates.append(newState)
        }

        // Restore tab scene + elements
        scene = tabStates[index].scene
        selectedElements = tabStates[index].elements

        // Restore CFD if this tab had it active
        if tabStates[index].isCFDActive {
            startCFD()
        }
        log("Switched to \(sceneTabs_data[index])")
    }

    public func addSceneTab() {
        let newIdx = sceneTabs_data.count
        sceneTabs_data.append("Scene \(newIdx + 1)")
        sceneTabsCFD.append(false)
        // Create fresh tab state
        var newState = TabState()
        newState.scene = SCNScene()
        setupSceneBase(newState.scene)
        tabStates.append(newState)
        // Switch to new tab (saves current, loads new)
        switchTab(newIdx)
        log("New scene tab: \(sceneTabs_data.last!)")
    }

    public func removeSceneTab(_ index: Int) {
        guard sceneTabs_data.count > 1, index < sceneTabs_data.count else { return }
        sceneTabs_data.remove(at: index)
        sceneTabsCFD.remove(at: index)
        if index < tabStates.count { tabStates.remove(at: index) }
        let newActive = min(activeTabIndex, sceneTabs_data.count - 1)
        switchTab(newActive)
    }

    public func rebuildAllAtoms() {
        let elements = selectedElements
        clearElements()
        for el in elements { addElement(el) }
        log("Rebuilt \(elements.count) atoms @ \(ptsPerComponent) pts/component")
    }

    // MARK: — Physics-based positioning
    // Atoms auto-space based on atomic radius, charge, and environment physics
    // They repel each other so they never overlap — just like the web app
    private func physicsPosition(for element: ArcElement, index: Int) -> SIMD3<Float> {
        let gravity   = Float(physics.gravity)
        let pressure  = Float(physics.pressure)
        let temp      = Float(physics.temperature)

        // Base atomic radius influences spacing
        let atomicRadius = Float(element.neutrons + element.protons) * 0.04 + 0.8

        // Place atoms in a spiral pattern, repelling from existing atoms
        var candidate = spiralPosition(index: index, spacing: atomicRadius * 3.5)

        // Apply physics offsets
        // Higher gravity pulls atoms down
        candidate.y -= gravity * 0.05
        // Higher pressure compresses the arrangement
        let pressureFactor = max(0.3, 1.0 - pressure * 0.005)
        candidate.x *= pressureFactor
        candidate.z *= pressureFactor
        // Temperature adds thermal jitter
        let thermalJitter = (temp - 72.0) * 0.002
        candidate.x += Float.random(in: -thermalJitter...thermalJitter)
        candidate.z += Float.random(in: -thermalJitter...thermalJitter)

        // Repulsion from existing atoms — push away from neighbors
        for (_, existingPos) in atomPositions {
            let diff = candidate - existingPos
            let dist = simd_length(diff)
            let minDist = atomicRadius * 2.5
            if dist < minDist && dist > 0.001 {
                let push = (diff / dist) * (minDist - dist) * 0.5
                candidate += push
            }
        }

        return candidate
    }

    // Archimedean spiral for initial placement
    private func spiralPosition(index: Int, spacing: Float) -> SIMD3<Float> {
        if index == 0 { return SIMD3<Float>(0, 0, 0) }
        let turns: Float = 0.618  // golden ratio turns
        let angle = Float(index) * turns * 2 * .pi
        let radius = sqrt(Float(index)) * spacing * 0.7
        return SIMD3<Float>(cos(angle) * radius, 0, sin(angle) * radius)
    }

    // MARK: — Point cloud atom builder
    // Each component (proton/neutron/electron) gets ptsPerComponent particles
    private func buildPointCloudAtom(_ element: ArcElement, at position: SIMD3<Float>) {
        let root = SCNNode()
        root.name = "atomZ:\(element.id)"
        root.position = SCNVector3(position.x, position.y, position.z)

        let pts = ptsPerComponent  // e.g. 30 default

        // ── Nucleus ──────────────────────────────────────────────────
        // neutrons × pts + protons × pts points packed into nucleus sphere
        let nucleusR = Float(element.neutrons + element.protons) * 0.018 + 0.22
        let nucleusR_cg = CGFloat(nucleusR)

        // Proton cloud — pts per proton
        let totalProtonPts = element.protons * pts
        let protonPts = fibonacciSphere(n: totalProtonPts, radius: nucleusR * 0.75)
        buildParticleCloud(parent: root, points: protonPts, ptSize: 0.011,
            diffuse: UIColor(red:1.0, green:0.42, blue:0.08, alpha:1),
            emissive: UIColor(red:0.4, green:0.15, blue:0.0, alpha:1))

        // Neutron cloud — pts per neutron
        let totalNeutronPts = element.neutrons * pts
        let neutronPts = fibonacciSphere(n: totalNeutronPts, radius: nucleusR * 0.85)
        buildParticleCloud(parent: root, points: neutronPts, ptSize: 0.013,
            diffuse: UIColor(red:0.55, green:0.55, blue:0.65, alpha:1),
            emissive: UIColor(red:0.15, green:0.15, blue:0.25, alpha:1))

        // Nucleus glow
        let glow = SCNSphere(radius: nucleusR_cg)
        glow.firstMaterial?.diffuse.contents  = UIColor(red:1.0, green:0.5, blue:0.1, alpha:0.07)
        glow.firstMaterial?.emission.contents = UIColor(red:1.0, green:0.4, blue:0.0, alpha:0.10)
        glow.firstMaterial?.isDoubleSided = true
        glow.firstMaterial?.lightingModel = .constant
        root.addChildNode(SCNNode(geometry: glow))

        // ── Electron shells ───────────────────────────────────────────
        // electrons × pts points distributed across orbital shells
        let catColor = element.category.color

        for (shellIdx, electronCount) in element.electronOrbits.enumerated() {
            let shellR = Float(shellIdx + 1) * 1.15 + nucleusR + 0.25
            let shellR_cg = CGFloat(shellR)

            // Orbital ring
            let torus = SCNTorus(ringRadius: shellR_cg, pipeRadius: 0.007)
            torus.firstMaterial?.diffuse.contents  = catColor.withAlphaComponent(0.20)
            torus.firstMaterial?.emission.contents = catColor.withAlphaComponent(0.08)
            torus.firstMaterial?.lightingModel = .constant
            let torusNode = SCNNode(geometry: torus)
            // Each shell tilted differently for 3D look
            torusNode.eulerAngles = SCNVector3(
                Float.pi/2 + Float(shellIdx) * 0.28,
                Float(shellIdx) * 0.52,
                Float(shellIdx) * 0.18)
            root.addChildNode(torusNode)

            // Electron point cloud — electronCount × pts points on this shell
            let totalElectronPts = electronCount * pts
            let ePts = shellSphere(n: totalElectronPts, radius: shellR)
            buildParticleCloud(parent: torusNode, points: ePts, ptSize: 0.020,
                diffuse: catColor, emissive: catColor.withAlphaComponent(0.5))

            // Orbital animation — inner shells faster
            let period = Double(2.2 + Float(shellIdx) * 0.6)
            torusNode.runAction(SCNAction.repeatForever(
                SCNAction.rotateBy(x: 0, y: CGFloat.pi*2, z: 0, duration: period)))
        }

        // Atom label
        let text = SCNText(string: element.elementSymbol, extrusionDepth: 0.01)
        text.font = UIFont.systemFont(ofSize: 0.35, weight: .bold)
        text.firstMaterial?.diffuse.contents  = UIColor.white
        text.firstMaterial?.emission.contents = UIColor(red:0.3, green:0.8, blue:1.0, alpha:0.4)
        text.firstMaterial?.lightingModel = .constant
        let lbl = SCNNode(geometry: text)
        let (mn, mx) = text.boundingBox
        lbl.position = SCNVector3(-(mx.x-mn.x)/2, -(nucleusR + 0.7), 0)
        lbl.scale = SCNVector3(0.75, 0.75, 0.75)
        root.addChildNode(lbl)

        scene.rootNode.addChildNode(root)
        atomNodes[element.id] = root
    }

    // Create a node of tiny spheres at given positions
    private func buildParticleCloud(parent: SCNNode, points: [SIMD3<Float>],
                                     ptSize: CGFloat, diffuse: UIColor, emissive: UIColor) {
        let geo = SCNSphere(radius: ptSize)
        geo.segmentCount = 4   // low poly for performance
        geo.firstMaterial?.diffuse.contents  = diffuse
        geo.firstMaterial?.emission.contents = emissive
        geo.firstMaterial?.lightingModel = .constant

        // Use SCNInstancedGeometry pattern via multiple nodes
        // Group under a container to minimize scene graph overhead
        let container = SCNNode()
        for pt in points {
            let n = SCNNode(geometry: geo)
            n.position = SCNVector3(pt.x, pt.y, pt.z)
            container.addChildNode(n)
        }
        parent.addChildNode(container)
    }

    // Fibonacci sphere — evenly distributed points on sphere surface
    private func fibonacciSphere(n: Int, radius: Float) -> [SIMD3<Float>] {
        guard n > 0 else { return [] }
        return (0..<n).map { i in
            let theta = Float.pi * (3.0 - sqrt(5.0)) * Float(i)
            let y = (1.0 - Float(i) / Float(max(n-1,1)) * 2.0) * radius
            let r = sqrt(max(0, radius*radius - y*y))
            return SIMD3<Float>(cos(theta)*r, y, sin(theta)*r)
        }
    }

    // Shell sphere — points distributed on spherical shell surface
    private func shellSphere(n: Int, radius: Float) -> [SIMD3<Float>] {
        guard n > 0 else { return [] }
        let jitter: Float = radius * 0.08  // slight random spread
        return (0..<n).map { i in
            let theta = Float.pi * (3.0 - sqrt(5.0)) * Float(i)
            let phi   = acos(1.0 - 2.0 * Float(i) / Float(max(n-1,1)))
            let r = radius + Float.random(in: -jitter...jitter)
            return SIMD3<Float>(
                sin(phi)*cos(theta)*r,
                cos(phi)*r,
                sin(phi)*sin(theta)*r)
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

    // MARK: — Mol canvas methods
    public func addElementToCanvas(_ element: ArcElement) {
        let pos = CGPoint(x: 80+Double(molAtoms.count%4)*80, y: 120+Double(molAtoms.count/4)*80)
        molAtoms.append(MolAtomNode(symbol:element.elementSymbol, z:element.protons,
                                    color:element.category.color, at:pos))
        isMolCanvasVisible = true
        log("Added \(element.elementSymbol) to Mol Canvas")
    }

    public func addToMolCanvas(element: ArcElement) { addElementToCanvas(element) }

    public func addMolBond(from: UUID, to: UUID) {
        molBonds.removeAll{($0.fromId==from&&$0.toId==to)||($0.fromId==to&&$0.toId==from)}
        molBonds.append(MolBond(from:from, to:to, order:molBondMode, isDelta:molDeltaMode))
    }

    public func addBond(from: UUID, to: UUID) {
        molBonds.removeAll{($0.fromId==from&&$0.toId==to)||($0.fromId==to&&$0.toId==from)}
        molBonds.append(MolBond(from:from, to:to, order:molBondMode, isDelta:true))
    }

    public func addDeltaConnection(from: UUID, to: UUID, fromShell: Int, toShell: Int, op: String) {
        deltaConnections.append(DeltaConnection(from:from, to:to,
            fromShell:fromShell, toShell:toShell, op:op))
        log("Δ: shell \(fromShell)→\(toShell) [\(op)]")
    }

    public func clearMolCanvas() {
        molAtoms.removeAll(); molBonds.removeAll(); deltaConnections.removeAll()
    }

    public func addMolCanvasToScene(newTab: Bool) {
        if newTab { addSceneTab() }
        for node in molAtoms {
            if let el = ElementStore.shared.elements.first(where:{$0.protons==node.atomicNumber}) {
                addElement(el)
            }
        }
        log("Mol Canvas added to \(newTab ? "new":"current") scene")
    }

    public func rebuildGrid() {
        scene.rootNode.childNodes.filter{$0.name=="grid"}.forEach{$0.removeFromParentNode()}
        if showGrid { addGridFloor(to: scene) }
    }

    public func exportGLB() -> URL? { SCNExportHelper().exportScene(scene, name:"ArcLake_Export") }


    public func log(_ message: String) {
        logEntries.insert(LogEntry(message: message), at: 0)
        if logEntries.count > 200 { logEntries.removeLast() }
    }

    public func openProbe(for element: ArcElement) {
        probeTarget = element; isOrbitDeltaVisible = true
    }
}

// MARK: — Supporting types
public enum ArcTab: String, CaseIterable {
    case molecule="Molecule", physics="Physics", math="Math"
    case arc="Arc", env="Env", log="Log"
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
