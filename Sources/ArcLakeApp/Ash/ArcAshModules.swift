import SwiftUI
import SceneKit
import Combine
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcAshModule — one independently serialisable slice of app state.
//
// Every module captures to / applies from a "settings" JSON object
// shaped {"global": {...}, "parts": {"<partKey>": {...}}, ...extras}.
// That is exactly the `settings` block of the shared module-preset
// schema, so a module can be exported/imported on its own without
// touching the rest of the .ash.
// ═══════════════════════════════════════════════════════════════════

@MainActor
public protocol ArcAshModule: AnyObject {
    var moduleID: String { get }
    var moduleVersion: Int { get }
    /// false for views onto another module's data (e.g. "thermal" ⊂ "fluid"):
    /// importable/exportable as a preset but not stored as its own .ash entry.
    var storedInDocument: Bool { get }
    /// Content modules are reset to defaults on New / Open; settings modules
    /// (theme, render, camera, ui, physics) are only touched if present in the file.
    var isContent: Bool { get }
    func capture() -> ArcJSON
    func apply(_ settings: ArcJSON) async
    func resetDefaults()
}

public extension ArcAshModule {
    var storedInDocument: Bool { true }
    var isContent: Bool { false }
    func resetDefaults() {}
}

/// Case-insensitive raw-value lookup (accepts "liquid" for "Liquid", etc.).
func arcAshEnum<E: CaseIterable & RawRepresentable>(_ s: String?, _ type: E.Type) -> E?
    where E.RawValue == String {
    guard let s else { return nil }
    if let e = E(rawValue: s) { return e }
    let low = s.lowercased()
    return E.allCases.first { $0.rawValue.lowercased() == low }
}

// MARK: — Theme
@MainActor
final class ArcAshThemeModule: ArcAshModule {
    let moduleID = "theme"
    let moduleVersion = 1
    private let themeVM: ArcThemeViewModel
    init(themeVM: ArcThemeViewModel) { self.themeVM = themeVM }

    func capture() -> ArcJSON {
        var g = ArcJB()
        g.str("theme", themeVM.current.rawValue)
        return .object(["global": g.json])
    }
    func apply(_ settings: ArcJSON) async {
        if let t = arcAshEnum(settings.global.str("theme"), ArcThemeViewModel.Theme.self) {
            themeVM.current = t
        }
    }
}

// MARK: — Render (ArcRenderSystem)
@MainActor
final class ArcAshRenderModule: ArcAshModule {
    let moduleID = "render"
    let moduleVersion = 1
    private let labVM: ArcLabViewModel
    init(labVM: ArcLabViewModel) { self.labVM = labVM }

    private func lightJSON(_ l: ArcLight) -> ArcJSON {
        var b = ArcJB()
        b.str("type", l.type.rawValue)
        b.str("name", l.name)
        b.str("color", ArcAshColor.hex(l.color))
        b.num("intensity", l.intensity)
        b.flag("castsShadow", l.castsShadow)
        b.num("shadowRadius", l.shadowRadius)
        b.num("softness", l.softness)
        b.num("coneAngle", l.coneAngle)
        b.flag("enabled", l.enabled)
        return b.json
    }
    private func light(from j: ArcJSON) -> ArcLight {
        var l = ArcLight()
        if let t = arcAshEnum(j.str("type"), ArcLightType.self) { l.type = t }
        if let v = j.str("name") { l.name = v }
        if let v = j.str("color"), let c = ArcAshColor.color(v) { l.color = c }
        if let v = j.cgf("intensity") { l.intensity = v }
        if let v = j.flag("castsShadow") { l.castsShadow = v }
        if let v = j.cgf("shadowRadius") { l.shadowRadius = v }
        if let v = j.cgf("softness") { l.softness = v }
        if let v = j.cgf("coneAngle") { l.coneAngle = v }
        if let v = j.flag("enabled") { l.enabled = v }
        return l
    }

    func capture() -> ArcJSON {
        let r = ArcRenderViewModel.shared
        var g = ArcJB()
        g.set("lights", .array(r.lights.map { lightJSON($0) }))
        g.flag("ssrEnabled", r.ssrEnabled)
        g.flag("ssgiEnabled", r.ssgiEnabled)
        g.flag("aoEnabled", r.aoEnabled)
        g.num("aoStrength", r.aoStrength)
        g.num("aoSize", r.aoSize)
        g.flag("postProcessEnabled", r.postProcessEnabled)
        g.str("toneMap", r.toneMap.rawValue)
        g.num("exposure", r.exposure)
        g.num("saturation", r.saturation)
        g.num("contrast", r.contrast)
        g.flag("curvatureEnabled", r.curvatureEnabled)
        g.num("bloomIntensity", r.bloomIntensity)
        g.num("bloomThreshold", r.bloomThreshold)
        g.num("motionBlur", r.motionBlur)
        g.num("renderScale", r.renderScale)
        g.num("msaaLevel", r.msaaLevel)
        g.str("backgroundMode", r.backgroundMode.rawValue)
        g.str("backgroundColor", ArcAshColor.hex(r.backgroundColor))
        g.str("gradientTopColor", ArcAshColor.hex(r.gradientTopColor))
        g.str("gradientBottomColor", ArcAshColor.hex(r.gradientBottomColor))
        g.num("gradientFactor", r.gradientFactor)
        g.str("environmentPreset", r.environmentPreset.rawValue)
        g.num("environmentIntensity", r.environmentIntensity)
        g.num("environmentContrast", r.environmentContrast)
        return .object(["global": g.json])
    }

