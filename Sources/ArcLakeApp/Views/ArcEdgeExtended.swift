import SwiftUI
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════════════
// ArcEdgeExtended.swift
// Radical Deepscale / DART Meadow — Arc Lake iOS v1.5.3
//
// Extended Arc Grid Vector Measurement System
//
// Built on the Arc Edge DOC = 3.0 framework from:
//   · arc-edge-vector.html — spline physics, sigma Meridian, physOffset
//   · __init__.py (Blender addon) — doc_circumference, arc tube mesh
//   · ArcEdgeMath.swift — DOC constant, circumference, splineAxis
//   · ArcLakeEngines.swift — rebuildArcMeasures, protonBridge, phi potential
//
// New capabilities:
//   1. ARC GRID VECTOR OVERLAY — three XZ/XY/ZY plane sigma grids
//      displayed over the 3D scene, one grid per active measurement domain
//   2. CROSS-DOMAIN TRIGONOMETRIC DELTA — measure the angular difference
//      between two measurement types (e.g. thermal vs wind velocity) using
//      dot product: cos θ = (A·B) / (|A||B|)
//   3. EXTENDED ARC MEASURE PRESETS — quick-select configurations:
//      Molecular, Thermal CFD, Wind Aero, Combustion, Comparative
//   4. SIGMA READOUT PER DOMAIN — live Σ value per domain, with trigonometric
//      countermeasure delta (Δθ between domains in degrees)
//   5. DOC CIRCUMFERENCE ON ATOMS — apply C = √(d×3)² to atomic/molecular
//      radii for shell arc length and orbital circumference readout
//   6. SURFACE ARC MEASURE — tap two points on a GLB surface and measure
//      the Arc Edge spline distance across the surface (not straight-line)
// ═══════════════════════════════════════════════════════════════════════════

// MARK: — Arc Measurement Domains

public enum ArcMeasureDomain: String, CaseIterable, Identifiable {
    case molecular    = "Molecular"
    case thermal      = "Thermal CFD"
    case wind         = "Wind Aero"
    case combustion   = "Combustion"
    case pressure     = "Pressure"
    case velocity     = "Velocity"
    public var id: String { rawValue }

    public var color: UIColor {
        switch self {
        case .molecular:  return UIColor(red: 0.0,  green: 0.9,  blue: 1.0,  alpha: 1)   // cyan
        case .thermal:    return UIColor(red: 1.0,  green: 0.35, blue: 0.05, alpha: 1)   // orange-red
        case .wind:       return UIColor(red: 0.35, green: 0.85, blue: 1.0,  alpha: 1)   // sky blue
        case .combustion: return UIColor(red: 1.0,  green: 0.75, blue: 0.0,  alpha: 1)   // fire yellow
        case .pressure:   return UIColor(red: 0.6,  green: 0.2,  blue: 1.0,  alpha: 1)   // violet
        case .velocity:   return UIColor(red: 0.2,  green: 1.0,  blue: 0.5,  alpha: 1)   // green
        }
    }
    public var swiftColor: Color { Color(color) }

    // Grid plane assigned to each domain (cycles through XZ, XY, ZY)
    public var gridPlane: ArcGridPlane {
        switch self {
        case .molecular:  return .XZ
        case .thermal:    return .XY
        case .wind:       return .XZ
        case .combustion: return .XY
        case .pressure:   return .ZY
        case .velocity:   return .ZY
        }
    }
}

public enum ArcGridPlane: String, CaseIterable {
    case XZ, XY, ZY
}

// MARK: — Extended Arc Measure Result

public struct ArcEdgeExtResult: Identifiable {
    public let id = UUID()
    public let label: String
    public let domain: ArcMeasureDomain
    // Core measurements
    public let arcLength: Double         // DOC-spline arc length (scene units)
    public let curvature: Double         // κ = Σ|Δθ| / Σ|Δs|
    public let phiA: Double              // velocity potential at A
    public let phiB: Double              // velocity potential at B
    public let docCircumference: Double  // C = √(d × 3)² on arc length as diameter
    // Grid vector
    public let sigmaPoint: SIMD3<Float>  // shared sigma Meridian in world space
    public let sigmaM: Double            // magnitude of sigma
    // Trigonometric delta fields (set after cross-domain comparison)
    public var deltaTheta: Double = 0    // angle vs another domain (degrees)
    public var deltaDomain: ArcMeasureDomain? = nil
    // DOC arc on molecule
    public var molecularArcLen: Double = 0  // orbital circumference via DOC
    public var shellIndex: Int = 0
}

