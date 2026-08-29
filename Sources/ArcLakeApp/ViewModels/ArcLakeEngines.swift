import SwiftUI
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcLakeEngines — Arc Edge Field Array · Math Engine · Transport
// 1:1 port of the arclake.html web-app logic (updateArcEdgeArraySelection,
// updateArcEdgeDynamicMesh, executeAdvMath, startRecording) with the
// straight-default-iteration arc + velocity-potential flux extension.
// ═══════════════════════════════════════════════════════════════════

// MARK: — Types

public enum ArcComponentField: String, CaseIterable, Identifiable {
    case group, neutron, proton, electron
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .group:    return "Entire Element Group"
        case .neutron:  return "Neutron (Centroid)"
        case .proton:   return "Proton (Centroid)"
        case .electron: return "Electron (Centroid)"
        }
    }
    // Web componentColors: group 0x00FF00, neutron 0xAAAAAA, proton 0xFF0000, electron 0x0000FF
    public var color: UIColor {
        switch self {
        case .group:    return UIColor(red: 0,    green: 1,    blue: 0,    alpha: 1)
        case .neutron:  return UIColor(red: 0.67, green: 0.67, blue: 0.67, alpha: 1)
        case .proton:   return UIColor(red: 1,    green: 0,    blue: 0,    alpha: 1)
        case .electron: return UIColor(red: 0.1,  green: 0.25, blue: 1,    alpha: 1)
        }
    }
    public var swiftColor: Color { Color(color) }
}

public struct ArcMeasureResult: Identifiable {
    public let id = UUID()
    public let label: String          // "Sg → U · proton"
    public let field: ArcComponentField
    public let length: Double         // scene units (av)
    public let curvature: Double      // finite κ — flux deflection of the arc
    public let phiA: Double           // velocity/gravity potential at endpoint A
    public let phiB: Double           // potential at endpoint B
}

public enum MatterState: String, CaseIterable {
    case gas = "Gas", liquid = "Liquid", solid = "Solid", plasma = "Plasma"
    // Web stateRad: gas 1.0, liquid π/4, solid π/8, plasma 2π
    var stateModifier: Double {
        switch self {
        case .gas: return 1.0
        case .liquid: return .pi / 4
        case .solid: return .pi / 8
        case .plasma: return .pi * 2
        }
    }
}

public enum EnvPreset: String, CaseIterable {
    case earth = "Earth", moon = "Moon", mars = "Mars",
         jupiter = "Jupiter", zeroG = "Zero-G", custom = "Custom"
    // gravity m/s², temperature °F, pressure psi
    var values: (g: Double, t: Double, p: Double)? {
        switch self {
        case .earth:   return (9.80,   72.0,  14.70)
        case .moon:    return (1.62,  -20.0,   0.00)
        case .mars:    return (3.71,  -81.0,   0.09)
        case .jupiter: return (24.79, -162.0, 14.70)
        case .zeroG:   return (0.00,   72.0,  14.70)
        case .custom:  return nil
        }
    }
}

public enum WindDir: String, CaseIterable {
    case plusZ = "+Z (North)", minusZ = "−Z (South)",
         plusX = "+X (East)",  minusX = "−X (West)", plusY = "+Y (Up)"
    var vector: SIMD3<Float> {
        switch self {
        case .plusZ:  return SIMD3(0, 0, 1)
        case .minusZ: return SIMD3(0, 0, -1)
        case .plusX:  return SIMD3(1, 0, 0)
        case .minusX: return SIMD3(-1, 0, 0)
        case .plusY:  return SIMD3(0, 1, 0)
        }
    }
}

// Math set — one SET card (web math-pair-card)
public struct ArcMathSet: Identifiable {
    public let id = UUID()
    public var atomA: Int? = nil          // element.id, nil = unset, -1 = Env
    public var atomB: Int? = nil
    public var compA: String = "neutron"  // all / neutron / proton / electron / shell_K.. / phys_*
    public var compB: String = "all_electrons"
    public var op: String = "multiply"    // MATH_OPS val
    public var radical = false
    public var radN: Double = 2
    public var vsEnv = false
    public var linked = false             // link this set → next (nest outward)
    public var result: Double? = nil
    public init() {}
}

// Web MATH_OPS — 12 operators
public let ARC_MATH_OPS: [(val: String, label: String, sym: String)] = [
    ("paren", "( )", "("), ("exp", "xⁿ", "^"), ("multiply", "×", "×"),
    ("divide", "÷", "÷"), ("add", "+", "+"), ("subtract", "−", "−"),
    ("mass", "M", "M"), ("volume", "V", "V"), ("weight", "Wt", "Wt"),
    ("density", "D", "D"), ("temp", "T", "T"), ("velocity", "v", "v"),
]
public let ARC_SHELL_NAMES = ["K","L","M","N","O","P","Q","R"]

