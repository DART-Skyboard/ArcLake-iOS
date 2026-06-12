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
    public func rebuildArcMeasures() {
        scene.rootNode.childNode(withName: "arc_measures", recursively: false)?
            .removeFromParentNode()

        // MODE 1: All-Scene (all-to-all link type) — nodes in scene order
        // MODE 2: Sequential selection — atoms in tap order
        var nodeIDs: [Int]
        var fields: [ArcComponentField]
        if let comp = arcAllSceneComponent {
            nodeIDs = selectedElements.map { $0.id }
            fields = [comp]
        } else {
            nodeIDs = arcSeqSelection
            if arcSameKindFilter {
                // Keep only atoms whose element symbol appears more than once
                nodeIDs = nodeIDs.filter { id in
                    guard let el = selectedElements.first(where: { $0.id == id }) else { return false }
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
        // measured pair itself (excluded per link below)
        var fluxSources: [Int: (pos: SIMD3<Float>, mass: Float)] = [:]
        for el in selectedElements {
            if let n = atomNode(for: el.id) {
                fluxSources[el.id] = (n.presentation.simdWorldPosition, Float(el.atomicMass))
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
        for li in 0..<(nodeIDs.count - 1) {
            guard let elA = selectedElements.first(where: { $0.id == nodeIDs[li] }),
                  let elB = selectedElements.first(where: { $0.id == nodeIDs[li+1] }),
                  let nA = atomNode(for: elA.id),
                  let nB = atomNode(for: elB.id) else { continue }
            let pStart = nA.presentation.simdWorldPosition
            let pEnd   = nB.presentation.simdWorldPosition
            let linkPair = Set([elA.id, elB.id])

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
                let segs = 20
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
        let jitter = (tempK / 293.0) * 0.004          // Brownian by temperature
        let wind = windDirection.vector * Float(windVelocity) * 0.002
        let envG = Float(physics.gravity)

        // Snapshot positions + per-atom neutron blueprint & bridge factor
        struct Body { let id: Int; let pos: SIMD3<Float>
                      let blueprint: Float; let bridge: Float }
        var bodies: [Body] = []
        for el in selectedElements {
            guard let n = atomNode(for: el.id) else { continue }
            bodies.append(Body(id: el.id, pos: n.simdPosition,
                blueprint: Float(max(el.neutrons, 1)),         // neutron blueprint (≥1: H interacts)
                bridge: Float(protonBridge(el.id).factor)))    // proton state passage
        }

        let G: Float = 0.05 * (envG / 9.8)    // env gravity scales the coupling (visible)
        for i in bodies.indices {
            guard let node = atomNode(for: bodies[i].id) else { continue }
            var vel = atomVelocities[bodies[i].id] ?? .zero

            // ── pairwise velocity-potential forces, bridge-modulated ──
            for j in bodies.indices where j != i {
                let dvec = bodies[j].pos - bodies[i].pos
                let r = simd_length(dvec)
                guard r > 0.6 else {
                    // contact repulsion — atoms never collapse into each other
                    if r > 1e-4 { vel -= simd_normalize(dvec) * 0.02 }
                    continue
                }
                // Φ-gradient: blueprintA·blueprintB / r², passed through BOTH
                // proton bridges (gas/liquid/solid/plasma congruency)
                let coupling = bodies[i].bridge * bodies[j].bridge
                let f = G * bodies[i].blueprint * bodies[j].blueprint
                    * coupling / (r * r)
                vel += simd_normalize(dvec) * min(f, 0.5) * dt
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
            var p = bodies[i].pos + vel
            for k in 0..<3 where abs(p[k]) > limit {
                p[k] = p[k].sign == .minus ? -limit : limit
                vel[k] *= -0.5
            }
            // grid floor — atoms rest on the plane instead of sinking
            if p.y < 0.6 { p.y = 0.6; if vel.y < 0 { vel.y = 0 } }
            p += SIMD3<Float>(Float.random(in: -jitter...jitter),
                              Float.random(in: -jitter...jitter),
                              Float.random(in: -jitter...jitter))
            node.simdPosition = p
            atomVelocities[bodies[i].id] = vel
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
