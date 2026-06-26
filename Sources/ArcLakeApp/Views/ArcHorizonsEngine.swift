import Foundation
import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════════════
// ArcHorizonsEngine.swift
// Radical Deepscale / DART Meadow — Arc Lake iOS v1.5.3
//
// JPL Horizons API v1.3 integration for real-time celestial trajectory data.
// API: https://ssd-api.jpl.nasa.gov/api/horizons.api
//
// Features:
//   · Fetch real-time ephemeris (position + velocity vectors) for any
//     solar system body — planets, moons, asteroids, comets, spacecraft
//   · Display celestial body as a labeled node in the Mantis Nav SceneKit scene
//   · Trajectory scrubber: center=real-time, left=past, right=future
//     Each notch = configurable time step (1 min / 1 hr / 1 day / 1 week)
//   · Manual trajectory math input (Δv, departure, arrival, slingshot)
//   · Scale: 1 AU = 10 scene units (adjustable)
// ═══════════════════════════════════════════════════════════════════════════

// MARK: — Known Bodies (subset of Horizons catalog)

public struct ArcCelestialBody: Identifiable {
    public let id: String          // Horizons target body ID (e.g. "499" for Mars)
    public let name: String
    public let symbol: String
    public let color: UIColor
    public let meanRadiusKm: Double  // for visual scale

    public static let catalog: [ArcCelestialBody] = [
        ArcCelestialBody(id:"10",   name:"Sun",           symbol:"☉", color:.systemYellow,          meanRadiusKm:695700),
        ArcCelestialBody(id:"199",  name:"Mercury",       symbol:"☿", color:.systemGray,            meanRadiusKm:2439),
        ArcCelestialBody(id:"299",  name:"Venus",         symbol:"♀", color:.systemOrange,          meanRadiusKm:6051),
        ArcCelestialBody(id:"399",  name:"Earth",         symbol:"♁", color:.systemBlue,            meanRadiusKm:6371),
        ArcCelestialBody(id:"301",  name:"Moon",          symbol:"☽", color:.systemGray2,           meanRadiusKm:1737),
        ArcCelestialBody(id:"499",  name:"Mars",          symbol:"♂", color:.systemRed,             meanRadiusKm:3390),
        ArcCelestialBody(id:"401",  name:"Phobos",        symbol:"Ph",color:.systemGray3,           meanRadiusKm:11),
        ArcCelestialBody(id:"599",  name:"Jupiter",       symbol:"♃", color:.systemOrange,          meanRadiusKm:69911),
        ArcCelestialBody(id:"699",  name:"Saturn",        symbol:"♄", color:.systemYellow,          meanRadiusKm:58232),
        ArcCelestialBody(id:"799",  name:"Uranus",        symbol:"♅", color:.systemTeal,            meanRadiusKm:25362),
        ArcCelestialBody(id:"899",  name:"Neptune",       symbol:"♆", color:.systemIndigo,          meanRadiusKm:24622),
        ArcCelestialBody(id:"999",  name:"Pluto",         symbol:"♇", color:.systemBrown,           meanRadiusKm:1188),
        ArcCelestialBody(id:"-143", name:"ISS",           symbol:"🛸",color:.systemGreen,           meanRadiusKm:0.05),
        ArcCelestialBody(id:"-48",  name:"Hubble",        symbol:"🔭",color:.systemCyan,            meanRadiusKm:0.007),
        ArcCelestialBody(id:"-234", name:"DART",          symbol:"⬡", color:.systemMint,            meanRadiusKm:0.001),
        ArcCelestialBody(id:"20065803", name:"Didymos",   symbol:"☄", color:.systemBrown,          meanRadiusKm:0.39),
        ArcCelestialBody(id:"1000041",  name:"Halley",    symbol:"☄", color:.systemGray,           meanRadiusKm:5.5),
        ArcCelestialBody(id:"2000433",  name:"Eros",      symbol:"☄", color:.systemBrown,          meanRadiusKm:8.4),
    ]
}

// MARK: — Ephemeris Data Point