    func apply(_ settings: ArcJSON) async {
        let r = ArcRenderViewModel.shared
        let g = settings.global
        if let arr = g.list("lights"), !arr.isEmpty { r.lights = arr.map { light(from: $0) } }
        if let v = g.flag("ssrEnabled") { r.ssrEnabled = v }
        if let v = g.flag("ssgiEnabled") { r.ssgiEnabled = v }
        if let v = g.flag("aoEnabled") { r.aoEnabled = v }
        if let v = g.cgf("aoStrength") { r.aoStrength = v }
        if let v = g.cgf("aoSize") { r.aoSize = v }
        if let v = g.flag("postProcessEnabled") { r.postProcessEnabled = v }
        if let v = arcAshEnum(g.str("toneMap"), ArcToneMap.self) { r.toneMap = v }
        if let v = g.cgf("exposure") { r.exposure = v }
        if let v = g.cgf("saturation") { r.saturation = v }
        if let v = g.cgf("contrast") { r.contrast = v }
        if let v = g.flag("curvatureEnabled") { r.curvatureEnabled = v }
        if let v = g.cgf("bloomIntensity") { r.bloomIntensity = v }
        if let v = g.cgf("bloomThreshold") { r.bloomThreshold = v }
        if let v = g.cgf("motionBlur") { r.motionBlur = v }
        if let v = g.cgf("renderScale") { r.renderScale = v }
        if let v = g.integer("msaaLevel") { r.msaaLevel = v }
        if let v = arcAshEnum(g.str("backgroundMode"), ArcBackgroundMode.self) { r.backgroundMode = v }
        if let s = g.str("backgroundColor"), let c = ArcAshColor.color(s) { r.backgroundColor = c }
        if let s = g.str("gradientTopColor"), let c = ArcAshColor.color(s) { r.gradientTopColor = c }
        if let s = g.str("gradientBottomColor"), let c = ArcAshColor.color(s) { r.gradientBottomColor = c }
        if let v = g.cgf("gradientFactor") { r.gradientFactor = v }
        if let v = arcAshEnum(g.str("environmentPreset"), ArcEnvironmentPreset.self) { r.environmentPreset = v }
        if let v = g.cgf("environmentIntensity") { r.environmentIntensity = v }
        if let v = g.cgf("environmentContrast") { r.environmentContrast = v }
        // Re-apply to the live view + the active scene.
        r.applyNow()
        r.applyLights(to: labVM.scene)
        r.applyBackground(to: labVM.scene)
    }
}

// MARK: — Camera
@MainActor
final class ArcAshCameraModule: ArcAshModule {
    let moduleID = "camera"
    let moduleVersion = 1

    func capture() -> ArcJSON {
        let m = ArcCameraManager.shared
        var g = ArcJB()
        g.set("cameras", ArcJSON.from(m.cameras))
        if let id = m.activeCameraId { g.str("activeCameraId", id.uuidString) } else { g.set("activeCameraId", .null) }
        g.flag("isOrtho", m.isOrtho)
        g.num("fov", m.fov)
        if let st = m.getCameraState?() {
            var c = ArcJB()
            c.vec("q", [Double(st.camQ.imag.x), Double(st.camQ.imag.y), Double(st.camQ.imag.z), Double(st.camQ.real)])
            c.num("radius", st.radius)
            c.vec("pivot", [Double(st.pivot.x), Double(st.pivot.y), Double(st.pivot.z)])
            c.num("fov", st.fov)
            c.flag("isOrtho", st.isOrtho)
            g.set("view", c.json)
        }
        return .object(["global": g.json])
    }

    func apply(_ settings: ArcJSON) async {
        let m = ArcCameraManager.shared
        let g = settings.global
        if let arr = g.list("cameras"), let cams = ArcJSON.array(arr).decode([ArcCamera].self) {
            m.cameras = cams
        }
        if let s = g.str("activeCameraId") { m.activeCameraId = UUID(uuidString: s) }
        if let v = g.flag("isOrtho") { m.isOrtho = v }
        if let v = g.dbl("fov") { m.fov = v }
        if let view = g.dict("view"), let q = view.list("q")?.compactMap({ $0.doubleValue }), q.count == 4,
           let p = view.list("pivot")?.compactMap({ $0.doubleValue }), p.count == 3 {
            let state = ArcCameraState(
                camQ: simd_quatf(ix: Float(q[0]), iy: Float(q[1]), iz: Float(q[2]), r: Float(q[3])),
                radius: view.flt("radius") ?? 10,
                pivot: SIMD3<Float>(Float(p[0]), Float(p[1]), Float(p[2])),
                fov: view.dbl("fov") ?? 60,
                isOrtho: view.flag("isOrtho") ?? false)
            // The SCNView coordinator may not exist yet (launch) — retry in the
            // background without holding up the rest of the restore.
            if let set = m.setCameraState {
                set(state, false)
            } else {
                Task { @MainActor in
                    for _ in 0..<20 {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if let set = ArcCameraManager.shared.setCameraState { set(state, false); break }
                    }
                }
            }
        }
    }
}

// MARK: — UI / tab layout / viewport
@MainActor
final class ArcAshUIModule: ArcAshModule {
    let moduleID = "ui"
    let moduleVersion = 1
    private let labVM: ArcLabViewModel
    init(labVM: ArcLabViewModel) { self.labVM = labVM }

    func capture() -> ArcJSON {
        var g = ArcJB()
        g.str("activeTab", labVM.activeTab.rawValue)
        g.num("activeTabIndex", labVM.activeTabIndex)
        var tabs: [ArcJSON] = []
        for (i, n) in labVM.sceneTabs_data.enumerated() {
            var t = ArcJB()
            t.str("name", n)
            t.flag("cfd", i < labVM.sceneTabsCFD.count ? labVM.sceneTabsCFD[i] : false)
            tabs.append(t.json)
        }
        g.set("sceneTabs", .array(tabs))
        g.flag("showGrid", labVM.showGrid)
        g.flag("showGridXZ", labVM.showGridXZ)
        g.flag("showGridXY", labVM.showGridXY)
        g.flag("showGridYZ", labVM.showGridYZ)
        g.num("gridDivisions", labVM.gridDivisions)
        g.flag("showFloor", labVM.showFloor)
        g.flag("showAxisLabels", labVM.showAxisLabels)
        g.flag("showAxisIndicators", labVM.showAxisIndicators)
        g.str("unitSystem", labVM.unitSystem.rawValue)
        return .object(["global": g.json])
    }

