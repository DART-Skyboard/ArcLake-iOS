
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
    @Published public var showGrid   = true    // master
    @Published public var showGridXZ = true    // XZ floor
    @Published public var showGridXY = true    // XY wall  
    @Published public var showGridYZ = true    // YZ wall
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
        let N = 20; let step: Float = 1.5
        let ext = Float(N) * step

        func lines3D(_ pts: [(SCNVector3, SCNVector3)], name: String) -> SCNNode {
            let g = SCNNode(); g.name = name
            for (i,(a,b)) in pts.enumerated() {
                let major = i % 4 == 0
                let alpha: CGFloat = major ? 0.18 : 0.06
                let col = UIColor.cyan.withAlphaComponent(alpha)
                let dx=b.x-a.x, dy=b.y-a.y, dz=b.z-a.z
                let len = sqrt(dx*dx+dy*dy+dz*dz)
                let cyl = SCNCylinder(radius:0.006, height:CGFloat(len))
                cyl.firstMaterial?.emission.contents=col; cyl.firstMaterial?.lightingModel = .constant
                let n=SCNNode(geometry:cyl)
                n.position=SCNVector3((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
                if abs(dx)>0.001 { n.eulerAngles=SCNVector3(0,0,Float.pi/2) }
                else if abs(dz)>0.001 { n.eulerAngles=SCNVector3(Float.pi/2,0,0) }
                g.addChildNode(n)
            }
            return g
        }

        func axisLine(color: UIColor, euler: SCNVector3, ext: Float) -> SCNNode {
            let c=SCNCylinder(radius:0.016,height:CGFloat(ext*2))
            c.firstMaterial?.emission.contents=color; c.firstMaterial?.lightingModel = .constant
            let n=SCNNode(geometry:c); n.eulerAngles=euler; return n
        }

        if showGridXZ {
            var pts=[(SCNVector3,SCNVector3)]()
            for i in stride(from: -N, through: N, by: 1) {
                let o=Float(i)*step
                pts.append((SCNVector3(-ext,0,o),SCNVector3(ext,0,o)))
                pts.append((SCNVector3(o,0,-ext),SCNVector3(o,0,ext)))
            }
            let g=lines3D(pts,name:"grid_xz")
            g.addChildNode(axisLine(color:UIColor(red:1,green:0.2,blue:0.2,alpha:0.6),
                euler:SCNVector3(0,0,Float.pi/2),ext:ext))  // X red
            g.addChildNode(axisLine(color:UIColor(red:0.2,green:1,blue:0.3,alpha:0.6),
                euler:SCNVector3(0,0,0),ext:ext))            // Y green
            g.addChildNode(axisLine(color:UIColor(red:0.2,green:0.4,blue:1,alpha:0.6),
                euler:SCNVector3(Float.pi/2,0,0),ext:ext))  // Z blue
            target.rootNode.addChildNode(g)
        }
        if showGridXY {
            var pts=[(SCNVector3,SCNVector3)]()
            for i in stride(from: -N, through: N, by: 1) {
                let o=Float(i)*step
                pts.append((SCNVector3(-ext,o,0),SCNVector3(ext,o,0)))
                pts.append((SCNVector3(o,-ext,0),SCNVector3(o,ext,0)))
            }
            target.rootNode.addChildNode(lines3D(pts,name:"grid_xy"))
        }
        if showGridYZ {
            var pts=[(SCNVector3,SCNVector3)]()
            for i in stride(from: -N, through: N, by: 1) {
                let o=Float(i)*step
                pts.append((SCNVector3(0,-ext,o),SCNVector3(0,ext,o)))
                pts.append((SCNVector3(0,o,-ext),SCNVector3(0,o,ext)))
            }
            target.rootNode.addChildNode(lines3D(pts,name:"grid_yz"))
        }
    }

        public func rebuildGrid() {
        let names: Set<String> = ["grid","grid_xz","grid_xy","grid_yz"]
        scene.rootNode.childNodes.filter{names.contains($0.name ?? "")}.forEach{$0.removeFromParentNode()}
        if showGrid { addGridFloor(to: scene) }
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