public struct ArcEphemerisPoint: Codable {
    public let julianDate: Double
    public let calendarDate: String
    // Heliocentric rectangular coordinates (AU)
    public let x: Double, y: Double, z: Double
    // Velocity (AU/day)
    public let vx: Double, vy: Double, vz: Double
    public let distAU: Double
    public var scenePosition: SIMD3<Float> {
        let scale: Float = 10.0  // 1 AU = 10 scene units
        return SIMD3<Float>(Float(x)*scale, Float(z)*scale, Float(y)*scale)
    }
}

// MARK: — Trajectory Result

public struct ArcTrajectoryResult {
    public let bodyId: String
    public let bodyName: String
    public let points: [ArcEphemerisPoint]
    public var currentIndex: Int    // index at real-time position
}

// MARK: — Time Step Enum

public enum ArcTimeStep: String, CaseIterable, Identifiable {
    case oneMin  = "1 min"
    case fiveMin = "5 min"
    case oneHr   = "1 hr"
    case sixHr   = "6 hr"
    case oneDay  = "1 day"
    case oneWeek = "1 week"
    public var id: String { rawValue }
    public var minutes: Double {
        switch self {
        case .oneMin: return 1; case .fiveMin: return 5
        case .oneHr: return 60; case .sixHr: return 360
        case .oneDay: return 1440; case .oneWeek: return 10080
        }
    }
}

// MARK: — ArcHorizonsEngine

@MainActor
public final class ArcHorizonsEngine: ObservableObject {
    public static let shared = ArcHorizonsEngine()

    // Horizons API endpoint (no auth required — public NASA API)
    private let apiBase = "https://ssd-api.jpl.nasa.gov/horizons.api"

    @Published public var selectedBodies: [String] = ["399", "499"]  // Earth + Mars default
    @Published public var trajectories: [ArcTrajectoryResult] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var timeStep: ArcTimeStep = .oneDay
    @Published public var scrubberOffset: Int = 0   // 0 = real-time, ± steps
    @Published public var totalSteps: Int = 100      // total scrubber range (±50 either side)
    @Published public var showOrbits: Bool = true
    @Published public var auPerUnit: Float = 10.0   // 1 AU = 10 scene units
    @Published public var currentEpoch: String = "NOW"

    private var bodyNodes: [String: SCNNode] = [:]
    private var orbitNodes: [String: SCNNode] = [:]
    private weak var scene: SCNScene?

    // MARK: — Fetch Ephemeris

    public func fetchAll(scene: SCNScene) async {
        self.scene = scene
        isLoading = true
        errorMessage = nil
        trajectories.removeAll()

        for bodyId in selectedBodies {
            if let result = await fetchEphemeris(bodyId: bodyId) {
                trajectories.append(result)
                injectBodyIntoScene(result, scene: scene)
            }
        }
        isLoading = false
        updateScrubPosition()
    }