    func apply(_ settings: ArcJSON) async {
        let g = settings.global
        if let tabs = g.list("sceneTabs"), !tabs.isEmpty {
            var guardCount = 0
            while labVM.sceneTabs_data.count < tabs.count && guardCount < 30 {
                labVM.addSceneTab(); guardCount += 1
            }
            while labVM.sceneTabs_data.count > tabs.count && labVM.sceneTabs_data.count > 1 {
                labVM.removeSceneTab(labVM.sceneTabs_data.count - 1)
            }
            for (i, t) in tabs.enumerated() where i < labVM.sceneTabs_data.count {
                if let n = t.str("name") { labVM.sceneTabs_data[i] = n }
            }
        }
        if let idx = g.integer("activeTabIndex"), idx >= 0, idx < labVM.sceneTabs_data.count,
           idx != labVM.activeTabIndex {
            labVM.switchTab(idx)
        }
        if let t = arcAshEnum(g.str("activeTab"), ArcTab.self) { labVM.activeTab = t }
        if let v = g.flag("showGrid") { labVM.showGrid = v }
        if let v = g.flag("showGridXZ") { labVM.showGridXZ = v }
        if let v = g.flag("showGridXY") { labVM.showGridXY = v }
        if let v = g.flag("showGridYZ") { labVM.showGridYZ = v }
        if let v = g.integer("gridDivisions"), v >= 2, v <= 200 { labVM.gridDivisions = v }
        if let v = g.flag("showFloor") { labVM.showFloor = v }
        if let v = g.flag("showAxisLabels") { labVM.showAxisLabels = v }
        if let v = g.flag("showAxisIndicators") { labVM.showAxisIndicators = v }
        if let u = arcAshEnum(g.str("unitSystem"), ArcLabViewModel.ArcUnitSystem.self) { labVM.unitSystem = u }
        labVM.rebuildGrid()
    }
}

// MARK: — Physics / environment
@MainActor
final class ArcAshPhysicsModule: ArcAshModule {
    let moduleID = "physics"
    let moduleVersion = 1
    private let labVM: ArcLabViewModel
    init(labVM: ArcLabViewModel) { self.labVM = labVM }

    func capture() -> ArcJSON {
        let p = labVM.physics
        var g = ArcJB()
        g.num("temperature", p.temperature)
        g.num("gravity", p.gravity)
        g.num("pressure", p.pressure)
        g.num("velocity", p.velocity)
        g.num("viscosity", p.viscosity)
        g.num("magnetism", p.magnetism)
        g.num("electricField", p.electricField)
        g.num("stableForce", p.stableForce)
        g.str("matterState", labVM.matterState.rawValue)
        g.str("envPreset", labVM.envPreset.rawValue)
        g.num("windVelocity", labVM.windVelocity)
        g.str("windDirection", labVM.windDirection.rawValue)
        g.num("ptsPerComponent", labVM.ptsPerComponent)
        g.num("electronPointSize", labVM.electronPointSize)
        g.num("nucleonPointSize", labVM.nucleonPointSize)
        var tabs: [ArcJSON] = []
        for t in p.tabs {
            var b = ArcJB()
            b.num("temperature", t.temperature)
            b.num("gravity", t.gravity)
            b.num("pressure", t.pressure)
            b.num("velocity", t.velocity)
            b.num("viscosity", t.viscosity)
            b.num("humidity", t.humidity)
            b.num("altitude", t.altitude)
            b.num("particleCount", t.particleCount)
            tabs.append(b.json)
        }
        return .object(["global": g.json, "tabs": .array(tabs)])
    }

    func apply(_ settings: ArcJSON) async {
        let p = labVM.physics
        let g = settings.global
        if let v = g.dbl("temperature") { p.temperature = v }
        if let v = g.dbl("gravity") { p.gravity = v }
        if let v = g.dbl("pressure") { p.pressure = v }
        if let v = g.dbl("velocity") { p.velocity = v }
        if let v = g.dbl("viscosity") { p.viscosity = v }
        if let v = g.dbl("magnetism") { p.magnetism = v }
        if let v = g.dbl("electricField") { p.electricField = v }
        if let v = g.dbl("stableForce") { p.stableForce = v }
        if let v = arcAshEnum(g.str("matterState"), MatterState.self) { labVM.matterState = v }
        if let v = arcAshEnum(g.str("envPreset"), EnvPreset.self) { labVM.envPreset = v }
        if let v = g.dbl("windVelocity") { labVM.windVelocity = v }
        if let v = arcAshEnum(g.str("windDirection"), WindDir.self) { labVM.windDirection = v }
        // Resolution setters rebuild every atom — only touch them when they differ.
        if let v = g.integer("ptsPerComponent"), v >= 1, v <= 3000, v != labVM.ptsPerComponent {
            labVM.ptsPerComponent = v
        }
        if let v = g.cgf("electronPointSize"), abs(v - labVM.electronPointSize) > 1e-6 {
            labVM.electronPointSize = v
        }
        if let v = g.cgf("nucleonPointSize"), abs(v - labVM.nucleonPointSize) > 1e-6 {
            labVM.nucleonPointSize = v
        }
        if let tabs = settings.list("tabs") {
            for (i, t) in tabs.enumerated() where i < p.tabs.count {
                var tab = p.tabs[i]
                if let v = t.dbl("temperature") { tab.temperature = v }
                if let v = t.dbl("gravity") { tab.gravity = v }
                if let v = t.dbl("pressure") { tab.pressure = v }
                if let v = t.dbl("velocity") { tab.velocity = v }
                if let v = t.dbl("viscosity") { tab.viscosity = v }
                if let v = t.dbl("humidity") { tab.humidity = v }
                if let v = t.dbl("altitude") { tab.altitude = v }
                if let v = t.integer("particleCount") { tab.particleCount = v }
                p.tabs[i] = tab
            }
        }
    }
}