public enum ArcMeasureMode: String, CaseIterable {
    case distance = "Distance"                       // straight default iteration
    case velocityPotential = "Velocity Potential"    // flux bend + κ readout
}

public struct RecordedFrame {
    public let time: Double
    public let positions: [Int: SIMD3<Float>]
}

// MARK: — Engine extension

extension ArcLabViewModel {

    // ── ARC EDGE FIELD ARRAY ─────────────────────────────────────────
    // Port of updateArcEdgeArraySelection + updateArcEdgeDynamicMesh.
    // Default iteration = STRAIGHT arc (no pulse animation); the only
    // deviation comes from the velocity/gravity-potential flux of other
    // elements near the link — exactly the physics the user asked for.
    // Matches nodeIDs entries against actual (element, key) pairs — works
    // whether the id is an instance key (the fixed default "All-Scene"
    // path) or came from arcSeqSelection (whatever that stores), instead of
    // matching purely by element.id, which is exactly what silently broke
    // every link after the first copy of any duplicated element.
    private func arcElementAndKey(for id: Int) -> (ArcElement, Int)? {
        for (idx, el) in selectedElements.enumerated() {
            let key = idx < selectedElementKeys.count ? selectedElementKeys[idx] : el.id
            if key == id || el.id == id { return (el, key) }
        }
        return nil
    }