    private func fetchEphemeris(bodyId: String) async -> ArcTrajectoryResult? {
        let body = ArcCelestialBody.catalog.first(where: { $0.id == bodyId })
        let name = body?.name ?? "Body \(bodyId)"

        // Calculate time range: ±(totalSteps/2) steps from now
        let now = Date()
        let stepsBack = totalSteps / 2
        let stepsForward = totalSteps - stepsBack
        let startDate = now.addingTimeInterval(-Double(stepsBack) * timeStep.minutes * 60)
        let stopDate  = now.addingTimeInterval(Double(stepsForward) * timeStep.minutes * 60)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MMM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let startStr = fmt.string(from: startDate)
        let stopStr  = fmt.string(from: stopDate)

        // Build Horizons API URL
        // VECTORS table gives X,Y,Z,VX,VY,VZ in heliocentric AU and AU/day
        var comps = URLComponents(string: apiBase)!
        comps.queryItems = [
            URLQueryItem(name: "format",       value: "json"),
            URLQueryItem(name: "COMMAND",      value: "'\(bodyId)'"),
            URLQueryItem(name: "OBJ_DATA",     value: "NO"),
            URLQueryItem(name: "MAKE_EPHEM",   value: "YES"),
            URLQueryItem(name: "EPHEM_TYPE",   value: "VECTORS"),
            URLQueryItem(name: "CENTER",       value: "'500@10'"),  // Sun center
            URLQueryItem(name: "START_TIME",   value: "'\(startStr)'"),
            URLQueryItem(name: "STOP_TIME",    value: "'\(stopStr)'"),
            URLQueryItem(name: "STEP_SIZE",    value: "'\(Int(timeStep.minutes))m'"),
            URLQueryItem(name: "VEC_TABLE",    value: "2"),   // table 2 = X,Y,Z,VX,VY,VZ
            URLQueryItem(name: "REF_PLANE",    value: "ECLIPTIC"),
            URLQueryItem(name: "REF_SYSTEM",   value: "J2000"),
            URLQueryItem(name: "VEC_CORR",     value: "NONE"),
            URLQueryItem(name: "OUT_UNITS",    value: "AU-D"),  // AU and AU/day
            URLQueryItem(name: "CSV_FORMAT",   value: "NO"),
        ]

        guard let url = comps.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parseHorizonsResponse(data: data, bodyId: bodyId, name: name, now: now)
        } catch {
            errorMessage = "Horizons fetch error: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: — Parse Horizons Text Response

    private func parseHorizonsResponse(data: Data, bodyId: String, name: String, now: Date) -> ArcTrajectoryResult? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }

        // Extract JSON result field or parse the text table
        // Horizons returns JSON with a "result" field containing the ephemeris text
        var tableText = raw
        if let jsonData = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let result = json["result"] as? String {
            tableText = result
        }

        var points = [ArcEphemerisPoint]()
        // $$SOE marks start of ephemeris data, $$EOE marks end
        guard let soeRange = tableText.range(of: "$$SOE"),
              let eoeRange = tableText.range(of: "$$EOE") else { return nil }

        let tableBody = String(tableText[soeRange.upperBound..<eoeRange.lowerBound])
        let lines = tableBody.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var i = 0
        while i < lines.count {
            // Horizons VECTORS output format (no CSV):
            // Line 1: JDTDB, Calendar, ...
            // Line 2: X= vvv Y= vvv Z= vvv
            // Line 3: VX= vvv VY= vvv VZ= vvv
            // Line 4: LT= ... RG= ... RR= ...
            guard i + 3 < lines.count else { break }

            let headerLine = lines[i].trimmingCharacters(in: .whitespaces)
            let xyzLine    = lines[i+1].trimmingCharacters(in: .whitespaces)
            let vxyzLine   = lines[i+2].trimmingCharacters(in: .whitespaces)
            let distLine   = lines[i+3].trimmingCharacters(in: .whitespaces)

            // Parse Julian date and calendar date from header
            let headerParts = headerLine.components(separatedBy: "=")
            guard let jdStr = headerParts.first?.trimmingCharacters(in: .whitespaces),
                  let jd = Double(jdStr.components(separatedBy: .whitespaces).first ?? "") else { i += 5; continue }

            let calParts = headerLine.components(separatedBy: "A.D.")
            let calDate = calParts.count > 1 ? calParts[1].components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? "" : ""

            // Parse X Y Z
            func extractVal(_ line: String, _ key: String) -> Double {
                guard let r = line.range(of: key + "=") else { return 0 }
                let after = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                return Double(after.components(separatedBy: .whitespaces).first ?? "0") ?? 0
            }
            let x  = extractVal(xyzLine,  "X");  let y = extractVal(xyzLine,  "Y");  let z = extractVal(xyzLine,  "Z")
            let vx = extractVal(vxyzLine, "VX"); let vy = extractVal(vxyzLine, "VY"); let vz = extractVal(vxyzLine, "VZ")
            let dist = extractVal(distLine, "RG")

            points.append(ArcEphemerisPoint(
                julianDate: jd, calendarDate: calDate,
                x: x, y: y, z: z, vx: vx, vy: vy, vz: vz, distAU: dist))
            i += 5
        }

        guard !points.isEmpty else { return nil }