// MARK: — Algebra (math sets) + Arc Edge settings
@MainActor
final class ArcAshAlgebraModule: ArcAshModule {
    let moduleID = "algebra"
    let moduleVersion = 1
    var isContent: Bool { true }
    private let labVM: ArcLabViewModel
    init(labVM: ArcLabViewModel) { self.labVM = labVM }

    func resetDefaults() {
        labVM.mathSets = [ArcMathSet(), ArcMathSet(), ArcMathSet(), ArcMathSet()]
        labVM.mathSigma = 0
        labVM.mathChain = []
        labVM.mathSigmaEnv = false
    }

    func capture() -> ArcJSON {
        var g = ArcJB()
        var sets: [ArcJSON] = []
        for s in labVM.mathSets {
            var b = ArcJB()
            if let a = s.atomA { b.num("atomA", a) }
            if let a = s.atomB { b.num("atomB", a) }
            b.str("compA", s.compA)
            b.str("compB", s.compB)
            b.str("op", s.op)
            b.flag("radical", s.radical)
            b.num("radN", s.radN)
            b.flag("vsEnv", s.vsEnv)
            b.flag("linked", s.linked)
            sets.append(b.json)
        }
        g.set("mathSets", .array(sets))
        g.num("mathSigma", labVM.mathSigma)
        g.set("mathChain", .array(labVM.mathChain.map { ArcJSON.string($0) }))
        g.flag("mathSigmaEnv", labVM.mathSigmaEnv)
        g.num("arcDOC", labVM.arcDOC)
        g.num("sigmaMX", labVM.sigmaMX)
        g.num("sigmaMY", labVM.sigmaMY)
        g.num("sigmaMZ", labVM.sigmaMZ)
        g.flag("meridianJoinXZ", labVM.meridianJoinXZ)
        g.flag("meridianJoinXY", labVM.meridianJoinXY)
        g.flag("meridianJoinZY", labVM.meridianJoinZY)
        g.str("arcPhysicsPipe", labVM.arcPhysicsPipe.rawValue)
        g.set("arcFieldComponents", .array(labVM.arcFieldComponents.map { ArcJSON.string($0.rawValue) }
            .sorted { ($0.stringValue ?? "") < ($1.stringValue ?? "") }))
        g.num("arcMeasureResolution", labVM.arcMeasureResolution)
        g.flag("arcClosedLoop", labVM.arcClosedLoop)
        g.str("arcMeasureMode", labVM.arcMeasureMode.rawValue)
        g.flag("arcSameKindFilter", labVM.arcSameKindFilter)
        return .object(["global": g.json])
    }

    func apply(_ settings: ArcJSON) async {
        let g = settings.global
        if let arr = g.list("mathSets"), !arr.isEmpty {
            var sets: [ArcMathSet] = []
            for j in arr {
                var s = ArcMathSet()
                s.atomA = j.integer("atomA")
                s.atomB = j.integer("atomB")
                if let v = j.str("compA") { s.compA = v }
                if let v = j.str("compB") { s.compB = v }
                if let v = j.str("op") { s.op = v }
                if let v = j.flag("radical") { s.radical = v }
                if let v = j.dbl("radN") { s.radN = v }
                if let v = j.flag("vsEnv") { s.vsEnv = v }
                if let v = j.flag("linked") { s.linked = v }
                sets.append(s)
            }
            labVM.mathSets = sets
        }
        if let v = g.dbl("mathSigma") { labVM.mathSigma = v }
        if let arr = g.list("mathChain") { labVM.mathChain = arr.compactMap { $0.stringValue } }
        if let v = g.flag("mathSigmaEnv") { labVM.mathSigmaEnv = v }
        if let v = g.dbl("arcDOC") { labVM.arcDOC = v }
        if let v = g.dbl("sigmaMX") { labVM.sigmaMX = v }
        if let v = g.dbl("sigmaMY") { labVM.sigmaMY = v }
        if let v = g.dbl("sigmaMZ") { labVM.sigmaMZ = v }
        if let v = g.flag("meridianJoinXZ") { labVM.meridianJoinXZ = v }
        if let v = g.flag("meridianJoinXY") { labVM.meridianJoinXY = v }
        if let v = g.flag("meridianJoinZY") { labVM.meridianJoinZY = v }
        if let v = arcAshEnum(g.str("arcPhysicsPipe"), ArcLabViewModel.ArcPipeMode.self) { labVM.arcPhysicsPipe = v }
        if let arr = g.list("arcFieldComponents") {
            let set = Set(arr.compactMap { arcAshEnum($0.stringValue, ArcComponentField.self) })
            if !set.isEmpty { labVM.arcFieldComponents = set }
        }
        if let v = g.integer("arcMeasureResolution"), v >= 2, v <= 400 { labVM.arcMeasureResolution = v }
        if let v = g.flag("arcClosedLoop") { labVM.arcClosedLoop = v }
        if let v = arcAshEnum(g.str("arcMeasureMode"), ArcMeasureMode.self) { labVM.arcMeasureMode = v }
        if let v = g.flag("arcSameKindFilter") { labVM.arcSameKindFilter = v }
        labVM.rebuildGrid()
    }
}

// MARK: — Chemistry (elements, Mol canvas, compound library)
@MainActor
final class ArcAshChemistryModule: ArcAshModule {
    let moduleID = "chemistry"
    let moduleVersion = 1
    var isContent: Bool { true }
    private let labVM: ArcLabViewModel
    init(labVM: ArcLabViewModel) { self.labVM = labVM }

    func resetDefaults() {
        if !labVM.selectedElements.isEmpty { labVM.clearElements() }
        labVM.molAtoms = []
        labVM.molBonds = []
        labVM.deltaConnections = []
        labVM.selectedMolAtomId = nil
    }

