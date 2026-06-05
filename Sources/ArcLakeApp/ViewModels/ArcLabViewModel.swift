
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
    @Published public var molCanvasPendingElement: ArcElement? = nil
    @Published public var cfdParticles: [SPHEngine.Particle] = []
    @Published public var alloyComponents: [AlloyComponent] = []

    // ── Particle resolution — pts per component (proton/neutron/electron)
    // Default 30, user-adjustable in Physics tab
    @Published public var ptsPerComponent: Int = 30
    @Published public var isNodeEditorVisible = false
    @Published public var showGrid    = true   // master toggle
    @Published public var showGridXZ  = true   // floor plane (horizontal)
    @Published public var showGridXY  = true   // front wall (vertical, facing Z)
    @Published public var showGridYZ  = true   // side wall (vertical, facing X)
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
        let gridSize: Int = 20
        let step: Float   = 1.5
        let extent: Float = Float(gridSize) * step

        func makePlane(name: String, lines: [(SCNVector3, SCNVector3)],
                       axisColors: (SCNVector3, SCNVector3, SCNVector3)?) -> SCNNode {
            let planeNode = SCNNode(); planeNode.name = name
            let lineR: CGFloat = 0.006

            for (i, (start, end)) in lines.enumerated() {
                let isMajor = i % 4 == 0
                let alpha: CGFloat = isMajor ? 0.18 : 0.06
                let col = UIColor.cyan.withAlphaComponent(alpha)
                let dx = end.x - start.x, dy = end.y - start.y, dz = end.z - start.z
                let length = sqrt(dx*dx + dy*dy + dz*dz)
                let cyl = SCNCylinder(radius: lineR, height: CGFloat(length))
                cyl.firstMaterial?.diffuse.contents = col
                cyl.firstMaterial?.emission.contents = col
                cyl.firstMaterial?.lightingModel = .constant
                let n = SCNNode(geometry: cyl)
                n.position = SCNVector3((start.x+end.x)/2,(start.y+end.y)/2,(start.z+end.z)/2)
                if abs(dx) > 0.001 { n.eulerAngles = SCNVector3(0, 0, Float.pi/2) }
                else if abs(dz) > 0.001 { n.eulerAngles = SCNVector3(Float.pi/2, 0, 0) }
                planeNode.addChildNode(n)
            }
            // Axis lines
            if let (xColor, yColor, zColor) = axisColors {
                func axis(_ color: SCNVector3, _ e: SCNVector3) -> SCNNode {
                    let c = SCNCylinder(radius: 0.016, height: CGFloat(extent*2))
                    c.firstMaterial?.emission.contents = UIColor(red:CGFloat(color.x),green:CGFloat(color.y),blue:CGFloat(color.z),alpha:0.6)
                    c.firstMaterial?.lightingModel = .constant
                    let n = SCNNode(geometry: c)
                    if e.x > 0 { n.eulerAngles = SCNVector3(0,0,Float.pi/2) }
                    else if e.z > 0 { n.eulerAngles = SCNVector3(Float.pi/2,0,0) }
                    return n
                }
                planeNode.addChildNode(axis(SCNVector3(1,0.2,0.2), SCNVector3(1,0,0))) // X red
                planeNode.addChildNode(axis(SCNVector3(0.2,1,0.3), SCNVector3(0,1,0))) // Y green
                planeNode.addChildNode(axis(SCNVector3(0.2,0.4,1), SCNVector3(0,0,1))) // Z blue
            }
            return planeNode
        }

        // XZ floor plane — horizontal grid at y=0
        if showGridXZ {
            var lines = [(SCNVector3, SCNVector3)]()
            for i in stride(from: -gridSize, through: gridSize, by: 1) {
                let o = Float(i) * step
                lines.append((SCNVector3(-extent,0,o), SCNVector3(extent,0,o)))  // rows
                lines.append((SCNVector3(o,0,-extent), SCNVector3(o,0,extent)))  // cols
            }
            let plane = makePlane(name: "grid_xz", lines: lines,
                axisColors: (SCNVector3(1,0.2,0.2), SCNVector3(0.2,1,0.3), SCNVector3(0.2,0.4,1)))
            target.rootNode.addChildNode(plane)
        }

        // XY wall plane — vertical grid facing Z at z=0
        if showGridXY {
            var lines = [(SCNVector3, SCNVector3)]()
            for i in stride(from: -gridSize, through: gridSize, by: 1) {
                let o = Float(i) * step
                lines.append((SCNVector3(-extent,o,0), SCNVector3(extent,o,0)))  // horizontal
                lines.append((SCNVector3(o,-extent,0), SCNVector3(o,extent,0)))  // vertical
            }
            let plane = makePlane(name: "grid_xy", lines: lines, axisColors: nil)
            target.rootNode.addChildNode(plane)
        }

        // YZ wall plane — vertical grid facing X at x=0
        if showGridYZ {
            var lines = [(SCNVector3, SCNVector3)]()
            for i in stride(from: -gridSize, through: gridSize, by: 1) {
                let o = Float(i) * step
                lines.append((SCNVector3(0,-extent,o), SCNVector3(0,extent,o)))   // vertical
                lines.append((SCNVector3(0,o,-extent), SCNVector3(0,o,extent)))   // depth
            }
            let plane = makePlane(name: "grid_yz", lines: lines, axisColors: nil)
            target.rootNode.addChildNode(plane)
        }
    }

        public func rebuildGrid() {
        scene.rootNode.childNodes
            .filter{["grid","grid_xz","grid_xy","grid_yz","grid_floor"].contains($0.name ?? "")}
            .forEach{$0.removeFromParentNode()}
        if showGrid { addGridFloor(to: scene) }
    }
    
    // MARK: — Scene Tabs
    public func addSceneTab() {
        let name = "Scene \(tabStates.count + 1)"
        tabStates.append(TabState())
        tabStates[tabStates.count-1].name = name
        sceneTabsCFD.append(false)
        activeTabIndex = tabStates.count - 1
    }

    public func removeSceneTab(at index: Int) {
        guard tabStates.count > 1, index < tabStates.count else { return }
        tabStates.remove(at: index)
        if index < sceneTabsCFD.count { sceneTabsCFD.remove(at: index) }
        activeTabIndex = max(0, min(activeTabIndex, tabStates.count - 1))
    }

    // MARK: — 3D Asset Import
    public func importAssetNode(_ node: SCNNode) {
        scene.rootNode.addChildNode(node)
        log("Imported asset: \(node.name ?? "model")")
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