        // Find index closest to now
        let nowJD = 2451545.0 + Date().timeIntervalSince(Date(timeIntervalSinceReferenceDate: 0)) / 86400.0
        let nowIdx = points.enumerated().min(by: { abs($0.element.julianDate - nowJD) < abs($1.element.julianDate - nowJD) })?.offset ?? 0

        return ArcTrajectoryResult(bodyId: bodyId, bodyName: name, points: points, currentIndex: nowIdx)
    }

    // MARK: — Scene Integration

    private func injectBodyIntoScene(_ result: ArcTrajectoryResult, scene: SCNScene) {
        let body = ArcCelestialBody.catalog.first(where: { $0.id == result.bodyId })
        let color = body?.color ?? .white
        let radius = max(0.1, min(2.0, Float((body?.meanRadiusKm ?? 1000)) / 10000.0 * auPerUnit))

        // Remove existing node
        bodyNodes[result.bodyId]?.removeFromParentNode()
        orbitNodes[result.bodyId]?.removeFromParentNode()

        // Body sphere
        let geo = SCNSphere(radius: CGFloat(radius))
        geo.firstMaterial?.diffuse.contents  = color
        geo.firstMaterial?.emission.contents = color.withAlphaComponent(0.4)
        geo.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: geo)
        node.name = "horizons_body_\(result.bodyId)"

        // Position at current epoch
        let pt = result.points[result.currentIndex]
        node.simdPosition = pt.scenePosition

        // Label
        let lbl = SCNText(string: result.bodyName, extrusionDepth: 0.01)
        lbl.font = UIFont.systemFont(ofSize: 0.4, weight: .bold)
        lbl.firstMaterial?.diffuse.contents  = UIColor.white
        lbl.firstMaterial?.emission.contents = color.withAlphaComponent(0.7)
        lbl.firstMaterial?.lightingModel = .constant
        let lblNode = SCNNode(geometry: lbl)
        lblNode.position = SCNVector3(Float(radius) + 0.1, 0, 0)
        lblNode.scale = SCNVector3(0.5, 0.5, 0.5)
        node.addChildNode(lblNode)

        scene.rootNode.addChildNode(node)
        bodyNodes[result.bodyId] = node

        // Orbit path
        if showOrbits && result.points.count > 1 {
            buildOrbitPath(result, color: color, scene: scene)
        }
    }

    private func buildOrbitPath(_ result: ArcTrajectoryResult, color: UIColor, scene: SCNScene) {
        let pts = result.points.map { $0.scenePosition }
        var positions = [SCNVector3]()
        for p in pts { positions.append(SCNVector3(p.x, p.y, p.z)) }

        // Build polyline from segments
        let orbitHolder = SCNNode(); orbitHolder.name = "horizons_orbit_\(result.bodyId)"
        for i in 0..<(positions.count - 1) {
            let a = positions[i], b = positions[i+1]
            let dx = b.x-a.x, dy = b.y-a.y, dz = b.z-a.z
            let len = sqrt(dx*dx + dy*dy + dz*dz)
            guard len > 0.001 else { continue }
            let cyl = SCNCylinder(radius: 0.008, height: CGFloat(len))
            cyl.radialSegmentCount = 4
            cyl.firstMaterial?.diffuse.contents = color
            cyl.firstMaterial?.emission.contents = color.withAlphaComponent(0.25)
            cyl.firstMaterial?.lightingModel = .constant
            cyl.firstMaterial?.writesToDepthBuffer = false
            let seg = SCNNode(geometry: cyl)
            seg.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
            let up = SCNVector3(0,1,0)
            let dir = SCNVector3(dx/len, dy/len, dz/len)
            let dot = min(1, max(-1, up.x*dir.x + up.y*dir.y + up.z*dir.z))
            let ax = SCNVector3(up.y*dir.z - up.z*dir.y, up.z*dir.x - up.x*dir.z, up.x*dir.y - up.y*dir.x)
            let axLen = sqrt(ax.x*ax.x + ax.y*ax.y + ax.z*ax.z)
            if axLen > 0.001 {
                seg.rotation = SCNVector4(ax.x/axLen, ax.y/axLen, ax.z/axLen, acos(dot))
            }
            orbitHolder.addChildNode(seg)
        }
        scene.rootNode.addChildNode(orbitHolder)
        orbitNodes[result.bodyId] = orbitHolder
    }

    // MARK: — Scrubber

    public func updateScrubPosition() {
        for (idx, result) in trajectories.enumerated() {
            let clampedIdx = max(0, min(result.points.count - 1,
                result.currentIndex + scrubberOffset))
            let pt = result.points[clampedIdx]
            if let node = bodyNodes[result.bodyId] {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.12
                node.simdPosition = pt.scenePosition
                SCNTransaction.commit()
            }
            let calDate = result.points[clampedIdx].calendarDate
            currentEpoch = calDate.isEmpty ? "Step \(scrubberOffset)" : calDate
            _ = idx  // suppress unused
        }
    }

    public func removeAllBodies() {
        bodyNodes.values.forEach { $0.removeFromParentNode() }
        orbitNodes.values.forEach { $0.removeFromParentNode() }
        bodyNodes.removeAll(); orbitNodes.removeAll()
        trajectories.removeAll()
    }
}