    func capture() -> ArcJSON {
        var g = ArcJB()
        g.set("elements", ArcJSON.from(labVM.selectedElements))
        var atoms: [ArcJSON] = []
        for a in labVM.molAtoms {
            var b = ArcJB()
            b.str("id", a.id.uuidString)
            b.str("symbol", a.symbol)
            b.num("atomicNumber", a.atomicNumber)
            b.str("color", ArcAshColor.hex(a.color))
            b.num("x", a.position.x)
            b.num("y", a.position.y)
            b.str("label", a.label)
            atoms.append(b.json)
        }
        g.set("molAtoms", .array(atoms))
        var bonds: [ArcJSON] = []
        for bd in labVM.molBonds {
            var b = ArcJB()
            b.str("from", bd.fromId.uuidString)
            b.str("to", bd.toId.uuidString)
            b.num("order", bd.order)
            b.flag("isDelta", bd.isDelta)
            bonds.append(b.json)
        }
        g.set("molBonds", .array(bonds))
        var deltas: [ArcJSON] = []
        for d in labVM.deltaConnections {
            var b = ArcJB()
            b.str("from", d.fromAtomId.uuidString)
            b.str("to", d.toAtomId.uuidString)
            b.num("fromShell", d.fromShell)
            b.num("toShell", d.toShell)
            b.str("op", d.operator_)
            b.str("label", d.label)
            deltas.append(b.json)
        }
        g.set("deltaConnections", .array(deltas))
        g.num("molBondMode", labVM.molBondMode)
        g.flag("molDeltaMode", labVM.molDeltaMode)
        g.flag("molLabelMode", labVM.molLabelMode)
        g.set("compoundLibrary", ArcJSON.from(ArcCompoundLibrary.shared.compounds))
        return .object(["global": g.json])
    }

    func apply(_ settings: ArcJSON) async {
        let g = settings.global
        if let arr = g.list("elements"),
           let els = ArcJSON.array(arr).decode([ArcElement].self) {
            let want = els.map { $0.id }
            let have = labVM.selectedElements.map { $0.id }
            if want != have {
                if !labVM.selectedElements.isEmpty { labVM.clearElements() }
                for e in els { labVM.addElementInstance(e) }
            }
        }
        if let atomsJ = g.list("molAtoms") {
            var idMap: [String: UUID] = [:]
            var atoms: [MolAtomNode] = []
            for a in atomsJ {
                let sym = a.str("symbol") ?? "C"
                let col = ArcAshColor.color(a.str("color") ?? "") ?? UIColor.white
                let pt = CGPoint(x: a.dbl("x") ?? 0, y: a.dbl("y") ?? 0)
                var node = MolAtomNode(symbol: sym, z: a.integer("atomicNumber") ?? 6, color: col, at: pt)
                if let l = a.str("label") { node.label = l }
                if let old = a.str("id") { idMap[old] = node.id }
                atoms.append(node)
            }
            var bonds: [MolBond] = []
            for b in g.list("molBonds") ?? [] {
                guard let f = idMap[b.str("from") ?? ""], let t = idMap[b.str("to") ?? ""] else { continue }
                bonds.append(MolBond(from: f, to: t, order: b.integer("order") ?? 1,
                                     isDelta: b.flag("isDelta") ?? false))
            }
            var deltas: [DeltaConnection] = []
            for d in g.list("deltaConnections") ?? [] {
                guard let f = idMap[d.str("from") ?? ""], let t = idMap[d.str("to") ?? ""] else { continue }
                var dc = DeltaConnection(from: f, to: t, fromShell: d.integer("fromShell") ?? 0,
                                         toShell: d.integer("toShell") ?? 0, op: d.str("op") ?? "+")
                if let l = d.str("label") { dc.label = l }
                deltas.append(dc)
            }
            labVM.molAtoms = atoms
            labVM.molBonds = bonds
            labVM.deltaConnections = deltas
        }
        if let v = g.integer("molBondMode") { labVM.molBondMode = v }
        if let v = g.flag("molDeltaMode") { labVM.molDeltaMode = v }
        if let v = g.flag("molLabelMode") { labVM.molLabelMode = v }
        if let arr = g.list("compoundLibrary"),
           let list = ArcJSON.array(arr).decode([ArcSavedCompound].self) {
            ArcCompoundLibrary.shared.merge(list)   // additive: never deletes the user's own compounds
        }
    }
}

// MARK: — Mantis Navigation
@MainActor
final class ArcAshMantisModule: ArcAshModule {
    let moduleID = "mantis"
    let moduleVersion = 1
    var isContent: Bool { true }
    private let labVM: ArcLabViewModel
    init(labVM: ArcLabViewModel) { self.labVM = labVM }

    private func propJSON(_ p: MantisPropellant) -> ArcJSON {
        var b = ArcJB()
        b.num("psi", p.psi); b.num("atmPsi", p.atmPsi)
        b.num("dimX", p.dimX); b.num("dimY", p.dimY); b.num("dimZ", p.dimZ)
        b.num("massParts", p.massParts); b.num("weightPerPartG", p.weightPerPartG)
        b.num("density", p.density); b.num("valveAngle", p.valveAngle)
        b.num("maxFlow", p.maxFlow); b.num("tempF", p.tempF)
        return b.json
    }
    private func prop(from j: ArcJSON?, base: MantisPropellant) -> MantisPropellant {
        guard let j else { return base }
        var p = base
        if let v = j.dbl("psi") { p.psi = v }
        if let v = j.dbl("atmPsi") { p.atmPsi = v }
        if let v = j.dbl("dimX") { p.dimX = v }
        if let v = j.dbl("dimY") { p.dimY = v }
        if let v = j.dbl("dimZ") { p.dimZ = v }
        if let v = j.dbl("massParts") { p.massParts = v }
        if let v = j.dbl("weightPerPartG") { p.weightPerPartG = v }
        if let v = j.dbl("density") { p.density = v }
        if let v = j.dbl("valveAngle") { p.valveAngle = v }
        if let v = j.dbl("maxFlow") { p.maxFlow = v }
        if let v = j.dbl("tempF") { p.tempF = v }
        return p
    }