// MARK: — Extended Measurement Preset

public struct ArcMeasurePreset: Identifiable {
    public let id: String
    public let name: String
    public let icon: String
    public let domains: [ArcMeasureDomain]
    public let mode: ArcMeasureMode
    public let description: String

    public static let presets: [ArcMeasurePreset] = [
        ArcMeasurePreset(id:"molecular",   name:"Molecular",      icon:"atom",
            domains:[.molecular],
            mode:.distance,
            description:"DOC arc length between element positions. Orbital circumference C=√(d×3)² per shell."),
        ArcMeasurePreset(id:"thermal",     name:"Thermal CFD",    icon:"thermometer.medium",
            domains:[.thermal],
            mode:.velocityPotential,
            description:"Velocity potential Φ field from thermal CFD particle distribution."),
        ArcMeasurePreset(id:"wind",        name:"Wind Aero",      icon:"wind",
            domains:[.wind, .pressure],
            mode:.velocityPotential,
            description:"Wind tunnel flow arcs. Φ bending = local pressure differential Cp."),
        ArcMeasurePreset(id:"combustion",  name:"Combustion",     icon:"flame.fill",
            domains:[.combustion, .thermal],
            mode:.velocityPotential,
            description:"Exhaust plume arc. Phi gradient maps stagnation heating zones."),
        ArcMeasurePreset(id:"comparative", name:"Cross-Domain Δ", icon:"arrow.triangle.branch",
            domains:[.molecular, .thermal, .wind],
            mode:.velocityPotential,
            description:"Trigonometric countermeasure: Δθ = arccos(A·B/|A||B|) between domains."),
        ArcMeasurePreset(id:"full",        name:"All Domains",    icon:"chart.xyaxis.line",
            domains:ArcMeasureDomain.allCases,
            mode:.velocityPotential,
            description:"All six measurement domains simultaneously. Grid vector overlay per plane."),
    ]
}

// MARK: — Arc Grid Vector Overlay Node

/// Renders the three sigma grid planes (XZ/XY/ZY) as thin arc spline grids
/// in the SceneKit scene, one per domain color. Matches arc-edge-vector.html
/// grid system with DOC-based deviation = sin(3·t + phase) × influence.
public final class ArcGridVectorOverlay {

    public static let shared = ArcGridVectorOverlay()
    private var gridNodes: [String: SCNNode] = [:]    // plane → node
    private let DOC: Float = 3.0
    private let STEPS = 20
    private weak var scene: SCNScene?

    public func attach(to scene: SCNScene) { self.scene = scene }

    public func updateGrid(domains: [ArcMeasureDomain],
                           sigmaPoint: SIMD3<Float>,
                           influence: Float,
                           domainValues: [ArcMeasureDomain: Double]) {
        guard let scene else { return }
        // Clear existing grid nodes
        gridNodes.values.forEach { $0.removeFromParentNode() }
        gridNodes.removeAll()

        let extent: Float = 8.0     // grid half-extent in scene units
        let spacing: Float = 1.5    // grid line spacing

        for domain in domains {
            let plane = domain.gridPlane
            let key = "\(domain.rawValue)_\(plane.rawValue)"
            if gridNodes[key] != nil { continue }  // already drawn this plane/domain combo

            let holder = SCNNode(); holder.name = "arcGrid_\(key)"
            let col = domain.color

            // Value for this domain drives the influence (arc deviation amplitude)
            let domVal = domainValues[domain] ?? 0
            let inf = influence * Float(min(1, abs(domVal) / 100.0) + 0.15)

            // Sigma point drives grid center phase offset
            let sx = sigmaPoint.x; let sy = sigmaPoint.y; let sz = sigmaPoint.z

            // Generate grid lines for this plane
            var lineStart: Float = -extent
            while lineStart <= extent {
                // Primary axis lines
                let pts = arcGridSpline(
                    plane: plane, pos: lineStart,
                    extent: extent, sigX: sx, sigY: sy, sigZ: sz,
                    inf: inf, DOC: DOC, steps: STEPS, primary: true)
                // Perpendicular axis lines
                let pts2 = arcGridSpline(
                    plane: plane, pos: lineStart,
                    extent: extent, sigX: sx, sigY: sy, sigZ: sz,
                    inf: inf, DOC: DOC, steps: STEPS, primary: false)

                if pts.count > 1 { addPolyline(pts, to: holder, color: col, opacity: 0.28) }
                if pts2.count > 1 { addPolyline(pts2, to: holder, color: col, opacity: 0.18) }
                lineStart += spacing
            }

            // Sigma Meridian point marker
            let sphere = SCNSphere(radius: 0.10)
            sphere.firstMaterial?.diffuse.contents = col
            sphere.firstMaterial?.emission.contents = col.withAlphaComponent(0.9)
            sphere.firstMaterial?.lightingModel = .constant
            let sigNode = SCNNode(geometry: sphere)
            sigNode.simdPosition = sigmaPoint
            holder.addChildNode(sigNode)

            scene.rootNode.addChildNode(holder)
            gridNodes[key] = holder
        }
    }

