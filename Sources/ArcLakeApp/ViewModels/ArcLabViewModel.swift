
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
    public let mantis = MantisNavModel()   // Mantis Navigation engine
    public var atomVelocities: [Int: SIMD3<Float>] = [:]
    @Published public var selectedImportedNode: String? = nil
    @Published public var showGlobalImporter = false    // from Imports tab

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

    // ── Quantum orbital particle system ──────────────────────────────
    @Published public var quantumAtoms: [ArcAtomData] = []
    @Published public var isPhysicsSimulating: Bool = false
    @Published public var scrubberPosition: Int = 0
    @Published public var ptsPerElectron: Int = 30 {
        didSet { ArcQuantumAtomBuilder.ptsPerElectron = ptsPerElectron; rebuildAllAtoms() }
    }
    // Pixel size of each particle point — was engine-internal only (no UI,
    // no @Published bridge), unlike ptsPerElectron right above which already
    // had both. Bridged the same way for consistency.
    @Published public var electronPointSize: CGFloat = 0.022 {
        didSet { ArcQuantumAtomBuilder.elecPtSize = electronPointSize; rebuildAllAtoms() }
    }
    @Published public var nucleonPointSize: CGFloat = 0.018 {
        didSet { ArcQuantumAtomBuilder.nucPtSize = nucleonPointSize; rebuildAllAtoms() }
    }
    private var physEngine = ArcQuantumPhysics.shared

    // Engine extension (separate file) needs atom node access
    public func atomNode(for id: Int) -> SCNNode? { atomNodes[id] }
    @Published public var isNodeEditorVisible = false
    @Published public var tappedCFDComponent: String? = nil  // triggers component config sheet

    // ── Node Editor per-tab persistence ──────────────────────────────
    // These dicts survive sheet dismissal/reopening because they live on the VM.
    // NodeEditorView reads/writes these directly instead of @State.
    @Published public var nodeTabNodes:       [Int: [Any]] = [:]
    @Published public var nodeTabConnections: [Int: [Any]] = [:]
    @Published public var nodeTabGroups:      [Int: [Any]] = [:]
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
        var atomPhysics: [Int: ArcAtomPhysics]
        var isCFDActive: Bool
        init() {
            scene = SCNScene()
            elements = []
            atomNodes = [:]
            atomPositions = [:]
            atomPhysics = [:]
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
    // Six-input physics (mass/volume/weight/density/temperature/velocity) —
    // keyed the same way as atomPositions (element.id, or element.id +
    // instanceIdx*1000 for repeated instances of the same element), since
    // ArcElement.id is the atomic number, not a per-instance identity.
    public var atomPhysics: [Int: ArcAtomPhysics] {
        get { tabStates[safe: activeTabIndex]?.atomPhysics ?? [:] }
        set { if activeTabIndex < tabStates.count { tabStates[activeTabIndex].atomPhysics = newValue } }
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
        // Use the actual current default background (gradient/color/
        // environment, whatever the theme/render settings say) instead of a
        // hardcoded flat color — this hardcoded line is why a brand new
        // scene tab showed the old flat dark background instead of the
        // blue gradient every other scene has.
        ArcRenderViewModel.shared.applyBackground(to: s)
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
        atomPhysics[element.id] = ArcAtomPhysics(
            element: element, gravityMS2: physics.gravity, temperatureK: physics.activeTab.ambientTempK)
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
        let key = element.id + instanceIdx * 1000
        atomPositions[key] = pos
        atomPhysics[key] = ArcAtomPhysics(
            element: element, gravityMS2: physics.gravity, temperatureK: physics.activeTab.ambientTempK)
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
        // Ensure the live SCNView is attached to this scene — it may not be
        // yet on first launch (before any Mantis Nav call triggers makeUIView).
        // Setting scene = scene re-triggers the view's scene assignment.
        if let sv = ArcRenderViewModel.shared.sceneView, sv.scene !== scene {
            sv.scene = scene
        }
    }

    /// All SCNScene instances across every tab — used by Mantis Navigation
    /// to discover imported assets regardless of which tab is currently active.
    public func allTabScenes() -> [SCNScene] {
        tabStates.map { $0.scene }
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
        // Keep per-tab environment physics in sync with the active scene tab
        physics.activeTabIndex = index

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

    // MARK: — Quantum physics simulation (web app applyNewPhysics parity)
    public func startPhysicsSimulation() {
        guard !isPhysicsSimulating else { return }
        isPhysicsSimulating = true; isPlaying = true; isRecording = true
        physEngine.isSimulating = true
        physEngine.gravity = Float(physics.gravity)
        physEngine.clearRecording()
        recordedFrameCount = 0; recordedFrames = []
        for i in quantumAtoms.indices {
            let imp: Float = 0.00005
            quantumAtoms[i].velocity = SIMD3<Float>(
                Float.random(in: -imp...imp),
                Float.random(in: -imp*0.5...imp*0.5),
                Float.random(in: -imp...imp))
            quantumAtoms[i].devWarmup = 0
            quantumAtoms[i].isActive = true
        }
        // Pass current scene physics to quantum engine
        physEngine.gravity         = Float(physics.gravity)
        physEngine.startEnvTempF   = Float(physics.temperature)
        physEngine.startEnvPressure = Float(physics.pressure)
        displayLink = CADisplayLink(target: self, selector: #selector(physicsDisplayLinkTick))
        displayLink?.add(to: .main, forMode: .common)
        log("Physics simulation started — LEATR neutron-first propagation")
    }

    public func stopPhysicsSimulation() {
        isPhysicsSimulating = false; isPlaying = false; isRecording = false
        physEngine.isSimulating = false
        displayLink?.invalidate(); displayLink = nil
        resetQuantumAtomPositions()
        recordedFrameCount = physEngine.frames.count
        log("Simulation stopped — \(recordedFrameCount) frames")
    }

    // Algebra Menu -> Quantum Engine bridge. An equation node's Delta or
    // Math-Operator sockets, when bound to an element that's actually placed
    // in the scene, contribute a small additive nudge to that element's
    // proton-bridge angle (see ArcQuantumEngine.tick). Scoped honestly: this
    // matches by ELEMENT SYMBOL, not a specific placed instance, so if
    // several atoms of the same element are in the scene (e.g. multiple
    // oxygens), an equation bound to "O" nudges all of them together —
    // full per-instance targeting would need equation nodes to carry a
    // specific instance key rather than just a symbol, which is a
    // reasonable next step but not this one.
    private func computeAlgebraModulation(forElementSymbol symbol: String) -> Float {
        var total: Float = 0
        for node in equationNodes {
            guard node.boundElementSymbol == symbol else { continue }
            for socket in node.outgoingSockets + node.incomingSockets {
                switch socket.kind {
                case .delta:
                    if let did = socket.linkedDeltaId, let d = deltaConnections.first(where: { $0.id == did }) {
                        let shellTerm = Float(d.toShell - d.fromShell) * 0.05
                        total += (d.operator_ == "-") ? -shellTerm : shellTerm
                    }
                case .mathOperator:
                    if let did = socket.linkedDeltaId, let d = deltaConnections.first(where: { $0.id == did }) {
                        total += (d.operator_ == "+") ? 0.02 : (d.operator_ == "-") ? -0.02 : 0
                    }
                default: break
                }
            }
        }
        return total
    }

    @objc private func physicsDisplayLinkTick() {
        guard isPhysicsSimulating else { return }
        // Apply any Algebra Menu modulation before advancing physics.
        for i in quantumAtoms.indices {
            let elementId = quantumAtoms[i].elementId
            if let symbol = selectedElements.first(where: { $0.id == elementId })?.elementSymbol {
                quantumAtoms[i].algebraModulation = computeAlgebraModulation(forElementSymbol: symbol)
            }
        }
        physEngine.tick(atoms: &quantumAtoms, dt: 0.016,
                        envTempF:      physEngine.startEnvTempF,
                        envGravity:    physEngine.gravity,
                        envPressurePsi: physEngine.startEnvPressure,
                        envWindMS:     Float(windVelocity))
        physEngine.captureFrame(atoms: quantumAtoms)
        recordedFrameCount = physEngine.frames.count
        playheadFrame = recordedFrameCount
    }

    private func resetQuantumAtomPositions() {
        for i in quantumAtoms.indices {
            let idx = i
            let el = selectedElements.first(where: { $0.id == quantumAtoms[idx].elementId })
            let pos = el.map { physicsPosition(for: $0, index: idx) } ?? SIMD3<Float>(Float(idx)*2, 0.6, 0)
            quantumAtoms[i].root.position = SCNVector3(pos.x, pos.y, pos.z)
            quantumAtoms[i].velocity = .zero
            quantumAtoms[i].devWarmup = 0
        }
    }

    public func scrubToFrame(_ frameIndex: Int) {
        physEngine.isScrubbing = true
        scrubberPosition = max(0, min(frameIndex, physEngine.frames.count - 1))
        physEngine.applyFrame(scrubberPosition, atoms: &quantumAtoms)
        playheadFrame = scrubberPosition
    }

    public func endScrubbing() { physEngine.isScrubbing = false }

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
        // Atoms spawn at their natural scene position above the floor.
        // The LEATR tick floor is at y=0.6 — candidate must be >= 0.6.
        // Higher gravity makes atoms sit slightly lower; higher temp raises them.
        let gravityOffset = -gravity * 0.02   // gentle pull, not extreme
        let tempLift      = (temp - 72.0) * 0.005   // warmer = slightly elevated
        candidate.y = max(0.6, candidate.y + gravityOffset + tempLift)
        // Higher pressure compresses the arrangement
        let pressureFactor = max(0.3, 1.0 - pressure * 0.005)
        // Scene-density term — as the number of placed atoms grows toward
        // many-molecule scale (hundreds to a thousand), packing tightens
        // further on top of the environment's own pressure setting, so
        // scaling up a molecule count reads as increasing density rather
        // than atoms endlessly spreading outward at a fixed spacing.
        let sceneCount = Float(selectedElements.count)
        let densityFactor = max(0.35, 1.0 - min(sceneCount, 1000) * 0.0004)
        candidate.x *= pressureFactor * densityFactor
        candidate.z *= pressureFactor * densityFactor
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
        // True 3D distribution. The previous version hardcoded Y to 0 for
        // EVERY atom — combined with physicsPosition's floor clamp
        // (candidate.y = max(0.6, ...)) downstream, every atom landed at
        // the exact same Y height: a perfectly flat plane, matching the
        // reported "physics only plays on a plane" bug precisely. This
        // spreads atoms across a real 3D volume, biased upward (not
        // symmetric around zero) so the floor clamp doesn't flatten half
        // of them straight back down to the same height.
        let goldenAngle: Float = .pi * (3.0 - sqrt(5.0))  // ≈2.399 rad — same constant already used for electron/point-cluster placement elsewhere in this codebase
        let i = Float(index)
        let radius = sqrt(i) * spacing * 0.7
        let azimuth = i * goldenAngle
        // Elevation cycles as index grows, scaled by radius, so atoms fan
        // out vertically as well as outward — further-out atoms also get
        // more vertical spread, nearer ones stay closer to the floor.
        let elevationUnit = i.truncatingRemainder(dividingBy: 23) / 23   // 0..<1, cycles
        let y = elevationUnit * radius * 0.9
        return SIMD3<Float>(cos(azimuth) * radius, y, sin(azimuth) * radius)
    }

    // MARK: — Point cloud atom builder
    // Each component (proton/neutron/electron) gets ptsPerComponent particles
    // ── Quantum atom builder — replaces legacy SCNTorus + sphere animation ──
    // Matches web app: ψ_nlm CDF orbital clouds, no preset animation,
    // physics driven by element data (Aufbau, Slater Zeff, shell wave propagation)
    private func buildPointCloudAtom(_ element: ArcElement, at position: SIMD3<Float>) {
        // Remove existing atom with this Z if present
        atomNodes[element.id]?.removeFromParentNode()
        if let idx = quantumAtoms.firstIndex(where: { $0.elementId == element.id }) {
            quantumAtoms.remove(at: idx)
        }

        ArcQuantumAtomBuilder.ptsPerElectron = ptsPerElectron
        let atomData = ArcQuantumAtomBuilder.build(element: element, at: position, scene: scene)
        quantumAtoms.append(atomData)
        atomNodes[element.id] = atomData.root
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

    // MARK: — Equation Node Graph (Algebra Menu ⇄ Node Editor ⇄ Molecule Canvas)
    // Single source of truth shared by all three UIs, and by Autumn (she
    // already receives `labVM` directly — see AutumnViewModel.processIntent).
    // Nothing here is view-local state.
    @Published public var equationNodes: [EquationNode] = []
    @Published public var equationConnections: [EquationConnection] = []

    @discardableResult
    public func addEquationNode(title: String, role: EquationNodeRole = .algebra,
                                 position: CGPoint? = nil,
                                 boundAtomId: UUID? = nil,
                                 boundElementSymbol: String? = nil) -> EquationNode {
        // Stagger new nodes instead of stacking every one at the same fixed
        // point — a simple diagonal cascade that wraps, cheap and always
        // keeps a fresh node visible and separable from earlier ones.
        let autoPosition: CGPoint = {
            let n = equationNodes.count
            let col = n % 5, row = n / 5
            return CGPoint(x: 140 + CGFloat(col) * 170, y: 120 + CGFloat(row) * 140)
        }()
        var node = EquationNode(title: title, position: position ?? autoPosition, role: role)
        node.boundAtomId = boundAtomId
        node.boundElementSymbol = boundElementSymbol

        // Element Selection socket — bound either to a specific Molecule
        // Canvas atom instance (linkedAtomId) or directly to a scene element
        // by symbol (boundElementSymbol), which is the primary path: "one
        // node pertains to one element" doesn't require ever touching the
        // Molecule Canvas.
        if boundAtomId != nil || boundElementSymbol != nil {
            var s = EquationSocket(kind: .elementSelection, direction: .incoming)
            if let atomId = boundAtomId, molAtoms.contains(where: { $0.id == atomId }) {
                s.linkedAtomId = atomId
            } else if let symbol = boundElementSymbol {
                s.localValue = symbol
            }
            node.incomingSockets.append(s)
        }

        // Bond + Delta are always present on a new node (outgoing) — these
        // are the attributes that connect to the Molecule Canvas, and
        // shouldn't require remembering to manually "+" them in every time.
        node.outgoingSockets.append(EquationSocket(kind: .bond, direction: .outgoing))
        node.outgoingSockets.append(EquationSocket(kind: .delta, direction: .outgoing))

        equationNodes.append(node)
        log("Algebra: built equation node \"\(title)\"")
        return node
    }

    public func removeEquationNode(_ id: UUID) {
        equationNodes.removeAll { $0.id == id }
        equationConnections.removeAll { $0.fromNodeId == id || $0.toNodeId == id }
    }

    @discardableResult
    public func addEquationSocket(to nodeId: UUID, kind: EquationSocketKind,
                                   direction: EquationSocketDirection, label: String? = nil) -> UUID? {
        guard let idx = equationNodes.firstIndex(where: { $0.id == nodeId }) else { return nil }
        var socket = EquationSocket(kind: kind, direction: direction, label: label)
        // Bond/Delta/Orbit/Operator sockets on a node bound to an atom default
        // to whatever real bond/delta already connects that atom, if one
        // exists, rather than starting detached from real data.
        if let atomId = equationNodes[idx].boundAtomId {
            switch kind {
            case .bond:
                if let b = molBonds.first(where: { $0.fromId == atomId || $0.toId == atomId }) {
                    socket.linkedBondId = b.id
                }
            case .delta, .orbitShell, .mathOperator:
                if let d = deltaConnections.first(where: { $0.fromAtomId == atomId || $0.toAtomId == atomId }) {
                    socket.linkedDeltaId = d.id
                }
            default: break
            }
        }
        if direction == .incoming { equationNodes[idx].incomingSockets.append(socket) }
        else { equationNodes[idx].outgoingSockets.append(socket) }
        return socket.id
    }

    public func removeEquationSocket(_ socketId: UUID, from nodeId: UUID) {
        guard let idx = equationNodes.firstIndex(where: { $0.id == nodeId }) else { return }
        equationNodes[idx].incomingSockets.removeAll { $0.id == socketId }
        equationNodes[idx].outgoingSockets.removeAll { $0.id == socketId }
        equationConnections.removeAll { $0.fromSocketId == socketId || $0.toSocketId == socketId }
    }

    /// Curve connection between two sockets, drawn in the Node Editor. If both
    /// ends belong to atom-bound nodes and are bond/delta-kind sockets, this
    /// also creates (or links to) the matching real MolBond/DeltaConnection —
    /// so wiring a curve in the Node Editor is enough to actually bond the
    /// atoms on the Molecule Canvas, not just a visual note.
    @discardableResult
    public func connectEquationSockets(fromNode: UUID, fromSocket: UUID,
                                        toNode: UUID, toSocket: UUID, isDelta: Bool = false) -> EquationConnection {
        let conn = EquationConnection(fromNodeId: fromNode, fromSocketId: fromSocket,
                                       toNodeId: toNode, toSocketId: toSocket, isDelta: isDelta)
        equationConnections.append(conn)
        materializeCanvasLink(for: conn)
        return conn
    }

    public func disconnectEquationSockets(_ connectionId: UUID) {
        equationConnections.removeAll { $0.id == connectionId }
    }

    private func materializeCanvasLink(for conn: EquationConnection) {
        guard let fromNode = equationNodes.first(where: { $0.id == conn.fromNodeId }),
              let toNode   = equationNodes.first(where: { $0.id == conn.toNodeId }),
              let fromAtom = fromNode.boundAtomId, let toAtom = toNode.boundAtomId,
              fromAtom != toAtom else { return }
        let fromSock = (fromNode.outgoingSockets + fromNode.incomingSockets).first(where: { $0.id == conn.fromSocketId })
        let toSock   = (toNode.outgoingSockets + toNode.incomingSockets).first(where: { $0.id == conn.toSocketId })
        guard let kind = fromSock?.kind ?? toSock?.kind else { return }

        switch kind {
        case .bond:
            if !molBonds.contains(where: { ($0.fromId==fromAtom && $0.toId==toAtom) || ($0.fromId==toAtom && $0.toId==fromAtom) }) {
                addMolBond(from: fromAtom, to: toAtom)
            }
        case .delta, .orbitShell, .mathOperator:
            if !deltaConnections.contains(where: {
                ($0.fromAtomId==fromAtom && $0.toAtomId==toAtom) || ($0.fromAtomId==toAtom && $0.toAtomId==fromAtom)
            }) {
                addDeltaConnection(from: fromAtom, to: toAtom, fromShell: 0, toShell: 0, op: "+")
            }
        default: break
        }
    }

    /// The read half of "sockets are live pointers, not copies" — always
    /// looks the value up fresh rather than trusting anything cached on the
    /// socket itself, so a change made anywhere (canvas, node editor,
    /// algebra menu, or Autumn) is visible everywhere immediately.
    public func socketDisplayValue(_ socket: EquationSocket) -> String {
        switch socket.kind {
        case .elementSelection:
            // Molecule Canvas atom binding takes priority if present, else
            // fall back to a plain scene-element symbol (localValue).
            if let id = socket.linkedAtomId, let a = molAtoms.first(where: { $0.id == id }) { return a.symbol }
            return socket.localValue.isEmpty ? "—" : socket.localValue
        case .bond:
            if let id = socket.linkedBondId, let b = molBonds.first(where: { $0.id == id }) { return "\(b.order)×" }
            return socket.localValue.isEmpty ? "—" : socket.localValue
        case .delta:
            if let id = socket.linkedDeltaId, let d = deltaConnections.first(where: { $0.id == id }) { return d.label }
            return socket.localValue.isEmpty ? "—" : socket.localValue
        case .orbitShell:
            let names = ["K","L","M","N","O","P","Q"]
            if let id = socket.linkedDeltaId, let d = deltaConnections.first(where: { $0.id == id }) {
                let shell = socket.direction == .incoming ? d.fromShell : d.toShell
                return shell < names.count ? names[shell] : "?"
            }
            return socket.localValue.isEmpty ? "—" : socket.localValue
        case .mathOperator:
            if let id = socket.linkedDeltaId, let d = deltaConnections.first(where: { $0.id == id }) { return d.operator_ }
            return socket.localValue.isEmpty ? "N/A" : socket.localValue
        case .elementComponent:
            return socket.localValue.isEmpty ? "—" : socket.localValue
        case .physicsAttribute:
            return socket.localValue.isEmpty ? "mass" : socket.localValue
        case .physicsValue:
            // Unit-aware: matches whichever physicsAttribute socket sits on
            // the same node, so "mass" shows "u", "volume" shows "Å³", etc —
            // the same units ArcAtomPhysics itself uses.
            let attr = physicsAttributeSibling(of: socket)
            let unit: String
            switch attr {
            case "volume":      unit = "Å³"
            case "weight":      unit = "N"
            case "density":     unit = "kg/m³"
            case "temperature": unit = "K"
            case "velocity":    unit = "m/s"
            default:            unit = "u"   // mass
            }
            return String(format: "%.3g %@", socket.doubleValue, unit)
        }
    }

    /// Finds the physicsAttribute socket on the same node as `value` (a
    /// physicsValue socket), so the value's display can show the right unit
    /// for whichever attribute it's paired with.
    private func physicsAttributeSibling(of value: EquationSocket) -> String {
        for node in equationNodes {
            let all = node.incomingSockets + node.outgoingSockets
            guard all.contains(where: { $0.id == value.id }) else { continue }
            if let attr = all.first(where: { $0.kind == .physicsAttribute }) {
                return attr.localValue.isEmpty ? "mass" : attr.localValue
            }
        }
        return "mass"
    }

    /// Whether a given socket currently has any curve connection touching
    /// it — drives the empty-vs-filled circle in the Node Editor.
    public func isEquationSocketConnected(_ socketId: UUID) -> Bool {
        equationConnections.contains { $0.fromSocketId == socketId || $0.toSocketId == socketId }
    }

    /// The write half — edits made in the Algebra Menu or Node Editor go
    /// through here so they land on the real molBonds/deltaConnections entry
    /// (or, for a not-yet-linked socket, the local fallback).
    public func setEquationSocketValue(_ socketId: UUID, onNode nodeId: UUID, to newValue: String) {
        guard let nIdx = equationNodes.firstIndex(where: { $0.id == nodeId }) else { return }

        func apply(_ socket: inout EquationSocket) {
            switch socket.kind {
            case .bond:
                if let bid = socket.linkedBondId, let bIdx = molBonds.firstIndex(where: { $0.id == bid }) {
                    molBonds[bIdx].order = max(1, min(3, Int(newValue) ?? molBonds[bIdx].order))
                } else { socket.localValue = newValue }
            case .mathOperator:
                if let did = socket.linkedDeltaId, let dIdx = deltaConnections.firstIndex(where: { $0.id == did }) {
                    deltaConnections[dIdx].operator_ = newValue
                } else { socket.localValue = newValue }
            case .orbitShell:
                let names = ["K","L","M","N","O","P","Q"]
                if let did = socket.linkedDeltaId, let dIdx = deltaConnections.firstIndex(where: { $0.id == did }),
                   let shellIdx = names.firstIndex(of: newValue) {
                    if socket.direction == .incoming { deltaConnections[dIdx].fromShell = shellIdx }
                    else { deltaConnections[dIdx].toShell = shellIdx }
                } else { socket.localValue = newValue }
            case .physicsValue:
                // Numeric, not text — parse into doubleValue, which is what
                // socketDisplayValue actually reads for this kind.
                socket.doubleValue = Double(newValue) ?? socket.doubleValue
            default:
                socket.localValue = newValue
            }
        }
        if let i = equationNodes[nIdx].incomingSockets.firstIndex(where: { $0.id == socketId }) {
            apply(&equationNodes[nIdx].incomingSockets[i])
        } else if let i = equationNodes[nIdx].outgoingSockets.firstIndex(where: { $0.id == socketId }) {
            apply(&equationNodes[nIdx].outgoingSockets[i])
        }
    }

    /// Order-of-operations evaluation order — Neutron (origin) first, then
    /// Proton (must resolve Radian/Gas-Liquid-Solid state via angle/degree
    /// congruency before anything downstream evaluates), then Algebra
    /// (propagates outward from the Neutron once Proton has resolved),
    /// then outermost parentheses Group nodes last.
    /// Nests a node inside a .group-role node's outer parentheses — or
    /// clears it (pass nil) to un-nest. This is the "Most Outer Parentheses
    /// Math Operator Group Nest" concept from the equation-node spec: a
    /// group node doesn't compute anything itself, it just gives its
    /// children a shared visual boundary and a place for a global label.
    /// Duplicate an equation node in place (small offset so it's visibly
    /// distinct) — same role, same element/atom binding, same sockets
    /// (fresh ids so they're independent), but NO copied connections, since
    /// the whole point is making new, independent socket connections on the
    /// copy rather than inheriting the original's wiring.
    @discardableResult
    public func duplicateEquationNode(_ nodeId: UUID) -> EquationNode? {
        guard let original = equationNodes.first(where: { $0.id == nodeId }) else { return nil }
        var copy = EquationNode(title: original.title + " copy",
                                 position: CGPoint(x: original.position.x + 40, y: original.position.y + 40),
                                 role: original.role)
        copy.boundAtomId = original.boundAtomId
        copy.boundElementSymbol = original.boundElementSymbol
        copy.parentGroupId = original.parentGroupId
        copy.incomingSockets = original.incomingSockets.map { old in
            var s = EquationSocket(kind: old.kind, direction: old.direction, label: old.label)
            s.linkedAtomId = old.linkedAtomId; s.linkedBondId = old.linkedBondId
            s.linkedDeltaId = old.linkedDeltaId; s.localValue = old.localValue
            return s
        }
        copy.outgoingSockets = original.outgoingSockets.map { old in
            var s = EquationSocket(kind: old.kind, direction: old.direction, label: old.label)
            s.linkedAtomId = old.linkedAtomId; s.linkedBondId = old.linkedBondId
            s.linkedDeltaId = old.linkedDeltaId; s.localValue = old.localValue
            return s
        }
        equationNodes.append(copy)
        log("Duplicated equation node \"\(original.title)\"")
        return copy
    }

    public func setEquationParentGroup(_ nodeId: UUID, to groupId: UUID?) {
        guard let idx = equationNodes.firstIndex(where: { $0.id == nodeId }) else { return }
        equationNodes[idx].parentGroupId = groupId
    }

    public func childNodes(ofGroup groupId: UUID) -> [EquationNode] {
        equationNodes.filter { $0.parentGroupId == groupId }
    }

    public func equationEvaluationOrder() -> [EquationNode] {
        let byRole: (EquationNodeRole) -> [EquationNode] = { role in
            self.equationNodes.filter { $0.role == role }
        }
        return byRole(.neutron) + byRole(.proton) + byRole(.algebra) + byRole(.group)
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
    case imports="Imports", render="Render", fluid="Fluid"
    var icon: String {
        switch self {
        case .molecule: return "atom"
        case .physics:  return "waveform.path"
        case .math:     return "function"
        case .arc:      return "circle.and.line.horizontal"
        case .env:      return "cloud.fill"
        case .log:      return "list.bullet"
        case .imports:  return "square.and.arrow.down"
        case .render:   return "scope"
        case .fluid:    return "water.waves"
        }
    }
}
public enum SceneMode { case atomic, cfd, mol2D }











// Array[safe:] subscript defined in ArcHorizonsEngine.swift









