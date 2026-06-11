
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
    @Published public var tappedElement: ArcElement? = nil   // atom tap info card
    @Published public var isOrbitDeltaVisible = false
    @Published public var molCanvasPendingElement: ArcElement? = nil
    @Published public var cfdParticles: [SPHEngine.Particle] = []
    @Published public var alloyComponents: [AlloyComponent] = []

    // ── Particle resolution — pts per component (proton/neutron/electron)
    // Default 30, user-adjustable in Physics tab
    @Published public var ptsPerComponent: Int = 30   // range 1…3000 (web parity)

    // ── Arc Edge Field Array state ───────────────────────────────────
    @Published public var arcAllSceneComponent: ArcComponentField? = nil
    @Published public var arcFieldComponents: Set<ArcComponentField> =
        [.group, .neutron, .proton, .electron]
    @Published public var arcSeqSelection: [Int] = []      // atoms in LINK ORDER
    @Published public var arcSameKindFilter = false
    @Published public var arcMeasureResults: [ArcMeasureResult] = []
    @Published public var arcEdgeLengthSum: Double = 0
    @Published public var arcMeasureMode: ArcMeasureMode = .distance
    public var atomVelocities: [Int: SIMD3<Float>] = [:]

    // ── Math engine state (SET 1–4 cards) ───────────────────────────
    @Published public var mathSets: [ArcMathSet] =
        [ArcMathSet(), ArcMathSet(), ArcMathSet(), ArcMathSet()]
    @Published public var mathSigma: Double = 0
    @Published public var mathChain: [String] = []
    @Published public var mathSigmaEnv = false

    // ── Physics environment ──────────────────────────────────────────
    @Published public var matterState: MatterState = .gas
    @Published public var envPreset: EnvPreset = .earth
    @Published public var windVelocity: Double = 0
    @Published public var windDirection: WindDir = .plusZ

    // ── Transport / recorder ─────────────────────────────────────────
    @Published public var isPlaying = false
    @Published public var isRecording = false
    @Published public var playheadFrame: Int = 0
    @Published public var recordedFrameCount: Int = 0
    public var recordedFrames: [RecordedFrame] = []
    var engineTimer: Timer? = nil

    // Engine extension (separate file) needs atom node access
    public func atomNode(for id: Int) -> SCNNode? { atomNodes[id] }
    @Published public var isNodeEditorVisible = false
    @Published public var isMantisNavVisible = false
    @Published public var showGrid   = true
    // Arc Edge Vector defaults: XZ floor plane only; XY / YZ toggleable on demand
    @Published public var showGridXZ = true
    @Published public var showGridXY = false
    @Published public var showGridYZ = false

    // ── Arc Edge advanced settings (arc-edge-vector.html parity) ──
    @Published public var gridDivisions: Int = 20      // 20×20 unit floor plane
    @Published public var arcDOC: Double = 3.0          // Arc Edge doc constant (replaces π)
    @Published public var sigmaMX: Double = 0           // Sigma Meridian shared 3D point
    @Published public var sigmaMY: Double = 0
    @Published public var sigmaMZ: Double = 0
    @Published public var meridianJoinXZ = true          // per-plane meridian join
    @Published public var meridianJoinXY = true
    @Published public var meridianJoinZY = true

    // ── Arc physics pipe — routes ArcLake environment physics into the
    //    Sigma Meridian of the arc-vector grid (arc-edge-vector.html parity)
    public enum ArcPipeMode: String, CaseIterable {
        case off          = "Off"
        case localMeridian = "Local Meridian"   // each arc vector deforms at its own meridian
        case globalGrid    = "Global Grid"      // whole grid deforms as one unified arc from world origin
    }
    @Published public var arcPhysicsPipe: ArcPipeMode = .off

    // ── Viewport units of measure ──────────────────────────────────
    // Arc Vector 1=1 is the native unit of the arc-vector hardware logic.
    public enum ArcUnitSystem: String, CaseIterable {
        case arcVector = "Arc Vector: 1=1"
        case metric    = "Metric"
        case imperial  = "Imperial"
    }
    @Published public var unitSystem: ArcUnitSystem = ArcUnitSystem(
        rawValue: UserDefaults.standard.string(forKey: "arcLakeUnits") ?? ""
    ) ?? .arcVector {
        didSet { UserDefaults.standard.set(unitSystem.rawValue, forKey: "arcLakeUnits") }
    }
    /// Human-readable length for `units` scene units, in the active unit system.
    /// 1 scene unit = 1 arc vector = 1 metre (metric) = 3.28084 ft (imperial).
    public func lengthLabel(_ units: Double) -> String {
        switch unitSystem {
        case .arcVector: return String(format: "%.3f av", units)
        case .metric:    return units >= 1000 ? String(format: "%.3f km", units/1000)
                                              : String(format: "%.3f m",  units)
        case .imperial:
            let ft = units * 3.28084
            return ft >= 5280 ? String(format: "%.3f mi", ft/5280)
                              : String(format: "%.2f ft", ft)
        }
    }
    public var unitSuffix: String {
        switch unitSystem {
        case .arcVector: return "av"
        case .metric:    return "m"
        case .imperial:  return "ft"
        }
    }
    @Published public var showFloor = false
    @Published public var showAxisLabels     = true
    @Published public var showAxisIndicators = true
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
        // 20×20 unit floor plane by default (gridDivisions cells per side)
        let N = max(2, gridDivisions / 2); let step: Float = 1.5; let ext = Float(N) * step

        // ── Arc-vector sigma: physics pipe feeds environment physics
        //    directly into the Sigma Meridian (temperature + gravity terms)
        let baseSigma = SIMD3<Float>(Float(sigmaMX), Float(sigmaMY), Float(sigmaMZ))
        var sigma = baseSigma
        if arcPhysicsPipe != .off {
            let tempTerm = Float((physics.temperature - 72.0) / 72.0) * 1.5   // °F deviation
            let gravTerm = Float((physics.gravity - 9.8) / 9.8) * 1.5          // m/s² deviation
            sigma += SIMD3<Float>(gravTerm, tempTerm, gravTerm)
        }
        let docScale  = Float(arcDOC) / 3.0          // DOC replaces π — 3.0 = neutral
        let deformOn  = simd_length(sigma) > 0.0005
        let globalMode = (arcPhysicsPipe == .globalGrid)

        // Arc-vector displacement field (arc-edge-vector.html parity):
        // bell(u) = 1 − u² — welds to zero at arc-vector endpoints, peaks at meridian.
        // local  : each line is its own arc vector (meridian at its midpoint)
        // global : the entire grid is ONE unified arc vector propagating from world
        //          origin — the unified surface the per-plane Join Meridian creates.
        func arcDisp(_ t: Float, _ ortho: Float, _ amp: Float) -> Float {
            guard deformOn, amp != 0 else { return 0 }
            if globalMode {
                let r = sqrt(t*t + ortho*ortho) / ext
                return amp * max(0, 1 - r*r) * docScale
            } else {
                let u = t / ext
                return amp * max(0, 1 - u*u) * docScale
            }
        }

        // Grid line — cyan, constant lighting
        func makeLine(_ a: SCNVector3, _ b: SCNVector3, alpha: CGFloat) -> SCNNode {
            let dx=b.x-a.x, dy=b.y-a.y, dz=b.z-a.z
            let len=sqrt(dx*dx+dy*dy+dz*dz)
            let c=SCNCylinder(radius:0.006, height:CGFloat(len))
            c.firstMaterial?.emission.contents=UIColor.cyan.withAlphaComponent(alpha)
            c.firstMaterial?.lightingModel = .constant
            let n=SCNNode(geometry:c)
            n.position=SCNVector3((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
            if abs(dx)>0.001 { n.eulerAngles=SCNVector3(0,0,Float.pi/2) }
            else if abs(dz)>0.001 { n.eulerAngles=SCNVector3(Float.pi/2,0,0) }
            return n
        }

        // Arc-vector grid line — when deformation is active, the line renders
        // as a sampled polyline of the quad spline; otherwise one cylinder.
        func makeArcLine(_ a: SCNVector3, _ b: SCNVector3, alpha: CGFloat,
                         axis: Int, lift: Int, ortho: Float, joined: Bool) -> SCNNode {
            let amp: Float = joined ? sigma[lift] : 0
            guard deformOn, amp != 0 else { return makeLine(a, b, alpha: alpha) }
            let parent = SCNNode()
            let segs = 24
            var prev: SCNVector3? = nil
            for i in 0...segs {
                let f = Float(i) / Float(segs)
                var p = SCNVector3(a.x + (b.x-a.x)*f, a.y + (b.y-a.y)*f, a.z + (b.z-a.z)*f)
                let t = (axis == 0 ? p.x : (axis == 1 ? p.y : p.z))
                let d = arcDisp(t, ortho, amp)
                if lift == 0 { p.x += d } else if lift == 1 { p.y += d } else { p.z += d }
                if let q = prev { parent.addChildNode(makeLine(q, p, alpha: alpha)) }
                prev = p
            }
            return parent
        }


        // Solid positive half-axis
        func posAxis(_ color: UIColor, length: Float, rx: Float, rz: Float,
                     offset: SCNVector3) -> SCNNode {
            let c = SCNCylinder(radius: 0.022, height: CGFloat(length))
            c.firstMaterial?.diffuse.contents  = color
            c.firstMaterial?.emission.contents = color
            c.firstMaterial?.lightingModel = .constant
            let n = SCNNode(geometry: c)
            n.eulerAngles = SCNVector3(rx, 0, rz)
            n.position = offset
            return n
        }

        // Dashed negative half-axis — same color, lower opacity, segmented cylinders
        func negAxis(_ color: UIColor, length: Float, rx: Float, rz: Float,
                     dir: SIMD3<Float>) -> SCNNode {
            let group = SCNNode()
            let dashLen: Float = 0.35; let gapLen: Float = 0.25
            var t: Float = gapLen
            while t < length {
                let dLen = min(dashLen, length - t)
                let c = SCNCylinder(radius: 0.01, height: CGFloat(dLen))
                c.firstMaterial?.diffuse.contents  = color.withAlphaComponent(0.6)
                c.firstMaterial?.emission.contents = color.withAlphaComponent(0.6)
                c.firstMaterial?.lightingModel = .constant
                let dn = SCNNode(geometry: c)
                dn.eulerAngles = SCNVector3(rx, 0, rz)
                let center = t + dLen/2
                dn.position = SCNVector3(dir.x*center, dir.y*center, dir.z*center)
                group.addChildNode(dn)
                t += dashLen + gapLen
            }
            return group
        }

        func arrowHead(color: UIColor, pos: SCNVector3, rx: Float, rz: Float) -> SCNNode {
            let cone = SCNCone(topRadius: 0, bottomRadius: 0.09, height: 0.32)
            cone.firstMaterial?.diffuse.contents  = color
            cone.firstMaterial?.emission.contents = color
            cone.firstMaterial?.lightingModel = .constant
            let n = SCNNode(geometry: cone)
            n.position = pos; n.eulerAngles = SCNVector3(rx, 0, rz)
            return n
        }

        func axisLabel(_ text: String, color: UIColor, pos: SCNVector3) -> SCNNode {
            let t = SCNText(string: text, extrusionDepth: 0.02)
            t.font = UIFont.systemFont(ofSize: 0.32, weight: .bold)
            t.firstMaterial?.emission.contents = color
            t.firstMaterial?.lightingModel = .constant
            let n = SCNNode(geometry: t)
            n.position = pos
            return n
        }

        // Pure saturated RGB — visible against white grid lines
        let xCol = UIColor(red:1.0, green:0.0, blue:0.0, alpha:1.0)  // X = red
        let yCol = UIColor(red:0.0, green:1.0, blue:0.0, alpha:1.0)  // Y = green
        let zCol = UIColor(red:0.0, green:0.3, blue:1.0, alpha:1.0)  // Z = blue

        if showAxisIndicators {
            let axisGroup = SCNNode(); axisGroup.name = "axis_origin"

            // X — red positive solid, negative dashed
            axisGroup.addChildNode(posAxis(xCol, length: ext, rx: 0, rz: Float.pi/2,
                offset: SCNVector3(ext/2, 0, 0)))
            axisGroup.addChildNode(negAxis(xCol, length: ext, rx: 0, rz: Float.pi/2,
                dir: SIMD3<Float>(-1,0,0)))
            axisGroup.addChildNode(arrowHead(color: xCol,
                pos: SCNVector3(ext+0.16, 0, 0), rx: 0, rz: -Float.pi/2))
            if showAxisLabels {
                axisGroup.addChildNode(axisLabel("+X", color: xCol,
                    pos: SCNVector3(ext+0.35, -0.12, -0.15)))
            }

            // Y — green positive solid, negative dashed
            axisGroup.addChildNode(posAxis(yCol, length: ext, rx: 0, rz: 0,
                offset: SCNVector3(0, ext/2, 0)))
            axisGroup.addChildNode(negAxis(yCol, length: ext, rx: 0, rz: 0,
                dir: SIMD3<Float>(0,-1,0)))
            axisGroup.addChildNode(arrowHead(color: yCol,
                pos: SCNVector3(0, ext+0.16, 0), rx: 0, rz: 0))
            if showAxisLabels {
                axisGroup.addChildNode(axisLabel("+Y", color: yCol,
                    pos: SCNVector3(0.12, ext+0.35, -0.15)))
            }

            // Z — blue positive solid, negative dashed
            axisGroup.addChildNode(posAxis(zCol, length: ext, rx: Float.pi/2, rz: 0,
                offset: SCNVector3(0, 0, ext/2)))
            axisGroup.addChildNode(negAxis(zCol, length: ext, rx: Float.pi/2, rz: 0,
                dir: SIMD3<Float>(0,0,-1)))
            axisGroup.addChildNode(arrowHead(color: zCol,
                pos: SCNVector3(0, 0, ext+0.16), rx: Float.pi/2, rz: 0))
            if showAxisLabels {
                axisGroup.addChildNode(axisLabel("+Z", color: zCol,
                    pos: SCNVector3(0.12, -0.12, ext+0.35)))
            }

            target.rootNode.addChildNode(axisGroup)
        }

        if showGridXZ {
            let g=SCNNode(); g.name="grid_xz"
            for i in stride(from: -N, through: N, by: 1) {
                let o=Float(i)*step; let major=(i%4==0)
                let a: CGFloat = major ? 0.18 : 0.06
                // XZ floor plane — each line is an arc vector lifting in Y;
                // Join Meridian welds them into one unified deformable surface
                g.addChildNode(makeArcLine(SCNVector3(-ext,0,o),SCNVector3(ext,0,o),alpha:a,
                                           axis:0, lift:1, ortho:o, joined:meridianJoinXZ))
                g.addChildNode(makeArcLine(SCNVector3(o,0,-ext),SCNVector3(o,0,ext),alpha:a,
                                           axis:2, lift:1, ortho:o, joined:meridianJoinXZ))
            }
            target.rootNode.addChildNode(g)
        }
        if showGridXY {
            let g=SCNNode(); g.name="grid_xy"
            for i in stride(from: -N, through: N, by: 1) {
                let o=Float(i)*step; let major=(i%4==0); let a: CGFloat = major ? 0.18 : 0.06
                g.addChildNode(makeArcLine(SCNVector3(-ext,o,0),SCNVector3(ext,o,0),alpha:a,
                                           axis:0, lift:2, ortho:o, joined:meridianJoinXY))
                g.addChildNode(makeArcLine(SCNVector3(o,-ext,0),SCNVector3(o,ext,0),alpha:a,
                                           axis:1, lift:2, ortho:o, joined:meridianJoinXY))
            }
            target.rootNode.addChildNode(g)
        }
        if showGridYZ {
            let g=SCNNode(); g.name="grid_yz"
            for i in stride(from: -N, through: N, by: 1) {
                let o=Float(i)*step; let major=(i%4==0); let a: CGFloat = major ? 0.18 : 0.06
                g.addChildNode(makeArcLine(SCNVector3(0,-ext,o),SCNVector3(0,ext,o),alpha:a,
                                           axis:1, lift:0, ortho:o, joined:meridianJoinZY))
                g.addChildNode(makeArcLine(SCNVector3(0,o,-ext),SCNVector3(0,o,ext),alpha:a,
                                           axis:2, lift:0, ortho:o, joined:meridianJoinZY))
            }
            target.rootNode.addChildNode(g)
        }
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

    // Add multiple copies of the same element to the scene
    // (unlike addElement which blocks duplicates)
    public func addElementInstance(_ element: ArcElement) {
        selectedElements.append(element)
        if activeTabIndex < tabStates.count {
            tabStates[activeTabIndex].elements = selectedElements
        }
        // Offset each instance slightly so they don't stack on top
        let instanceIdx = selectedElements.count - 1
        let angle = Float(instanceIdx) * 0.618 * .pi * 2   // golden angle spread
        let radius = Float(instanceIdx / 6 + 1) * 2.5
        let pos = SIMD3<Float>(
            radius * cos(angle),
            0,
            radius * sin(angle)
        )
        atomPositions[element.id + instanceIdx * 1000] = pos
        buildPointCloudAtom(element, at: pos)
        log("Added instance of \(element.elementName) (\(instanceIdx + 1) in scene)")
    }

    // Add element to Mol Canvas instead of 3D scene
    public func addToMolCanvas(_ element: ArcElement) {
        // Set pending atom in MolCanvasState — MolCanvasView picks it up on next appear/onChange
        MolCanvasState.shared.pendingAtom = (
            symbol: element.elementSymbol,
            z: element.protons,
            color: element.category.color
        )
        // Open the canvas if not already open
        if !isMolCanvasVisible {
            withAnimation(.spring()) { isMolCanvasVisible = true }
        }
        log("Sent \(element.elementSymbol) to Mol Canvas")
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
        node.removeFromParentNode()
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

        // Invisible hit-sphere covering the whole atom — makes tap reliable
        // even when particle density is low near the edges
        let totalR = Float(element.electronOrbits.count) * 1.15 + nucleusR + 1.5
        let hitGeo = SCNSphere(radius: CGFloat(totalR))
        hitGeo.firstMaterial?.diffuse.contents  = UIColor.clear
        hitGeo.firstMaterial?.isDoubleSided = true
        hitGeo.firstMaterial?.lightingModel = .constant
        hitGeo.firstMaterial?.writesToDepthBuffer = false
        hitGeo.firstMaterial?.colorBufferWriteMask = []
        let hitNode = SCNNode(geometry: hitGeo)
        hitNode.name = "atomZ_hit:\(element.id)"  // also recognizable if needed
        root.addChildNode(hitNode)

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

    public func toggleAxisIndicators() {
        showAxisIndicators.toggle()
        rebuildGrid()
    }

    public func toggleGridPlane(_ plane: String) {
        switch plane {
        case "xz": showGridXZ.toggle()
        case "xy": showGridXY.toggle()
        case "yz": showGridYZ.toggle()
        default: break
        }
        rebuildGrid()
    }

    public func rebuildGrid() {
        // Remove all grid AND axis nodes before re-adding
        let gnames: Set<String> = ["grid","grid_xz","grid_xy","grid_yz","axis_origin"]
        scene.rootNode.childNodes.filter{gnames.contains($0.name ?? "")}.forEach{$0.removeFromParentNode()}
        // Always call addGridFloor — it internally checks showGrid / showAxisIndicators
        addGridFloor(to: scene)
    }

    public func exportGLB() -> URL? {
        let helper = SCNExportHelper()
        helper.recordedFrames = recordedFrames   // animation data rides in the GLB
        return helper.exportScene(scene, name: "ArcLake_Export", format: .glb)
    }
    public func exportUSDZ() -> URL? { SCNExportHelper().exportScene(scene, name:"ArcLake_Export", format: .usdz) }


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