    public func clearGrid() {
        gridNodes.values.forEach { $0.removeFromParentNode() }
        gridNodes.removeAll()
    }

    // Generate a DOC-spline arc line for one grid row
    private func arcGridSpline(plane: ArcGridPlane, pos: Float,
                                extent: Float, sigX: Float, sigY: Float, sigZ: Float,
                                inf: Float, DOC: Float, steps: Int, primary: Bool) -> [SIMD3<Float>] {
        var pts = [SIMD3<Float>]()
        let phase: Float = pos * 0.31 + (primary ? 0 : Float.pi / 2)
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let u = t * extent * 2 - extent  // -extent ... +extent
            // Arc deviation: sin(DOC × t + phase) × influence
            let dev = sin(DOC * t + phase) * inf * 0.55
            var p: SIMD3<Float>
            switch plane {
            case .XZ:
                if primary { p = SIMD3<Float>(u, sigY + dev, pos) }
                else       { p = SIMD3<Float>(pos, sigY + dev, u) }
            case .XY:
                if primary { p = SIMD3<Float>(u, pos + dev, sigZ) }
                else       { p = SIMD3<Float>(pos, u + dev, sigZ) }
            case .ZY:
                if primary { p = SIMD3<Float>(sigX, pos + dev, u) }
                else       { p = SIMD3<Float>(sigX, u + dev, pos) }
            }
            pts.append(p)
        }
        return pts
    }

    private func addPolyline(_ pts: [SIMD3<Float>], to parent: SCNNode,
                              color: UIColor, opacity: Float) {
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i+1]
            let v = b - a; let len = simd_length(v)
            guard len > 1e-5 else { continue }
            let geo = SCNCylinder(radius: 0.012, height: CGFloat(len))
            geo.radialSegmentCount = 4
            geo.firstMaterial?.diffuse.contents = color
            geo.firstMaterial?.emission.contents = color.withAlphaComponent(Double(opacity))
            geo.firstMaterial?.lightingModel = .constant
            geo.firstMaterial?.writesToDepthBuffer = false
            let n = SCNNode(geometry: geo)
            n.simdPosition = (a + b) / 2
            let up = SIMD3<Float>(0, 1, 0)
            let dir = simd_normalize(v)
            let axis = simd_cross(up, dir)
            let dot = max(-1, min(1, simd_dot(up, dir)))
            if simd_length(axis) > 1e-5 {
                n.simdOrientation = simd_quatf(angle: acos(dot), axis: simd_normalize(axis))
            } else if dot < 0 {
                n.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3(1,0,0))
            }
            parent.addChildNode(n)
        }
    }
}

// MARK: — ArcEdgeExtEngine

@MainActor
public final class ArcEdgeExtEngine: ObservableObject {
    public static let shared = ArcEdgeExtEngine()

    @Published public var activePreset: ArcMeasurePreset = ArcMeasurePreset.presets[0]
    @Published public var extResults: [ArcEdgeExtResult] = []
    @Published public var sigmaPoint: SIMD3<Float> = .zero
    @Published public var crossDomainDelta: Double = 0   // Δθ in degrees
    @Published public var crossDomainPairs: [(a: ArcMeasureDomain, b: ArcMeasureDomain, theta: Double)] = []
    @Published public var showGridOverlay: Bool = true
    @Published public var gridInfluence: Float = 0.8
    @Published public var docCircReadout: [String: Double] = [:]  // atomSymbol → C value