// MARK: — ArcHorizonsPanel (SwiftUI)

struct ArcHorizonsPanel: View {
    @StateObject private var engine = ArcHorizonsEngine.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "globe.americas.fill")
                    .foregroundColor(themeVM.accent).font(.system(size:11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("HORIZONS TRAJECTORY")
                        .font(.system(size:9,weight:.black,design:.monospaced))
                        .foregroundColor(themeVM.accent).tracking(2)
                    Text("JPL Horizons API v1.3 · Real-time ephemeris")
                        .font(.system(size:6.5,design:.monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer()
                if engine.isLoading {
                    ProgressView().scaleEffect(0.6).tint(themeVM.accent)
                } else {
                    Button { Task { await engine.fetchAll(scene: labVM.scene) } } label: {
                        Image(systemName:"arrow.clockwise").font(.system(size:11))
                            .foregroundColor(themeVM.accent)
                    }
                }
            }
            .padding(.horizontal,12).padding(.vertical,8)
            .background(Color.white.opacity(0.04))

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment:.leading, spacing:10) {

                    if let err = engine.errorMessage {
                        Text(err).font(.system(size:8,design:.monospaced))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(6).background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius:5))
                    }

                    // Body selector
                    sectionTitle("SELECT BODIES")
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())], spacing:4) {
                        ForEach(ArcCelestialBody.catalog.prefix(15)) { body in
                            let selected = engine.selectedBodies.contains(body.id)
                            Button {
                                if selected { engine.selectedBodies.removeAll{$0==body.id} }
                                else { engine.selectedBodies.append(body.id) }
                            } label: {
                                VStack(spacing:1) {
                                    Text(body.symbol).font(.system(size:12))
                                    Text(body.name).font(.system(size:6.5,weight:.semibold,design:.monospaced))
                                }
                                .frame(maxWidth:.infinity).padding(5)
                                .background(selected ? Color(body.color).opacity(0.22) : Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius:6))
                                .overlay(RoundedRectangle(cornerRadius:6)
                                    .stroke(selected ? Color(body.color).opacity(0.55) : Color.white.opacity(0.08), lineWidth:1))
                            }
                            .foregroundColor(selected ? Color(body.color) : .white.opacity(0.6))
                        }
                    }

                    // Time step
                    sectionTitle("TIME STEP PER NOTCH")
                    HStack(spacing:4) {
                        ForEach(ArcTimeStep.allCases) { step in
                            Button(step.rawValue) { engine.timeStep = step }
                                .font(.system(size:7.5,weight:.bold,design:.monospaced))
                                .padding(.horizontal,6).padding(.vertical,4)
                                .background(engine.timeStep == step
                                    ? themeVM.accent.opacity(0.2) : Color.white.opacity(0.05))
                                .foregroundColor(engine.timeStep == step ? themeVM.accent : .white.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius:4))
                        }
                    }

                    // Trajectory scrubber
                    sectionTitle("EPOCH SCRUBBER")
                    VStack(spacing:4) {
                        HStack {
                            Text("PAST").font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.3))
                            Slider(value: Binding(
                                get: { Double(engine.scrubberOffset + engine.totalSteps/2) },
                                set: { engine.scrubberOffset = Int($0) - engine.totalSteps/2;
                                       engine.updateScrubPosition() }
                            ), in: 0...Double(engine.totalSteps))
                            .tint(themeVM.accent)
                            Text("FUTURE").font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.3))
                        }
                        HStack {
                            Image(systemName:"clock").font(.system(size:8)).foregroundColor(themeVM.accent.opacity(0.6))
                            Text(engine.currentEpoch)
                                .font(.system(size:8.5,weight:.semibold,design:.monospaced))
                                .foregroundColor(themeVM.accent)
                            Spacer()
                            Button("NOW") {
                                engine.scrubberOffset = 0
                                engine.updateScrubPosition()
                            }
                            .font(.system(size:8,weight:.bold,design:.monospaced))
                            .padding(.horizontal,7).padding(.vertical,3)
                            .background(themeVM.accent.opacity(0.15))
                            .foregroundColor(themeVM.accent)
                            .clipShape(Capsule())
                        }
                    }

                    // Live trajectory readout
                    if !engine.trajectories.isEmpty {
                        sectionTitle("LIVE POSITION")
                        ForEach(engine.trajectories, id:\.bodyId) { traj in
                            if let pt = traj.points[safe: traj.currentIndex + engine.scrubberOffset] {
                                let body = ArcCelestialBody.catalog.first{$0.id == traj.bodyId}
                                HStack {
                                    Text(body?.symbol ?? "?").font(.system(size:12))
                                    VStack(alignment:.leading, spacing:2) {
                                        Text(traj.bodyName)
                                            .font(.system(size:8.5,weight:.bold,design:.monospaced))
                                            .foregroundColor(Color(body?.color ?? .white))
                                        Text(String(format:"X:%.4f Y:%.4f Z:%.4f AU", pt.x, pt.y, pt.z))
                                            .font(.system(size:7,design:.monospaced))
                                            .foregroundColor(.white.opacity(0.4))
                                        Text(String(format:"Dist: %.4f AU | V:%.4f AU/day", pt.distAU,
                                                    sqrt(pt.vx*pt.vx+pt.vy*pt.vy+pt.vz*pt.vz)))
                                            .font(.system(size:7,design:.monospaced))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                }
                                .padding(6)
                                .background(Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius:5))
                            }
                        }
                    }

                    // Orbit toggle
                    HStack {
                        Toggle("Show Orbit Paths", isOn: $engine.showOrbits)
                            .tint(themeVM.accent)
                            .font(.system(size:8.5,design:.monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    // Fetch button
                    Button {
                        Task { await engine.fetchAll(scene: labVM.scene) }
                    } label: {
                        HStack(spacing:8) {
                            Image(systemName:"paperplane.fill").font(.system(size:11))
                            Text(engine.isLoading ? "FETCHING..." : "LOAD TRAJECTORIES")
                                .font(.system(size:10,weight:.black,design:.monospaced)).tracking(1)
                        }
                        .frame(maxWidth:.infinity).padding(.vertical,9)
                        .background(themeVM.accent.opacity(0.15))
                        .foregroundColor(themeVM.accent)
                        .clipShape(RoundedRectangle(cornerRadius:8))
                        .overlay(RoundedRectangle(cornerRadius:8)
                            .stroke(themeVM.accent.opacity(0.4),lineWidth:1))
                    }
                    .disabled(engine.isLoading)
                }
                .padding(10)
            }
        }
        .background(Color(red:0.02,green:0.04,blue:0.10).opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius:12))
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size:7.5,weight:.bold,design:.monospaced))
            .foregroundColor(.white.opacity(0.3)).tracking(1.5)
    }
}

// Safe subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