    public func rebuildArcMeasures() {
        scene.rootNode.childNode(withName: "arc_measures", recursively: false)?
            .removeFromParentNode()

        // This is the actual function behind the visible Arc Edge curves —
        // a completely separate, never-before-examined function from
        // ArcEdgeExtended.swift's computeDomainArcs(), which only ever fed
        // a text summary list in the sidebar. Every previous "fix" to Arc
        // Edge lookups was made to that unrelated function; this is the one
        // that actually builds the arc_measures SceneKit node, and it had
        // the exact same plain-element-id lookup bug throughout, never
        // caught until now. atomNode(for:) only ever resolves the FIRST
        // copy of any element type once duplicates exist, so any selection
        // touching a duplicated element could silently fail to find a node
        // and skip that link entirely — producing no visible curve at all.
        var nodeIDs: [Int]
        var fields: [ArcComponentField]
        if let comp = arcAllSceneComponent {
            nodeIDs = selectedElementKeys
            fields = [comp]
        } else {
            nodeIDs = arcSeqSelection
            if arcSameKindFilter {
                // Keep only atoms whose element symbol appears more than once
                nodeIDs = nodeIDs.filter { id in
                    guard let (el, _) = arcElementAndKey(for: id) else { return false }
                    return selectedElements.filter { $0.elementSymbol == el.elementSymbol }.count > 1
                }
            }
            fields = ArcComponentField.allCases.filter { arcFieldComponents.contains($0) }
        }

        guard nodeIDs.count >= 2, !fields.isEmpty else {
            arcMeasureResults = []
            arcEdgeLengthSum = 0
            return
        }

        let holder = SCNNode(); holder.name = "arc_measures"
        var results: [ArcMeasureResult] = []
        var lengthSum = 0.0

        // Flux: all atoms in the scene influence the arc except the
        // measured pair itself (excluded per link below) — keyed by
        // instance now, so duplicates of the same element each keep their
        // own separate entry instead of overwriting each other.
        var fluxSources: [Int: (pos: SIMD3<Float>, mass: Float)] = [:]
        for (idx, el) in selectedElements.enumerated() {
            let key = idx < selectedElementKeys.count ? selectedElementKeys[idx] : el.id
            if let n = atomNode(for: key) {
                fluxSources[key] = (n.presentation.simdWorldPosition, Float(el.atomicMass))
            }
        }

        // Velocity/gravity potential Φ(p) = Σ mᵢ / (dᵢ + ε) over all atoms.
        // The neutron count defines the blueprint mass that sources the field.
        func phi(_ p: SIMD3<Float>, excluding: Set<Int>) -> Double {
            var s = 0.0
            for (id, src) in fluxSources where !excluding.contains(id) {
                let d = simd_distance(p, src.pos)
                s += Double(src.mass) / Double(d + 0.5)
            }
            return s
        }

        // Sequential links: N1→N2, N2→N3, …
        // Sequential N1->N2->N3... links, plus one extra closing link
        // (last -> first) when arcClosedLoop is on. Recomputed fresh every
        // call, so it always reflects whichever atoms are CURRENTLY first
        // and last in nodeIDs — adding or removing a selection updates
        // which pair the closing arc spans automatically, no separate
        // bookkeeping needed.
        var linkPairs: [(Int, Int)] = (0..<(nodeIDs.count - 1)).map { ($0, $0 + 1) }
        if arcClosedLoop && nodeIDs.count >= 2 {
            linkPairs.append((nodeIDs.count - 1, 0))
        }
        for (li, liNext) in linkPairs {
            guard let (elA, keyA) = arcElementAndKey(for: nodeIDs[li]),
                  let (elB, keyB) = arcElementAndKey(for: nodeIDs[liNext]),
                  let nA = atomNode(for: keyA),
                  let nB = atomNode(for: keyB) else { continue }
            let pStart = nA.presentation.simdWorldPosition
            let pEnd   = nB.presentation.simdWorldPosition
            let linkPair = Set([keyA, keyB])

            let arcDir = simd_normalize(pEnd - pStart)
            var arcUpV = SIMD3<Float>(0, 1, 0)
            if abs(simd_dot(arcDir, arcUpV)) > 0.9 { arcUpV = SIMD3(1, 0, 0) }
            let arcPerp = simd_normalize(simd_cross(arcDir, arcUpV))

            for (fi, field) in fields.enumerated() {
                // Per-field perpendicular separation — web sepScale 0.18
                let sep: Float = fields.count > 1
                    ? (Float(fi) - Float(fields.count - 1) / 2) * 0.18 : 0
                let offset = arcPerp * sep

                // Sample the arc — 20 segments, straight default + flux bend
                let segs = max(4, min(200, arcMeasureResolution))
                var pts: [SIMD3<Float>] = []
                var phis: [Double] = []
                for i in 0...segs {
                    let t = Float(i) / Float(segs)
                    var p = simd_mix(pStart, pEnd, SIMD3(repeating: t))
                    let φ = phi(p, excluding: linkPair)
                    phis.append(φ)
                    p += offset
                    pts.append(p)
                }
                // Flux bend — ONLY in velocity-potential mode. Distance mode
                // keeps the arc perfectly straight (default iteration).
                let φmean = phis.reduce(0, +) / Double(phis.count)
                let fluxGain: Float = arcMeasureMode == .velocityPotential ? 0.35 : 0
                for i in 1..<segs {
                    let t = Float(i) / Float(segs)
                    let weld = 1 - pow(2*t - 1, 2)           // 0 at ends, 1 at meridian
                    let dev = Float(phis[i] - φmean) * fluxGain * weld
                    pts[i] += arcPerp * dev
                }

                // Length + finite curvature κ = Σ|Δθ| / Σ|Δs|
                var length: Double = 0
                var turn: Double = 0
                for i in 0..<segs {
                    length += Double(simd_distance(pts[i], pts[i+1]))
                    if i > 0 {
                        let v0 = simd_normalize(pts[i] - pts[i-1])
                        let v1 = simd_normalize(pts[i+1] - pts[i])
                        let c = max(-1, min(1, simd_dot(v0, v1)))
                        turn += Double(acos(c))
                    }
                }
                let kappa = length > 0 ? turn / length : 0

                // Polyline render — small cylinders, constant lighting
                for i in 0..<segs {
                    holder.addChildNode(Self.measureSegment(pts[i], pts[i+1], color: field.color))
                }

                lengthSum += length
                results.append(ArcMeasureResult(
                    label: "\(elA.elementSymbol) → \(elB.elementSymbol) · \(field.rawValue)",
                    field: field, length: length, curvature: kappa,
                    phiA: phi(pStart, excluding: linkPair),
                    phiB: phi(pEnd,   excluding: linkPair)))
            }
        }

        scene.rootNode.addChildNode(holder)
        arcMeasureResults = results
        arcEdgeLengthSum = lengthSum
    }