    private let DOC: Double = 3.0
    private let gridOverlay = ArcGridVectorOverlay.shared

    // MARK: — Main compute entry point

    public func compute(labVM: ArcLabViewModel) {
        guard labVM.selectedElements.count >= 2 else {
            extResults = []
            crossDomainPairs = []
            gridOverlay.clearGrid()
            return
        }

        let domains = activePreset.domains
        var allResults = [ArcEdgeExtResult]()
        var domainVectors: [ArcMeasureDomain: SIMD3<Double>] = [:]  // sigma vector per domain

        // ── Build per-domain arc results ─────────────────────────────────
        for domain in domains {
            let domResults = computeDomainArcs(domain: domain, labVM: labVM)
            allResults.append(contentsOf: domResults)

            // Accumulate domain sigma vector: length + curvature + phi
            let sigVec = domResults.reduce(SIMD3<Double>.zero) { acc, r in
                acc + SIMD3<Double>(r.arcLength, r.curvature, (r.phiA + r.phiB) * 0.5)
            }
            domainVectors[domain] = simd_length(sigVec) > 0 ? simd_normalize(sigVec) : SIMD3<Double>(1,0,0)
        }

        // ── Trigonometric cross-domain delta ─────────────────────────────
        // For each pair of domains: Δθ = arccos(A·B / |A||B|)
        var pairs = [(a: ArcMeasureDomain, b: ArcMeasureDomain, theta: Double)]()
        let domArr = domains
        for i in 0..<domArr.count {
            for j in (i+1)..<domArr.count {
                let vA = domainVectors[domArr[i]] ?? SIMD3<Double>(1,0,0)
                let vB = domainVectors[domArr[j]] ?? SIMD3<Double>(0,1,0)
                let cosTheta = max(-1, min(1, simd_dot(vA, vB)))
                let theta = acos(cosTheta) * 180.0 / .pi
                pairs.append((a: domArr[i], b: domArr[j], theta: theta))

                // Tag the delta onto results for the first domain
                for k in allResults.indices where allResults[k].domain == domArr[i] {
                    allResults[k].deltaTheta = theta
                    allResults[k].deltaDomain = domArr[j]
                    break
                }
            }
        }

        // ── Sigma Meridian point (shared intersection of all domain arcs) ─
        // Average of all atom positions weighted by domain count
        let nodes = labVM.selectedElements.compactMap { el in
            labVM.atomNode(for: el.id).map { ($0.simdPosition, el) }
        }
        let avgPos = nodes.reduce(SIMD3<Float>.zero) { $0 + $1.0 } / Float(max(1, nodes.count))
        sigmaPoint = avgPos

        // ── DOC circumference per atom shell ─────────────────────────────
        var docDict = [String: Double]()
        for el in labVM.selectedElements {
            // Atomic radius as diameter — C = √(d × 3)² = d × 3
            let r = Double(el.neutrons + el.protons) * 0.018 + 0.22  // nucleus radius (scene units)
            let totalShells = el.electronOrbits.count
            for shell in 0..<totalShells {
                let shellR = Double(shell + 1) * 1.15 + r + 0.25
                let diam = shellR * 2
                let C = sqrt(pow(diam * DOC, 2))  // C = √(d×3)²
                docDict["\(el.elementSymbol)·\(shell+1)"] = C
            }
        }
        docCircReadout = docDict

        // ── Grid vector overlay update ────────────────────────────────────
        let domainDoubles = Dictionary(uniqueKeysWithValues: domains.map { d in
            let v = allResults.filter { $0.domain == d }.first?.arcLength ?? 0
            return (d, v)
        })
        if showGridOverlay {
            gridOverlay.updateGrid(
                domains: domains,
                sigmaPoint: sigmaPoint,
                influence: gridInfluence,
                domainValues: domainDoubles)
        } else {
            gridOverlay.clearGrid()
        }

        extResults = allResults
        crossDomainPairs = pairs
        crossDomainDelta = pairs.first?.theta ?? 0
    }

    // MARK: — Per-domain arc computation