    func resetDefaults() {
        let m = labVM.mantis
        m.propSets = [MantisNavModel.PropSet()]
        m.vehicleAsset = nil
        m.hideOtherAssets = false
        m.chemistryMode = false
        m.isTrajectoryLinked = false
        m.trajectoryTargetId = "499"
        m.trajectoryTargetName = "Mars"
        m.trajectoryLinkedPropSetId = nil
    }

    func capture() -> ArcJSON {
        let m = labVM.mantis
        var g = ArcJB()
        g.flag("chemistryMode", m.chemistryMode)
        g.str("cameraMode", m.cameraMode.rawValue)
        g.str("envPreset", m.envPreset.rawValue)
        g.num("customG", m.customG)
        g.num("customPsi", m.customPsi)
        if let v = m.vehicleAsset { g.str("vehicleAsset", v) } else { g.set("vehicleAsset", .null) }
        g.flag("hideOtherAssets", m.hideOtherAssets)
        g.flag("isTrajectoryLinked", m.isTrajectoryLinked)
        g.str("trajectoryTargetId", m.trajectoryTargetId)
        g.str("trajectoryTargetName", m.trajectoryTargetName)
        g.flag("showTrajectorySection", m.showTrajectorySection)
        g.num("oxiFlow", m.oxiFlow)
        g.num("fuelFlow", m.fuelFlow)
        if let id = m.trajectoryLinkedPropSetId,
           let idx = m.propSets.firstIndex(where: { $0.id == id }) {
            g.num("trajectoryLinkedPropSetIndex", idx)
        } else {
            g.set("trajectoryLinkedPropSetIndex", .null)
        }
        var sets: [ArcJSON] = []
        for s in m.propSets {
            var b = ArcJB()
            b.set("oxidizer", propJSON(s.oxidizer))
            b.set("fuel", propJSON(s.fuel))
            b.num("depressPsi", s.depressPsi)
            b.num("depressAtmPsi", s.depressAtmPsi)
            if let a = s.assetName { b.str("assetName", a) }
            sets.append(b.json)
        }
        g.set("propSets", .array(sets))
        return .object(["global": g.json])
    }

    func apply(_ settings: ArcJSON) async {
        let m = labVM.mantis
        let g = settings.global
        if let v = g.flag("chemistryMode") { m.chemistryMode = v }
        if let v = arcAshEnum(g.str("cameraMode"), MantisNavModel.CamMode.self) { m.cameraMode = v }
        if let v = arcAshEnum(g.str("envPreset"), MantisNavModel.MantisEnv.self) { m.envPreset = v }
        if let v = g.dbl("customG") { m.customG = v }
        if let v = g.dbl("customPsi") { m.customPsi = v }
        if let arr = g.list("propSets"), !arr.isEmpty {
            var sets: [MantisNavModel.PropSet] = []
            for j in arr {
                var s = MantisNavModel.PropSet()
                s.oxidizer = prop(from: j.dict("oxidizer"), base: s.oxidizer)
                s.fuel = prop(from: j.dict("fuel"), base: s.fuel)
                if let v = j.dbl("depressPsi") { s.depressPsi = v }
                if let v = j.dbl("depressAtmPsi") { s.depressAtmPsi = v }
                s.assetName = j.str("assetName")
                sets.append(s)
            }
            m.propSets = sets
            if let idx = g.integer("trajectoryLinkedPropSetIndex"), idx >= 0, idx < sets.count {
                m.trajectoryLinkedPropSetId = sets[idx].id
            }
        }
        if let v = g.flag("isTrajectoryLinked") { m.isTrajectoryLinked = v }
        if let v = g.str("trajectoryTargetId") { m.trajectoryTargetId = v }
        if let v = g.str("trajectoryTargetName") { m.trajectoryTargetName = v }
        if let v = g.flag("showTrajectorySection") { m.showTrajectorySection = v }
        if let v = g.dbl("oxiFlow") { m.oxiFlow = v }
        if let v = g.dbl("fuelFlow") { m.fuelFlow = v }
        m.vehicleAsset = g.str("vehicleAsset")
        if let v = g.flag("hideOtherAssets") { m.hideOtherAssets = v }
    }
}

// MARK: — Fluid / CFD (thermal + combustion mechanical flow)

/// Other code (e.g. the simulation port: forced seals, openings, atmosphere…)
/// can persist additional state WITHOUT touching this file: register a
/// capture/apply pair under a unique key. It is stored at
/// fluid.settings.global.extensions[key] and survives even when the
/// registering code is absent (unknown keys are preserved verbatim).
public struct ArcAshFluidExtension {
    public let capture: () -> ArcJSON
    public let apply: (ArcJSON) -> Void
    public init(capture: @escaping () -> ArcJSON, apply: @escaping (ArcJSON) -> Void) {
        self.capture = capture; self.apply = apply
    }
}
@MainActor
public enum ArcAshFluidExtensions {
    fileprivate static var registry: [String: ArcAshFluidExtension] = [:]
    public static func register(key: String, capture: @escaping () -> ArcJSON,
                                apply: @escaping (ArcJSON) -> Void) {
        registry[key] = ArcAshFluidExtension(capture: capture, apply: apply)
    }
}

@MainActor
final class ArcAshFluidModule: ArcAshModule {
    let moduleID = "fluid"
    let moduleVersion = 1
    var isContent: Bool { true }