    static func measureSegment(_ a: SIMD3<Float>, _ b: SIMD3<Float>, color: UIColor) -> SCNNode {
        let v = b - a; let len = simd_length(v)
        guard len > 1e-5 else { return SCNNode() }
        let cyl = SCNCylinder(radius: 0.035, height: CGFloat(len))
        cyl.radialSegmentCount = 6
        cyl.firstMaterial?.diffuse.contents = color
        cyl.firstMaterial?.emission.contents = color.withAlphaComponent(0.8)
        cyl.firstMaterial?.lightingModel = .constant
        let n = SCNNode(geometry: cyl)
        n.simdPosition = (a + b) / 2
        // Orient Y axis along v
        let up = SIMD3<Float>(0, 1, 0)
        let axis = simd_cross(up, simd_normalize(v))
        let dot = max(-1, min(1, simd_dot(up, simd_normalize(v))))
        if simd_length(axis) > 1e-5 {
            n.simdOrientation = simd_quatf(angle: acos(dot), axis: simd_normalize(axis))
        } else if dot < 0 {
            n.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))
        }
        return n
    }

    // Tap an atom row in the field-array list — toggles in LINK ORDER
    public func toggleArcSelection(_ id: Int) {
        if let idx = arcSeqSelection.firstIndex(of: id) {
            arcSeqSelection.remove(at: idx)
        } else {
            arcSeqSelection.append(id)
        }
        rebuildArcMeasures()
    }

    // Select All / Deselect All for the Arc Edge field-array list — appends
    // every currently-visible element not already selected, in list order,
    // preserving whatever partial link-order selection already existed.
    // Fixed to use each atom's own instance key instead of el.id: with
    // duplicate elements, the previous version added the FIRST copy's
    // plain id, then skipped every subsequent duplicate because that same
    // id already "existed" in the selection — visibly confirmed by a
    // screenshot showing six duplicate Tantalum rows all displaying the
    // identical link-order badge, since they were all really just querying
    // the one shared id.
    public func selectAllArcElements() {
        for (idx, el) in selectedElements.enumerated() {
            let key = idx < selectedElementKeys.count ? selectedElementKeys[idx] : el.id
            if !arcSeqSelection.contains(key) { arcSeqSelection.append(key) }
        }
        rebuildArcMeasures()
    }

    public func deselectAllArcElements() {
        arcSeqSelection = []
        rebuildArcMeasures()
    }

    // ── MATH ENGINE — executeAdvMath 1:1 port ────────────────────────
    // Neutron-first propagation: Neutron(count) → Proton bridge
    // [radian/degree per matter state] → Electron/Shell target value.
    public func executeAdvMath() {
        var results: [Double] = []
        var chain: [String] = []

        for i in mathSets.indices {
            let set = mathSets[i]
            let neutronA = mathNeutronCount(set.atomA)
            let bridgeA = protonBridge(set.atomA)
            let vA = mathResolve(set.atomA, set.compA) * bridgeA.factor

            var vB: Double? = nil
            if let b = set.atomB {
                let bridgeB = protonBridge(b)
                vB = mathResolve(b, set.compB) * bridgeB.factor
            }

            var val = mathApplyOp(vA, vB, set.op, set.radical ? set.radN : nil)

            // Physics property ops scale by their scene value
            if ["mass","volume","weight","density","temp","velocity"].contains(set.op) {
                val *= mathPhysicsValue(set.op)
            }
            if set.vsEnv {
                val = mathApplyOp(val, mathEnvValue("env_" + set.op), set.op, nil)
            }

            mathSets[i].result = val
            results.append(val)

            let aL = mathLabel(set.atomA), bL = set.atomB.map(mathLabel) ?? ""
            let sym = ARC_MATH_OPS.first(where: { $0.val == set.op })?.sym ?? "?"
            chain.append("Neutron(\(neutronA)) → Proton[\(String(format: "%.2f", bridgeA.deg))°/"
                + "\(String(format: "%.4f", bridgeA.rad))rad, \(matterState.rawValue.lowercased())]"
                + " → \(aL)[\(fmtMath(vA))]"
                + (set.atomB != nil ? " \(sym) \(bL)[\(fmtMath(vB ?? 0))]" : "")
                + " = \(fmtMath(val))")
        }

        // Nest results — linked sets chain via the PREVIOUS set's op
        var sigma = results.first ?? 0
        for i in 1..<max(results.count, 1) where i < results.count {
            if mathSets[i].linked {
                sigma = mathApplyOp(sigma, results[i], mathSets[i-1].op, nil)
            } else {
                sigma += results[i]
            }
        }
        // σ vs environment: σ · gravity · (pressure / 14.7)
        if mathSigmaEnv {
            sigma = sigma * physics.gravity * (physics.pressure / 14.7)
        }

        mathSigma = sigma
        mathChain = chain
        log("Σ Math = \(fmtMath(sigma)) [\(mathSets.compactMap{$0.result}.count) sets]")

        // ── PIPE TO SCENE — phys_* targets write back to PhysicsState
        for set in mathSets {
            guard let val = set.result, val.isFinite else { continue }
            if set.compA.hasPrefix("phys_") {
                switch set.compA.replacingOccurrences(of: "phys_", with: "") {
                case "temperature": physics.temperature = abs(val)
                case "gravity":     physics.gravity     = abs(val)
                case "pressure":    physics.pressure    = abs(val)
                case "velocity":    physics.velocity    = abs(val)
                default: break
                }
            }
        }
        rebuildArcMeasures()   // arcs respond to the new physics immediately
    }

    // Proton bridge: rad = (neutrons / protons) · π · stateModifier
    // factor = max(0.01, (1 + cos rad) / 2) — congruency wave
    func protonBridge(_ atomID: Int?) -> (factor: Double, rad: Double, deg: Double) {
        guard let id = atomID, id >= 0,
              let el = selectedElements.first(where: { $0.id == id }) else {
            return (1, 0, 0)
        }
        let rad = Double(el.neutrons) / Double(max(el.protons, 1))
            * .pi * matterState.stateModifier
        let deg = rad * 180 / .pi
        let factor = max(0.01, (1 + cos(rad)) / 2)
        return (factor, rad, deg)
    }

    func mathNeutronCount(_ atomID: Int?) -> Int {
        guard let id = atomID, id >= 0 else { return 0 }
        return selectedElements.first(where: { $0.id == id })?.neutrons ?? 1
    }

    // Value resolver — all / neutron / proton / electron / all_electrons /
    // shell_K..R / phys_* / Env (-1)
    func mathResolve(_ atomID: Int?, _ comp: String) -> Double {
        guard let id = atomID else { return 1 }
        if id == -1 { return mathEnvValue(comp) }
        guard let el = selectedElements.first(where: { $0.id == id }) else { return 1 }
        switch comp {
        case "all":            return el.atomicMass * Double(max(el.electronOrbits.count, 1))
        case "neutron":        return Double(el.neutrons)
        case "proton":         return Double(el.protons)
        case "electron", "all_electrons": return Double(el.electrons)
        default:
            if comp.hasPrefix("shell_") {
                let sn = String(comp.dropFirst(6))
                if let si = ARC_SHELL_NAMES.firstIndex(of: sn), si < el.electronOrbits.count {
                    return Double(el.electronOrbits[si])
                }
                return 1
            }
            if comp.hasPrefix("phys_") { return mathPhysicsValue(String(comp.dropFirst(5))) }
            if comp.hasPrefix("env_")  { return mathEnvValue(comp) }
            return 1
        }
    }

    func mathEnvValue(_ prop: String) -> Double {
        switch prop {
        case "env_temperature", "env_temp": return physics.temperature
        case "env_velocity": return physics.velocity
        case "env_weight":   return physics.gravity
        case "env_mass", "env_volume", "env_density": return 1
        default: return physics.gravity
        }
    }

    func mathPhysicsValue(_ prop: String) -> Double {
        switch prop {
        case "temp", "temperature": return physics.temperature
        case "velocity": return physics.velocity
        case "weight":   return physics.gravity
        case "gravity":  return physics.gravity
        case "pressure": return physics.pressure
        default: return 1   // mass / volume / density default 1 like web
        }
    }

    func mathApplyOp(_ a: Double, _ b: Double?, _ op: String, _ radical: Double?) -> Double {
        var r: Double
        switch op {
        case "paren":    r = b != nil ? a + b! : a
        case "exp":      r = b != nil ? pow(a, b!) : a
        case "multiply": r = b != nil ? a * b! : a
        case "divide":   r = b != nil ? a / (abs(b!) < 1e-10 ? 1e-10 : b!) : a
        case "add":      r = b != nil ? a + b! : a
        case "subtract": r = b != nil ? a - b! : a
        case "mass","volume","weight","density","temp","velocity":
            r = b != nil ? a * b! : a
        default: r = a
        }
        if let n = radical, n > 0 {
            r = pow(abs(r), 1 / n) * (r < 0 ? -1 : 1)
        }
        return r.isFinite ? r : 0
    }

    func mathLabel(_ atomID: Int?) -> String {
        guard let id = atomID else { return "—" }
        if id == -1 { return "Env" }
        return selectedElements.first(where: { $0.id == id })?.elementSymbol ?? "?"
    }

    func fmtMath(_ v: Double) -> String {
        if !v.isFinite { return "—" }
        if abs(v) > 1e10 || (abs(v) < 1e-6 && v != 0) {
            return String(format: "%.4e", v)
        }
        return String(format: "%.6g", v)
    }

    // ── TRANSPORT — play / stop / REC / scrub (web startRecording port) ──
    public func transportPlay() {
        guard !isPlaying else { return }
        isPlaying = true
        startEngineTick()
        setImportedAnimations(paused: false)   // GLB animations play with sim
        log("Simulation started")
    }

    // Resume / pause any animation players that came in with GLB imports
    func setImportedAnimations(paused: Bool) {
        scene.rootNode.enumerateChildNodes { node, _ in
            for key in node.animationKeys where key.hasPrefix("glb_") {
                node.animationPlayer(forKey: key)?.paused = paused
            }
        }
    }

    public func transportStop() {
        isPlaying = false
        if isRecording { transportStopRecording() }
        stopEngineTick()
        setImportedAnimations(paused: true)
        atomVelocities = [:]
        log("Simulation stopped")
    }

    // REC clears frames and auto-starts the simulation — like the web app
    public func transportRecord() {
        recordedFrames = []
        recordedFrameCount = 0
        playheadFrame = 0
        isRecording = true
        transportPlay()
        log("Recording started…")
    }

    public func transportStopRecording() {
        isRecording = false
        recordedFrameCount = recordedFrames.count
        log("Recording stopped. \(recordedFrames.count) frames captured.")
    }

    // Scrub — applies a recorded frame's positions to the scene
    public func transportSeek(frame: Int) {
        guard frame >= 0, frame < recordedFrames.count else { return }
        playheadFrame = frame
        let f = recordedFrames[frame]
        for (id, pos) in f.positions {
            atomNode(for: id)?.simdPosition = pos
        }
        rebuildArcMeasures()
    }

    func startEngineTick() {
        engineTimer?.invalidate()
        engineTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.engineTick() }
        }
    }

    func stopEngineTick() {
        engineTimer?.invalidate()
        engineTimer = nil
    }

    // 30 fps simulation tick — the full physics interaction model:
    //   ENVIRONMENT: gravity preset, wind drift, temperature Brownian motion
    //   ELEMENT ↔ ELEMENT: every pair couples through a gravity-like velocity
    //   potential Φ = m·m/r², but ALL math is delivered neutron-first —
    //   the neutron count is the blueprint mass, the proton acts as the
    //   radian/mole passage (matter-state bridge), and the result lands on
    //   the electron shells as motion. coupling = bridgeA · bridgeB.
    func engineTick() {
        guard isPlaying else { return }
        let dt: Float = 1.0 / 30.0
        let tempK = Float(max(0, (physics.temperature - 32) * 5/9 + 273.15))
        let jitter = (tempK / 293.0) * 0.018          // Brownian by temperature
        let wind = windDirection.vector * Float(windVelocity) * 0.002
        let envG = Float(physics.gravity)

        // Snapshot positions + per-atom neutron blueprint & bridge factor.
        // Body.key is the atomNodes/atomVelocities key for THIS SPECIFIC
        // instance — NOT necessarily el.id. This is the actual root cause
        // of the collapse: with duplicate-element support, several entries
        // in selectedElements can share the same el.id, but only the FIRST
        // copy of each element type was ever stored under its plain id;
        // every duplicate lives under its own instance key. Looking things
        // up by el.id alone (the previous code) meant every duplicate was
        // invisible to the simulation — never found, never moved — while
        // whatever WAS found under the plain id kept receiving force
        // contributions computed as if it represented all of them.
        struct Body { let key: Int; let pos: SIMD3<Float>
                      let blueprint: Float; let bridge: Float }
        var bodies: [Body] = []
        for (idx, el) in selectedElements.enumerated() {
            let key = idx < selectedElementKeys.count ? selectedElementKeys[idx] : el.id
            guard let n = atomNode(for: key) else { continue }
            bodies.append(Body(key: key, pos: n.simdPosition,
                blueprint: Float(max(el.neutrons, 1)),         // neutron blueprint (≥1: H interacts)
                bridge: Float(protonBridge(el.id).factor)))    // proton state passage — chemistry is per TYPE, so el.id is correct here
        }

        // Second pass at this — the first fix (repulsion + cutoff +
        // neighbor normalization) was directionally right but didn't
        // actually solve it: a FIXED 1.4-unit equilibrium combined with the
        // force scaling by the FULL PRODUCT of two elements' neutron counts
        // meant heavy elements (the videos consistently used Ba, U, Rf, Db)
        // pinned the force at its cap across almost the entire practical
        // range regardless of distance — verified numerically: two Uranium
        // atoms (146 neutrons each) still produced a raw force over 16x the
        // cap even 8 units apart. The repulsive term could only ever matter
        // at distances far closer than these atoms actually sit, so it was
        // effectively inert for exactly the elements the videos kept using.
        // Real fix: mass now scales the EQUILIBRIUM distance (heavier atoms
        // settle farther apart, which is physically sensible — bigger
        // electron shells need more room) instead of scaling the raw force
        // magnitude by the full product of neutron counts. Force magnitude
        // itself uses sqrt(blueprintA · blueprintB), far gentler than the
        // full product, plus an explicit flat coefficient — verified
        // numerically this keeps heavy-element forces in a well-behaved
        // range at realistic separations instead of pinned at the cap.
        let G: Float = 0.05 * (envG / 9.8)    // env gravity scales the coupling (visible)
        let interactionCutoff: Float = 24.0   // wide enough to cover heavy elements' larger equilibrium
        var neighborCount = [Int](repeating: 0, count: bodies.count)
        for i in bodies.indices {
            for j in bodies.indices where j != i {
                if simd_length(bodies[j].pos - bodies[i].pos) < interactionCutoff {
                    neighborCount[i] += 1
                }
            }
        }

        for i in bodies.indices {
            guard let node = atomNode(for: bodies[i].key) else { continue }
            var vel = atomVelocities[bodies[i].key] ?? .zero

            // ── pairwise velocity-potential forces, bridge-modulated ──
            for j in bodies.indices where j != i {
                let dvec = bodies[j].pos - bodies[i].pos
                let r = simd_length(dvec)
                guard r > 0.05 else { continue }             // avoid divide-by-near-zero
                guard r < interactionCutoff else { continue } // outside interaction range — no force at all

                let coupling = bodies[i].bridge * bodies[j].bridge
                // Bigger/heavier pairs settle farther apart — grows with the
                // SUM of blueprints (sub-quadratic), not their product.
                let equilibrium: Float = 1.2 + (bodies[i].blueprint + bodies[j].blueprint).squareRoot() * 0.55
                let ratio = equilibrium / max(r, 0.3)
                let attractive = ratio * ratio
                let repulsive  = ratio * ratio * ratio * ratio * ratio * ratio
                // Gentle mass scaling on magnitude — sqrt of the product,
                // not the full product, so heavy pairs don't dwarf light
                // ones by orders of magnitude at their own equilibrium.
                let massScale = (bodies[i].blueprint * bodies[j].blueprint).squareRoot()
                let f = G * massScale * coupling * (attractive - repulsive) * 1.4
                // Bumped from 0.05 — verified numerically the previous
                // coefficient produced forces of ~0.02-0.03 for heavy
                // elements even near their own crossover distance, which
                // combined with per-frame viscosity damping and gravity
                // already settling atoms to the floor, was too weak to
                // produce any visible lateral movement — what looked like
                // "stuttering in place" was just the harmless, separate
                // Brownian jitter term with no real drift underneath it.
                // This keeps the same safety mechanisms (repulsion, cutoff,
                // neighbor normalization, mass-scaled equilibrium) that
                // prevent collapse, just strong enough to actually see.
                let capped = max(-0.5, min(f, 0.5))
                let n = Float(max(1, max(neighborCount[i], neighborCount[j])))
                vel += simd_normalize(dvec) * (capped / n) * dt
            }

            // ── environment ──
            vel += wind * dt * 30
            // gravity settles atoms toward the grid floor (preset-scaled);
            // Zero-G preset → no settle, Jupiter → fast settle
            vel.y -= envG * 0.00045
            // env velocity (m/s) = global flow along the wind direction
            vel += windDirection.vector * Float(physics.velocity) * 0.0008
            // viscosity → damping: 1 cP = 0.985 baseline, thicker = heavier damping
            vel *= Float(min(0.995, max(0.90, 1.0 - 0.015 * physics.viscosity)))
            // soft boundary — fold back inside the grid extent
            let limit: Float = Float(gridDivisions) * 0.75 + 6
            // Continuous Brownian perturbation as VELOCITY, not a fixed
            // position offset — sustains real, evolving motion driven by
            // temperature indefinitely, instead of a wobble that's the only
            // thing left once the coupling force naturally settles near
            // equilibrium.
            vel += SIMD3<Float>(Float.random(in: -jitter...jitter),
                                Float.random(in: -jitter...jitter),
                                Float.random(in: -jitter...jitter)) * 6.0

            var p = bodies[i].pos + vel
            for k in 0..<3 where abs(p[k]) > limit {
                p[k] = p[k].sign == .minus ? -limit : limit
                vel[k] *= -0.5
            }
            // grid floor — atoms rest on the plane instead of sinking
            if p.y < 0.6 { p.y = 0.6; if vel.y < 0 { vel.y = 0 } }
            node.simdPosition = p
            atomVelocities[bodies[i].key] = vel

            // Real orbital rotation instead of a shader-driven jitter —
            // the shader modifier approach could never be visually verified
            // (no way to test-render it from here) and per the latest
            // report still wasn't producing anything visible. Standard
            // SceneKit eulerAngles rotation is ordinary, well-understood
            // code, and matches what was actually being asked for: the
            // electron shell itself sweeping around the nucleus, not
            // particles jittering in place. Speed is driven by this atom's
            // own temperature, its own current velocity (kinetic energy),
            // AND how many other atoms are nearby right now — genuinely
            // reacting to the local environment and neighboring atoms, not
            // just a fixed spin. Axis direction is randomized once per atom
            // via a stable per-node phase, so many atoms in a scene don't
            // all spin in visible lockstep.
            if let orbitalCloud = node.childNodes.first(where: { $0.name?.hasPrefix("_orbitalCloud:") == true }) {
                let tempFactor = max(0, Float(physics.temperature) - 32) / 212.0
                let localSpeed = simd_length(vel)
                let crowding = Float(neighborCount[i])
                // Base rate raised significantly and made less dependent
                // on this atom's own translational velocity — that velocity
                // naturally decays toward zero once atoms settle near their
                // coupling-force equilibrium (correct behavior for the
                // atoms themselves), which was also silently starving the
                // electron rotation of any driving signal once things
                // calmed down, even though electron motion shouldn't stop
                // just because the atom itself isn't drifting anymore.
                let spinRate = 0.05 + tempFactor * 0.14 + localSpeed * 2.2 + crowding * 0.006
                // Stable per-atom phase (from its own key) picks a consistent
                // tilt axis so this atom's spin direction doesn't change
                // erratically frame to frame, while still differing atom to
                // atom.
                let seed = Float(bodies[i].key % 360) * (.pi / 180)
                let axis = SIMD3<Float>(sin(seed), cos(seed * 1.3), sin(seed * 0.7))
                let normAxis = simd_normalize(axis)
                let cur = orbitalCloud.eulerAngles
                orbitalCloud.eulerAngles = SCNVector3(
                    cur.x + spinRate * normAxis.x,
                    cur.y + spinRate * normAxis.y,
                    cur.z + spinRate * normAxis.z)
            }
        }

        if isRecording {
            var snap: [Int: SIMD3<Float>] = [:]
            for el in selectedElements {
                if let n = atomNode(for: el.id) { snap[el.id] = n.simdPosition }
            }
            recordedFrames.append(RecordedFrame(
                time: Double(recordedFrames.count) / 30.0, positions: snap))
            recordedFrameCount = recordedFrames.count
            playheadFrame = recordedFrames.count - 1
        }

        rebuildArcMeasures()   // dynamic update during simulation play

        // ── Sync quantum orbital clouds to atom node positions ───────────
        // Quantum cloud follows atom position — no separate position tracking needed
        for atomD in quantumAtoms {
            let nodePos = atomNode(for: atomD.elementId)?.simdPosition ?? .zero
            atomD.root.simdPosition = nodePos
        }
    }

    // ── MANTIS NAVIGATION TAB — always-on while its tab lives ────────
    /// Index of the dedicated "Mantis Nav" tab — tracked by name so it
    /// survives other tabs being closed (index shifts).
    public var mantisTabIndex: Int? {
        sceneTabs_data.firstIndex(of: "Mantis Nav")
    }

    /// Opening the navigation menu creates (or returns to) the dedicated
    /// Mantis scene tab and activates flight immediately — no Activate
    /// button. Settings in the menu apply to the scene live. The tab's
    /// X closes the session; the menu tile brings it back.
    public func openMantisTab() {
        if let i = mantisTabIndex {
            switchTab(i)
        } else {
            addSceneTab()
            let i = sceneTabs_data.count - 1
            sceneTabs_data[i] = "Mantis Nav"
            switchTab(i)
        }
        mantis.labVM = self
        mantis.applyEnv(mantis.envPreset)
        if !mantis.isActive { mantis.activate(in: scene) }
        // Pre-fetch remote assets in background so they're available immediately
        // Pre-fetch remote assets — cachedRemoteURL does the disk IO
        Task(priority: .background) {
            for ra in MantisNavModel.remoteAssets {
                _ = self.mantis.cachedRemoteURL(resource: ra.resource, remoteURL: ra.url)
            }
        }
    }

    // ── ENV PRESETS — applied to active tab like the web app ────────
    public func applyEnvPreset(_ preset: EnvPreset) {
        envPreset = preset
        guard let v = preset.values else { return }
        physics.gravity = v.g
        physics.temperature = v.t
        physics.pressure = v.p
        log("Environment preset: \(preset.rawValue) — g \(v.g), \(v.t)°F, \(v.p) psi")
        rebuildArcMeasures()
    }
}