    private func computeDomainArcs(domain: ArcMeasureDomain,
                                    labVM: ArcLabViewModel) -> [ArcEdgeExtResult] {
        let nodeIDs = labVM.arcSeqSelection.isEmpty
            ? labVM.selectedElements.map { $0.id }
            : labVM.arcSeqSelection
        guard nodeIDs.count >= 2 else { return [] }

        // Flux sources — weighted by domain
        var fluxSources: [Int: (pos: SIMD3<Float>, weight: Float)] = [:]
        for el in labVM.selectedElements {
            guard let n = labVM.atomNode(for: el.id) else { continue }
            let weight = domainWeight(el: el, domain: domain)
            fluxSources[el.id] = (n.presentation.simdWorldPosition, weight)
        }

        func phi(_ p: SIMD3<Float>, excluding: Set<Int>) -> Double {
            var s = 0.0
            for (id, src) in fluxSources where !excluding.contains(id) {
                let d = simd_distance(p, src.pos)
                s += Double(src.weight) / Double(d + 0.5)
            }
            return s
        }

        var results = [ArcEdgeExtResult]()
        let fluxGain: Float = labVM.arcMeasureMode == .velocityPotential ? 0.42 : 0

        for li in 0..<(nodeIDs.count - 1) {
            guard let elA = labVM.selectedElements.first(where: { $0.id == nodeIDs[li] }),
                  let elB = labVM.selectedElements.first(where: { $0.id == nodeIDs[li+1] }),
                  let nA = labVM.atomNode(for: elA.id),
                  let nB = labVM.atomNode(for: elB.id) else { continue }

            let pStart = nA.presentation.simdWorldPosition
            let pEnd   = nB.presentation.simdWorldPosition
            let linkPair = Set([elA.id, elB.id])

            let arcDir = simd_normalize(pEnd - pStart)
            var arcUp = SIMD3<Float>(0, 1, 0)
            if abs(simd_dot(arcDir, arcUp)) > 0.9 { arcUp = SIMD3(1, 0, 0) }
            let arcPerp = simd_normalize(simd_cross(arcDir, arcUp))

            // Domain-based perpendicular offset (separates domain arcs visually)
            let domIdx = ArcMeasureDomain.allCases.firstIndex(of: domain) ?? 0
            let sep = (Float(domIdx) - Float(ArcMeasureDomain.allCases.count - 1) / 2) * 0.22
            let offset = arcPerp * sep

            let segs = 24
            var pts = [SIMD3<Float>]()
            var phis = [Double]()
            for i in 0...segs {
                let t = Float(i) / Float(segs)
                var p = simd_mix(pStart, pEnd, SIMD3(repeating: t))
                // DOC-based deviation: sin(3·t + phase) × domainInfluence
                let phase = Float(domIdx) * Float.pi / Float(ArcMeasureDomain.allCases.count)
                let docDev = sin(Float(DOC) * t + phase) * 0.12 * gridInfluence
                p += arcUp * docDev
                let φ = phi(p, excluding: linkPair)
                phis.append(φ)
                p += offset
                pts.append(p)
            }

            // Flux bend
            let φmean = phis.reduce(0, +) / Double(phis.count)
            for i in 1..<segs {
                let t = Float(i) / Float(segs)
                let weld = 1 - pow(2*t - 1, 2)
                let dev = Float(phis[i] - φmean) * fluxGain * weld
                pts[i] += arcPerp * dev
            }

            // Arc length + curvature κ
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

            // DOC circumference on arc length as diameter
            let docC = sqrt(pow(length * DOC, 2))

            // Sigma point for this arc = midpoint at t=0.5
            let sigPt = pts[segs / 2]
            let sigM = Double(simd_length(sigPt))

            // Molecular arc length = DOC circumference of nucleus radius
            let molR = Double(elA.neutrons + elA.protons) * 0.018 + 0.22
            let molArc = sqrt(pow(molR * 2 * DOC, 2))

            results.append(ArcEdgeExtResult(
                label: "\(elA.elementSymbol)→\(elB.elementSymbol) [\(domain.rawValue)]",
                domain: domain,
                arcLength: length,
                curvature: kappa,
                phiA: phi(pStart, excluding: linkPair),
                phiB: phi(pEnd,   excluding: linkPair),
                docCircumference: docC,
                sigmaPoint: sigPt,
                sigmaM: sigM,
                molecularArcLen: molArc,
                shellIndex: 0))
        }
        return results
    }