    private let engine = ArcFluidEngine.shared
    /// Last known complete fluid settings (global + parts + anything unknown).
    /// Parts for models that aren't currently loaded stay here until they are.
    private(set) var desired: ArcJSON = .object([:])
    private var lastSpecNames: [String] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        engine.$componentSpecs
            .sink { [weak self] specs in
                let names = specs.map { $0.nodeName }
                Task { @MainActor [weak self] in self?.specsChanged(names) }
            }
            .store(in: &cancellables)
        engine.$isRunning
            .sink { [weak self] running in
                if running { Task { @MainActor [weak self] in self?.applyDesiredParts() } }
            }
            .store(in: &cancellables)
    }

    func resetDefaults() {
        desired = .object([:])
        engine.mode = .liquid
        engine.scenePreset = .dam
        engine.particleVisual = .volumetric
        engine.particleCount = 500
        engine.gravityScale = 1.0
        engine.smoothingH = 1.5
        engine.autoSealEnabled = true
        engine.liveLeaksEnabled = true
        engine.floorHeatEnabled = true
        engine.xrayGlow = true
        engine.continuousFlow = true
        engine.propulsion = .bell
    }

    private func specsChanged(_ names: [String]) {
        guard names != lastSpecNames else { return }
        lastSpecNames = names
        applyDesiredParts()
    }

    // MARK: part <-> JSON
    static func alloyJSON(_ a: ArcAlloySpec) -> ArcJSON {
        var b = ArcJB()
        b.str("name", a.name)
        b.num("densityKgM3", a.densityKgM3)
        b.num("thermalConductivity", a.thermalConductivity)
        b.num("tensileStrengthMPa", a.tensileStrengthMPa)
        b.num("maxTempK", a.maxTempK)
        b.num("maxPressureMPa", a.maxPressureMPa)
        b.num("specificHeat", a.specificHeat)
        b.num("emissivity", a.emissivity)
        b.num("modulusGPa", a.modulusGPa)
        b.str("matId", a.matId)
        return b.json
    }
    static func apply(alloy j: ArcJSON, to a: inout ArcAlloySpec) {
        if let v = j.str("name") { a.name = v }
        if let v = j.first(["densityKgM3", "density"])?.doubleValue { a.densityKgM3 = v }
        if let v = j.first(["thermalConductivity", "conductivity"])?.doubleValue { a.thermalConductivity = v }
        if let v = j.dbl("tensileStrengthMPa") { a.tensileStrengthMPa = v }
        if let v = j.first(["maxTempK", "meltingPointK"])?.doubleValue { a.maxTempK = v }
        if let v = j.dbl("maxPressureMPa") { a.maxPressureMPa = v }
        if let v = j.dbl("specificHeat") { a.specificHeat = v }
        if let v = j.dbl("emissivity") { a.emissivity = v }
        if let v = j.dbl("modulusGPa") { a.modulusGPa = v }
        if let v = j.str("matId") { a.matId = v }
    }

    /// Only user-configured fields — never the computed/live ones
    /// (currentTempK, currentPressureMPa, stressLevel, thermalLoad), which
    /// would make every autosave look "changed".
    static func partJSON(_ s: ArcComponentSpec) -> ArcJSON {
        var b = ArcJB()
        b.str("name", s.displayName)
        b.set("alloy", alloyJSON(s.alloy))
        b.flag("isInlet", s.isInlet)
        b.flag("isOutlet", s.isOutlet)
        b.num("inletFlowRate", s.inletFlowRate)
        b.num("fillLevel", s.fillLevel)
        b.num("particleCapacity", s.particleCapacity)
        b.num("particlesPerM3Visible", s.particlesPerM3Visible)
        b.num("pressurePsi", s.pressurePsi)
        b.num("massKg", s.massKg)
        b.str("matId", s.matId)
        b.num("wallMm", s.wallMm)
        b.flag("isCombustionChamber", s.isCombustionChamber)
        if let f = s.fluidType { b.str("fluidType", f.rawValue) } else { b.set("fluidType", .null) }
        if let k = s.geometricKind { b.str("geometricKind", k.rawValue) } else { b.set("geometricKind", .null) }
        b.set("connectedContainerNames", .array(s.connectedContainerNames.map { ArcJSON.string($0) }))
        b.vec("bboxMin", [Double(s.boundingMin.x), Double(s.boundingMin.y), Double(s.boundingMin.z)])
        b.vec("bboxMax", [Double(s.boundingMax.x), Double(s.boundingMax.y), Double(s.boundingMax.z)])
        return b.json
    }

    static func apply(part j: ArcJSON, to s: inout ArcComponentSpec, alloyOnly: Bool = false) {
        if let m = j.str("matId"), let pre = ArcAlloySpec.preset(id: m) { s.alloy = pre }
        if let a = j.dict("alloy") {
            var al = s.alloy
            apply(alloy: a, to: &al)
            s.alloy = al
        }
        if alloyOnly { return }
        if let v = j.first(["isInlet", "inlet"])?.boolValue { s.isInlet = v }
        if let v = j.first(["isOutlet", "outlet"])?.boolValue { s.isOutlet = v }
        if let v = j.first(["inletFlowRate", "flowRate"])?.doubleValue { s.inletFlowRate = v }
        if let v = j.dbl("fillLevel") { s.fillLevel = min(1, max(0, v)) }
        if let v = j.integer("particleCapacity") { s.particleCapacity = max(1, v) }
        if let v = j.first(["particlesPerM3Visible", "particleDensity"])?.doubleValue { s.particlesPerM3Visible = Float(v) }
        if let v = j.first(["pressurePsi", "pressure_psi"])?.doubleValue { s.pressurePsi = v }
        if let v = j.first(["massKg", "mass"])?.doubleValue { s.massKg = max(0, v) }
        if let v = j.first(["wallMm", "wall_mm"])?.doubleValue { s.wallMm = min(200, max(0.05, v)) }
        if let v = j.first(["isCombustionChamber", "combustionChamber"])?.boolValue { s.isCombustionChamber = v }
        if let f = j.first(["fluidType", "fluid"])?.stringValue {
            s.fluidType = ArcCombustionFlow.FluidType(rawValue: f.capitalized)
        }
        if let k = j.first(["geometricKind", "kind", "classification"])?.stringValue,
           let kind = ArcGeometricClassifier.Kind(rawValue: k.lowercased()) {
            s.geometricKind = kind
        }
        if let arr = j.list("connectedContainerNames") {
            s.connectedContainerNames = arr.compactMap { $0.stringValue }
        }
    }

    // MARK: capture / apply
    func capture() -> ArcJSON {
        var g = ArcJB()
        g.str("mode", engine.mode.rawValue)
        g.str("scenePreset", engine.scenePreset.rawValue)
        g.str("particleVisual", engine.particleVisual.rawValue)
        g.num("particleCount", engine.particleCount)
        g.num("gravityScale", engine.gravityScale)
        g.num("smoothingH", engine.smoothingH)
        g.num("envTempK", engine.envTempK)
        g.num("envPressurePa", engine.envPressurePa)
        g.flag("autoSealEnabled", engine.autoSealEnabled)
        g.flag("liveLeaksEnabled", engine.liveLeaksEnabled)
        g.flag("floorHeatEnabled", engine.floorHeatEnabled)
        g.flag("xrayGlow", engine.xrayGlow)
        g.flag("continuousFlow", engine.continuousFlow)
        g.str("propulsion", engine.propulsion.rawValue)
        if !ArcAshFluidExtensions.registry.isEmpty {
            var ext: [String: ArcJSON] = [:]
            for (k, e) in ArcAshFluidExtensions.registry { ext[k] = e.capture() }
            g.set("extensions", .object(ext))
        }
        var parts: [String: ArcJSON] = [:]
        for s in engine.componentSpecs { parts[s.nodeName] = Self.partJSON(s) }
        let live: ArcJSON = .object(["global": g.json, "parts": .object(parts)])
        desired = desired.merged(with: live)
        return desired
    }

    func apply(_ settings: ArcJSON) async {
        desired = settings
        applyGlobals(settings.global)
        applyDesiredParts()
    }

    /// Used by the thermal view to keep `desired` consistent after a partial import.
    func mergeDesired(_ partial: ArcJSON) { desired = desired.merged(with: partial) }

    func applyGlobals(_ g: ArcJSON) {
        if let v = arcAshEnum(g.str("mode"), ArcFluidMode.self) { engine.mode = v }
        if let v = arcAshEnum(g.str("scenePreset"), ArcFluidScene.self) { engine.scenePreset = v }
        if let v = arcAshEnum(g.str("particleVisual"), ArcParticleVisual.self) { engine.particleVisual = v }
        if let v = g.first(["particleCount", "particles"])?.intValue { engine.particleCount = max(1, v) }
        if let v = g.dbl("gravityScale") { engine.gravityScale = Float(v) }
        if let v = g.dbl("smoothingH") { engine.smoothingH = Float(v) }
        if let v = g.first(["envTempK", "ambientTempK", "temperatureK", "tempK"])?.doubleValue { engine.envTempK = Float(v) }
        if let v = g.first(["envPressurePa", "ambientPressurePa", "pressurePa"])?.doubleValue { engine.envPressurePa = Float(v) }
        if let v = g.flag("autoSealEnabled") { engine.autoSealEnabled = v }
        if let v = g.flag("liveLeaksEnabled") { engine.liveLeaksEnabled = v }
        if let v = g.flag("floorHeatEnabled") { engine.floorHeatEnabled = v }
        if let v = g.flag("xrayGlow") { engine.xrayGlow = v }
        if let v = g.flag("continuousFlow") { engine.continuousFlow = v }
        if let v = arcAshEnum(g.str("propulsion"), ArcPropulsion.self) { engine.propulsion = v }
        if let ext = g.dict("extensions")?.objectValue {
            for (k, v) in ext { ArcAshFluidExtensions.registry[k]?.apply(v) }
        }
    }

    func applyDesiredParts(alloyOnly: Bool = false) {
        guard let parts = desired.parts.objectValue, !parts.isEmpty else { return }
        var specs = engine.componentSpecs
        guard !specs.isEmpty else { return }
        var changed = false
        for i in specs.indices {
            guard let pj = parts[specs[i].nodeName] else { continue }
            let before = Self.partJSON(specs[i])
            Self.apply(part: pj, to: &specs[i], alloyOnly: alloyOnly)
            if Self.partJSON(specs[i]) != before { changed = true }
        }
        if changed { engine.componentSpecs = specs }
    }
}