    // Domain-specific flux weighting — modulates which element property
    // drives the velocity-potential field for each measurement context
    private func domainWeight(el: ArcElement, domain: ArcMeasureDomain) -> Float {
        switch domain {
        case .molecular:  return Float(el.atomicMass)               // mass
        case .thermal:    return Float(el.protons) * 0.8 + 0.2      // proton count ≈ ionization energy
        case .wind:       return Float(el.atomicMass) / Float(max(1, el.protons)) // mass-to-charge
        case .combustion: return Float(max(el.neutrons, 1)) * 1.2  // neutron blueprint (LEATR)
        case .pressure:   return Float(el.electronOrbits.count) * 0.5 + Float(el.atomicMass) * 0.1
        case .velocity:   return Float(el.protons + el.neutrons) * Float(el.electronOrbits.count)
        }
    }

    // MARK: — Preset switch

    public func setPreset(_ preset: ArcMeasurePreset, labVM: ArcLabViewModel) {
        activePreset = preset
        compute(labVM: labVM)
    }
}

// MARK: — ArcEdgeExtPanel (SwiftUI)

struct ArcEdgeExtPanel: View {
    @StateObject private var engine = ArcEdgeExtEngine.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ───────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundColor(themeVM.accent).font(.system(size: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("ARC EDGE EXTENDED")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(themeVM.accent).tracking(2)
                    Text("Grid Vector · Trig Delta · Multi-Domain · DOC=3")
                        .font(.system(size: 6.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer()
                Button {
                    engine.compute(labVM: labVM)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(themeVM.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.04))

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {

                    // ── Preset selector ──────────────────────────────
                    sectionTitle("MEASUREMENT PRESET")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(ArcMeasurePreset.presets) { preset in
                            Button {
                                engine.setPreset(preset, labVM: labVM)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 9))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(preset.name)
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        Text(preset.domains.map{String($0.rawValue.prefix(4))}.joined(separator: "·"))
                                            .font(.system(size: 6, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                }
                                .padding(.horizontal, 7).padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(engine.activePreset.id == preset.id
                                    ? themeVM.accent.opacity(0.18)
                                    : Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(engine.activePreset.id == preset.id
                                        ? themeVM.accent.opacity(0.5)
                                        : Color.white.opacity(0.08), lineWidth: 1))
                            }
                            .foregroundColor(engine.activePreset.id == preset.id
                                ? themeVM.accent : .white.opacity(0.65))
                        }
                    }

                    // ── Grid overlay toggle ──────────────────────────
                    sectionTitle("ARC GRID VECTOR")
                    HStack(spacing: 8) {
                        Toggle("", isOn: $engine.showGridOverlay)
                            .labelsHidden()
                            .tint(themeVM.accent)
                            .onChange(of: engine.showGridOverlay) { _ in
                                engine.compute(labVM: labVM)
                            }
                        Text(engine.showGridOverlay ? "Grid ON" : "Grid OFF")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(engine.showGridOverlay ? themeVM.accent : .white.opacity(0.35))
                        Spacer()
                        Text("Inf")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                        Slider(value: $engine.gridInfluence, in: 0.1...2.0)
                            .tint(themeVM.accent)
                            .frame(width: 80)
                            .onChange(of: engine.gridInfluence) { _ in engine.compute(labVM: labVM) }
                        Text(String(format: "%.1f", engine.gridInfluence))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                    }

                    // ── Cross-domain trig delta ──────────────────────
                    if !engine.crossDomainPairs.isEmpty {
                        sectionTitle("TRIGONOMETRIC Δθ COUNTERMEASURE")
                        VStack(spacing: 4) {
                            ForEach(Array(engine.crossDomainPairs.enumerated()), id: \.0) { _, pair in
                                HStack {
                                    Circle().fill(pair.a.swiftColor).frame(width:6,height:6)
                                    Text(pair.a.rawValue.prefix(8))
                                        .font(.system(size: 7.5, design: .monospaced))
                                        .foregroundColor(pair.a.swiftColor)
                                    Image(systemName: "arrow.left.and.right")
                                        .font(.system(size: 7))
                                        .foregroundColor(.white.opacity(0.3))
                                    Circle().fill(pair.b.swiftColor).frame(width:6,height:6)
                                    Text(pair.b.rawValue.prefix(8))
                                        .font(.system(size: 7.5, design: .monospaced))
                                        .foregroundColor(pair.b.swiftColor)
                                    Spacer()
                                    // Δθ = arccos(A·B) — the angular countermeasure
                                    Text(String(format: "Δθ %.1f°", pair.theta))
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(deltaColor(pair.theta))
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        // Interpretation
                        let theta = engine.crossDomainPairs.first?.theta ?? 0
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                            Text(deltaInterpretation(theta))
                                .font(.system(size: 7.5, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.vertical, 3)
                    }

                    // ── Sigma Meridian readout ───────────────────────
                    sectionTitle("SIGMA MERIDIAN")
                    HStack {
                        Text("σ world")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text(String(format: "(%.2f, %.2f, %.2f)",
                                    engine.sigmaPoint.x, engine.sigmaPoint.y, engine.sigmaPoint.z))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                    }

                    // ── Arc results ──────────────────────────────────
                    if !engine.extResults.isEmpty {
                        sectionTitle("ARC MEASUREMENTS")
                        VStack(spacing: 5) {
                            ForEach(engine.extResults) { r in
                                ArcExtResultRow(result: r, accent: themeVM.accent)
                            }
                        }
                    }

                    // ── DOC circumference readout ────────────────────
                    if !engine.docCircReadout.isEmpty {
                        sectionTitle("DOC ORBITAL C = √(d×3)²")
                        VStack(spacing: 3) {
                            ForEach(Array(engine.docCircReadout.sorted(by: { $0.key < $1.key })), id: \.key) { key, val in
                                HStack {
                                    Text(key)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                    Spacer()
                                    Text(String(format: "C = %.3f", val))
                                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(themeVM.accent)
                                }
                            }
                        }
                    }

                    // ── Compute button ───────────────────────────────
                    Button {
                        engine.compute(labVM: labVM)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "function").font(.system(size: 11))
                            Text("COMPUTE ARC MEASURES")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .tracking(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(themeVM.accent.opacity(0.14))
                        .foregroundColor(themeVM.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(themeVM.accent.opacity(0.38), lineWidth: 1))
                    }
                }
                .padding(10)
            }
        }
        .background(Color(red:0.03,green:0.05,blue:0.10).opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            ArcGridVectorOverlay.shared.attach(to: labVM.scene)
        }
    }

    // MARK: — Helpers

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.3)).tracking(1.5)
    }