// MARK: — Thermal (a focused view onto the fluid module's thermal fields)
@MainActor
final class ArcAshThermalModule: ArcAshModule {
    let moduleID = "thermal"
    let moduleVersion = 1
    var storedInDocument: Bool { false }
    private let fluid: ArcAshFluidModule
    private let engine = ArcFluidEngine.shared
    init(fluid: ArcAshFluidModule) { self.fluid = fluid }

    func capture() -> ArcJSON {
        var g = ArcJB()
        g.num("envTempK", engine.envTempK)
        g.num("envPressurePa", engine.envPressurePa)
        g.flag("floorHeatEnabled", engine.floorHeatEnabled)
        var parts: [String: ArcJSON] = [:]
        for s in engine.componentSpecs {
            var b = ArcJB()
            b.set("alloy", ArcAshFluidModule.alloyJSON(s.alloy))
            parts[s.nodeName] = b.json
        }
        return .object(["global": g.json, "parts": .object(parts)])
    }

    func apply(_ settings: ArcJSON) async {
        let g = settings.global
        if let v = g.first(["envTempK", "ambientTempK", "temperatureK", "tempK"])?.doubleValue { engine.envTempK = Float(v) }
        if let v = g.first(["envPressurePa", "ambientPressurePa", "pressurePa"])?.doubleValue { engine.envPressurePa = Float(v) }
        if let v = g.flag("floorHeatEnabled") { engine.floorHeatEnabled = v }
        // Persist into the fluid module's state (alloy fields only) and apply to live parts.
        var partial: [String: ArcJSON] = [:]
        var gOut = ArcJB()
        gOut.num("envTempK", engine.envTempK)
        gOut.num("envPressurePa", engine.envPressurePa)
        gOut.flag("floorHeatEnabled", engine.floorHeatEnabled)
        partial["global"] = gOut.json
        var partsOut: [String: ArcJSON] = [:]
        for (k, v) in settings.parts.objectValue ?? [:] {
            if let a = v.dict("alloy") { partsOut[k] = .object(["alloy": a]) }
        }
        partial["parts"] = .object(partsOut)
        fluid.mergeDesired(.object(partial))
        fluid.applyDesiredParts(alloyOnly: true)
    }
}