    private func deltaColor(_ theta: Double) -> Color {
        if theta < 15  { return .green   }   // nearly aligned — domains agree
        if theta < 45  { return Color(red:0.8,green:1,blue:0.2,opacity:1) }
        if theta < 90  { return .yellow  }   // moderate divergence
        if theta < 135 { return .orange  }   // significant divergence
        return .red                           // near-opposite — strong countermeasure
    }

    private func deltaInterpretation(_ theta: Double) -> String {
        if theta < 15  { return "Domains aligned — similar fluid behavior" }
        if theta < 45  { return "Slight divergence — minor interaction effect" }
        if theta < 90  { return "Moderate divergence — notable cross-domain effect" }
        if theta < 135 { return "Strong countermeasure — opposing field vectors" }
        return "Near-opposite vectors — maximum countermeasure effect"
    }
}

// MARK: — Arc result row

struct ArcExtResultRow: View {
    let result: ArcEdgeExtResult
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(result.domain.swiftColor).frame(width:6,height:6)
                Text(result.label)
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(result.domain.swiftColor)
                Spacer()
                if result.deltaTheta > 0.1, let dl = result.deltaDomain {
                    Text(String(format: "Δθ %.0f°", result.deltaTheta))
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.8))
                }
            }
            HStack(spacing: 10) {
                metricPill("L", String(format:"%.3f", result.arcLength))
                metricPill("κ", String(format:"%.3f", result.curvature))
                metricPill("C", String(format:"%.2f", result.docCircumference))
                metricPill("φΔ", String(format:"%.2f", abs(result.phiA - result.phiB)))
            }
            if result.molecularArcLen > 0 {
                Text(String(format: "Mol arc C=%.3f (DOC·nucleus)", result.molecularArcLen))
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(result.domain.swiftColor.opacity(0.2), lineWidth: 1))
    }
    private func metricPill(_ label: String, _ val: String) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 6.5, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            Text(val).font(.system(size: 7.5, weight: .semibold, design: .monospaced)).foregroundColor(accent)
        }
    }
}
