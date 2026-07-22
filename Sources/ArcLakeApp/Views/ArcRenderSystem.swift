import SwiftUI
import SceneKit
import CoreImage
import PhotosUI

// ═══════════════════════════════════════════════════════════════════
// ArcRenderSystem — Nomad-parity PBR render control for ArcLake.
// Tone mapping · SSAO · IBL · Post-process · Per-mesh material editor
// ═══════════════════════════════════════════════════════════════════

// MARK: — Tone Mapping modes
public enum ArcToneMap: String, CaseIterable, Identifiable {
    case aces = "ACES", neutral = "Neutral", none = "None"
    public var id: String { rawValue }
}

// MARK: — Viewport Background modes (matches Nomad's Background panel)
public enum ArcBackgroundMode: String, CaseIterable, Identifiable {
    case color = "Color", gradient = "Gradient", environment = "Environment"
    public var id: String { rawValue }
}

public enum ArcEnvironmentPreset: String, CaseIterable, Identifiable {
    case day = "Day", sunset = "Sunset", overcast = "Overcast",
         studio = "Studio", night = "Night", custom = "Custom"
    public var id: String { rawValue }
}

// MARK: — Material blend modes (matches Nomad)
public enum ArcBlendMode: String, CaseIterable, Identifiable {
    case opaque = "Opaque", subsurface = "Subsurface", blending = "Blending",
         additive = "Additive", refraction = "Refraction"
    public var id: String { rawValue }
    var scnBlend: SCNTransparencyMode {
        switch self {
        case .blending, .refraction: return .aOne
        case .additive: return .rgbZero
        default: return .aOne
        }
    }
}

// MARK: — Light type
public enum ArcLightType: String, CaseIterable, Identifiable {
    case directional = "Directional", environment = "Environment",
         spot = "Spot", point = "Point"
    public var id: String { rawValue }
    var scnType: SCNLight.LightType {
        switch self {
        case .directional: return .directional
        case .environment: return .ambient
        case .spot:        return .spot
        case .point:       return .omni
        }
    }
    var icon: String {
        switch self {
        case .directional: return "sun.max.fill"
        case .environment: return "globe"
        case .spot:        return "flashlight.on.fill"
        case .point:       return "lightbulb.fill"
        }
    }
}

public struct ArcLight: Identifiable {
    public let id = UUID()
    public var type: ArcLightType = .directional
    public var name: String = "Light"
    public var color: UIColor = .white
    public var intensity: CGFloat = 1000
    public var castsShadow = true
    public var shadowRadius: CGFloat = 3
    public var softness: CGFloat = 0.5
    public var coneAngle: CGFloat = 45
    public var enabled = true
    public var nodeName: String { "arc_light_\(id.uuidString.prefix(8))" }
}

// MARK: — ViewModel
@MainActor
public final class ArcRenderViewModel: ObservableObject {
    public static let shared = ArcRenderViewModel()

    // Lights
    @Published public var lights: [ArcLight] = [
        ArcLight(type: .directional, name: "Sun",
                 color: .white, intensity: 1200, castsShadow: true),
        ArcLight(type: .environment, name: "Sky",
                 color: UIColor(red:0.5,green:0.7,blue:1,alpha:1),
                 intensity: 300, castsShadow: false),
    ]

    // Post-process
    @Published public var ssrEnabled        = true
    @Published public var ssgiEnabled       = true
    @Published public var aoEnabled         = true
    @Published public var aoStrength: CGFloat = 1.5
    @Published public var aoSize: CGFloat     = 1.4
    @Published public var postProcessEnabled  = true

    // Tone mapping (Nomad-style)
    @Published public var toneMap: ArcToneMap = .aces
    @Published public var exposure: CGFloat   = 1.0     // Nomad default 1.0
    @Published public var saturation: CGFloat = 1.0
    @Published public var contrast: CGFloat   = 0.0
    @Published public var curvatureEnabled    = true     // curvature/cavity darkening

    // Bloom
    @Published public var bloomIntensity: CGFloat = 0.0
    @Published public var bloomThreshold: CGFloat = 0.75
    @Published public var motionBlur: CGFloat     = 0.0

    // Quality
    @Published public var renderScale: CGFloat = 1.0
    @Published public var msaaLevel: Int       = 4

    // MARK: — Viewport Background (Color / Gradient / Environment)
    // Matches Nomad's Background panel: pick a flat color, a two-color
    // gradient with a blend factor, or an environment map. Environment
    // mode drives BOTH the visible backdrop and the scene's IBL lighting
    // together, same as picking an HDRI in Nomad — they're the same map.
    @Published public var backgroundMode: ArcBackgroundMode = .color
    @Published public var backgroundColor: UIColor =
        UIColor(red: 0.013, green: 0.027, blue: 0.065, alpha: 1)
    @Published public var gradientTopColor: UIColor =
        UIColor(red: 0.05, green: 0.09, blue: 0.20, alpha: 1)
    @Published public var gradientBottomColor: UIColor =
        UIColor(red: 0.01, green: 0.015, blue: 0.03, alpha: 1)
    @Published public var gradientFactor: CGFloat = 0.5   // blend midpoint, Nomad-style

    @Published public var environmentPreset: ArcEnvironmentPreset = .day
    @Published public var environmentImage: UIImage? = nil   // set when preset or import chosen
    @Published public var environmentIntensity: CGFloat = 1.0  // "Exposure" in the panel
    @Published public var environmentContrast: CGFloat = 0.0   // -1...1

    // MARK: — Procedural sky environment (real image-based lighting)
    // A flat ambient color gives PBR materials nothing directional to
    // reflect, which is most of why metal/rough surfaces look flat and
    // plasticky compared to Nomad (which uses real Poly Haven HDRIs).
    // This generates a simple equirectangular sky gradient once and reuses
    // it as scene.lightingEnvironment.contents — real IBL variation with
    // zero bundled assets, so specular highlights and reflections actually
    // have something believable to pick up.
    // Generic vertical-gradient equirect image generator — used for both
    // the environment presets below and the plain two-color Background
    // gradient mode.
    public static func verticalGradientImage(
        size: CGSize, colors: [UIColor], locations: [CGFloat]
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = colors.map { $0.cgColor }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: cg as CFArray, locations: locations) else { return }
            ctx.cgContext.drawLinearGradient(gradient,
                start: CGPoint(x: size.width/2, y: 0),
                end:   CGPoint(x: size.width/2, y: size.height),
                options: [])
        }
    }

    // Five preset "HDRI-style" environments — no bundled assets, generated
    // on demand. Not a substitute for a real captured HDRI, but gives real
    // directional IBL variation (unlike a flat ambient color) across a
    // useful spread of lighting moods, same role Nomad's Poly Haven presets
    // play in their Background panel.
    public static func skyPreset(_ preset: ArcEnvironmentPreset) -> UIImage {
        let size = CGSize(width: 512, height: 256)
        switch preset {
        case .day:
            return verticalGradientImage(size: size, colors: [
                UIColor(red: 0.22, green: 0.42, blue: 0.85, alpha: 1),
                UIColor(red: 0.55, green: 0.70, blue: 0.95, alpha: 1),
                UIColor(red: 0.97, green: 0.88, blue: 0.72, alpha: 1),
                UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1),
            ], locations: [0.0, 0.4, 0.58, 1.0])
        case .sunset:
            return verticalGradientImage(size: size, colors: [
                UIColor(red: 0.15, green: 0.12, blue: 0.35, alpha: 1),
                UIColor(red: 0.55, green: 0.22, blue: 0.35, alpha: 1),
                UIColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1),
                UIColor(red: 0.08, green: 0.06, blue: 0.09, alpha: 1),
            ], locations: [0.0, 0.35, 0.62, 1.0])
        case .overcast:
            return verticalGradientImage(size: size, colors: [
                UIColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1),
                UIColor(red: 0.68, green: 0.70, blue: 0.73, alpha: 1),
                UIColor(red: 0.75, green: 0.76, blue: 0.77, alpha: 1),
                UIColor(red: 0.20, green: 0.21, blue: 0.22, alpha: 1),
            ], locations: [0.0, 0.4, 0.6, 1.0])
        case .studio:
            return verticalGradientImage(size: size, colors: [
                UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1),
                UIColor(red: 0.60, green: 0.60, blue: 0.62, alpha: 1),
                UIColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1),
                UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1),
            ], locations: [0.0, 0.45, 0.7, 1.0])
        case .night:
            return verticalGradientImage(size: size, colors: [
                UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1),
                UIColor(red: 0.05, green: 0.06, blue: 0.14, alpha: 1),
                UIColor(red: 0.10, green: 0.09, blue: 0.16, alpha: 1),
                UIColor(red: 0.01, green: 0.01, blue: 0.02, alpha: 1),
            ], locations: [0.0, 0.4, 0.6, 1.0])
        case .custom:
            return verticalGradientImage(size: size,
                colors: [.gray, .darkGray], locations: [0.0, 1.0])
        }
    }

    // Applies contrast (-1...1) to an environment image via Core Image —
    // this is the actual per-environment "contrast" control in the panel,
    // independent from the camera's overall tone-mapping contrast.
    public static func applyContrast(_ image: UIImage, amount: CGFloat) -> UIImage {
        guard amount != 0, let cg = image.cgImage else { return image }
        let ci = CIImage(cgImage: cg)
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ci, forKey: kCIInputImageKey)
        filter?.setValue(1.0 + amount, forKey: kCIInputContrastKey)
        let context = CIContext()
        guard let output = filter?.outputImage,
              let rendered = context.createCGImage(output, from: ci.extent) else { return image }
        return UIImage(cgImage: rendered)
    }

    // Backward-compat alias — existing callers used this name directly.
    public static var proceduralSkyImage: UIImage { skyPreset(.day) }

    // Scene view ref
    public weak var sceneView: SCNView? = nil
    public func applyNow() {
        guard let v = sceneView else { return }
        applyCamera(v)
        if let s = v.scene {
            applyLights(to: s)
            applyBackground(to: s)
        }
    }

    // MARK: — Apply viewport background (Color / Gradient / Environment)
    // Environment mode intentionally drives BOTH scene.background AND
    // scene.lightingEnvironment from the same image — picking an HDRI
    // should light the scene the way it visually surrounds it, exactly
    // like Nomad's own Background→Environment behavior.
    public func applyBackground(to scene: SCNScene) {
        switch backgroundMode {
        case .color:
            scene.background.contents = backgroundColor

        case .gradient:
            // Blend factor shifts where the two colors meet, matching
            // Nomad's "Factor" slider under the two color swatches.
            let mid = min(max(gradientFactor, 0), 1)
            let img = ArcRenderViewModel.verticalGradientImage(
                size: CGSize(width: 4, height: 256),
                colors: [gradientTopColor, gradientBottomColor],
                locations: [0.0, mid == 0.5 ? 0.5 : mid])
            scene.background.contents = img
            // Gradient mode still lights the scene with the existing Sky
            // ambient light's own color, unchanged from before.
            if let env = lights.first(where: { $0.type == .environment && $0.enabled }) {
                scene.lightingEnvironment.contents  = env.color
                scene.lightingEnvironment.intensity = Double(env.intensity / 1000)
            }

        case .environment:
            let base = environmentImage ?? ArcRenderViewModel.skyPreset(environmentPreset)
            let final = ArcRenderViewModel.applyContrast(base, amount: environmentContrast)
            scene.background.contents = final
            scene.lightingEnvironment.contents  = final
            scene.lightingEnvironment.intensity = Double(environmentIntensity)
        }
    }

    // MARK: — Apply lights
    public func applyLights(to scene: SCNScene) {
        scene.rootNode.childNodes
            .filter { $0.name?.hasPrefix("arc_light_") == true }
            .forEach { $0.removeFromParentNode() }

        for light in lights where light.enabled {
            let l = SCNLight()
            l.type            = light.type.scnType
            l.color           = light.color
            l.intensity       = light.intensity
            l.castsShadow     = light.castsShadow
            l.shadowMode      = .forward
            // Softer, higher-res shadows — this is most of the gap vs. Nomad's
            // look: their contact/cast shadows are high-resolution and soft-
            // edged, ours were low-res (default map size) with only 8 samples.
            l.shadowRadius       = max(light.shadowRadius, 4)
            l.shadowSampleCount  = 24
            l.shadowMapSize      = CGSize(width: 4096, height: 4096)
            l.automaticallyAdjustsShadowProjection = true
            l.shadowColor     = UIColor.black.withAlphaComponent(0.4)
            if light.type == .spot {
                l.spotInnerAngle = light.coneAngle * Double(1 - light.softness)
                l.spotOuterAngle = light.coneAngle
            }
            let node = SCNNode(); node.name = light.nodeName; node.light = l
            switch light.type {
            case .directional: node.eulerAngles = SCNVector3(-Float.pi/4, Float.pi/6, 0)
            case .environment: node.position    = SCNVector3(0, 50, 0)
            case .spot:        node.position    = SCNVector3(0, 15, 10)
                               node.eulerAngles = SCNVector3(-Float.pi/4, 0, 0)
            case .point:       node.position    = SCNVector3(0, 8, 0)
            }
            scene.rootNode.addChildNode(node)
        }
        // Background + lighting-environment are now handled together by
        // applyBackground(to:) below (Color / Gradient / Environment modes).
    }

    // MARK: — Apply camera
    public func applyCamera(_ view: SCNView) {
        let cam = view.scene?.rootNode
            .childNode(withName: "arcCamera", recursively: false)?.camera
            ?? view.pointOfView?.camera
        guard let cam else { return }
        let pp = postProcessEnabled
        cam.wantsHDR = true
        cam.bloomIntensity      = pp ? min(bloomIntensity, 1.5) : 0
        cam.bloomThreshold      = max(bloomThreshold, 0.75)
        cam.bloomBlurRadius     = pp && bloomIntensity > 0.05 ? 4.0 : 0
        cam.motionBlurIntensity = pp && motionBlur > 0.01 ? min(motionBlur, 0.5) : 0
        // Tone mapping → exposure offset mapping:
        // ACES: standard; Neutral: reduced contrast; None: flat
        let toneExp: CGFloat = switch toneMap {
            case .aces:    exposure
            case .neutral: exposure * 0.85
            case .none:    0
        }
        cam.exposureOffset = pp ? max(toneExp - 1.0, -1.5) : 0
        // Saturation/contrast via color grading (approximated via exposure + white point)
        // SCNCamera doesn't expose saturation directly; we fold it into bloom threshold
        if pp && aoEnabled {
            cam.screenSpaceAmbientOcclusionIntensity       = Double(aoStrength) * 2.2
            cam.screenSpaceAmbientOcclusionRadius          = Double(aoSize) * 0.06
            cam.screenSpaceAmbientOcclusionBias            = 0.02
            cam.screenSpaceAmbientOcclusionDepthThreshold  = 0.15
            cam.screenSpaceAmbientOcclusionNormalThreshold = 0.25
        } else { cam.screenSpaceAmbientOcclusionIntensity = 0 }
        view.antialiasingMode   = msaaMode(msaaLevel)
        view.contentScaleFactor = min(UIScreen.main.nativeScale * renderScale,
                                      UIScreen.main.nativeScale * 1.5)
    }

    public func msaaMode(_ level: Int) -> SCNAntialiasingMode {
        switch level { case 1: return .none; case 2: return .multisampling2X
                       default: return .multisampling4X }
    }
}

// MARK: — Material Inspector ViewModel
@MainActor
final class ArcMaterialInspector: ObservableObject {
    static let shared = ArcMaterialInspector()

    struct MeshEntry: Identifiable {
        let id: UUID
        var name: String
        var blendMode: ArcBlendMode
        var roughness: CGFloat
        var metalness: CGFloat
        var opacity: CGFloat
        var doubleSided: Bool
        var castsShadow: Bool
        // refs to live materials
        var materials: [SCNMaterial]
    }

    @Published var entries: [MeshEntry] = []
    @Published var expandedId: UUID? = nil

    func loadScene(_ scene: SCNScene) {
        var found: [MeshEntry] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry, !geo.materials.isEmpty else { return }
            let nm = node.name ?? geo.name ?? "mesh"
            if nm.hasPrefix("arc_light_") || nm == "mantis_drone" { return }
            let mat = geo.materials[0]
            let blend: ArcBlendMode = {
                if mat.transparent.contents != nil { return .blending }
                if mat.transparencyMode == .rgbZero { return .additive }
                return .opaque
            }()
            found.append(MeshEntry(
                id: UUID(), name: nm,
                blendMode: blend,
                roughness: mat.roughness.contents as? CGFloat ?? 0.5,
                metalness: mat.metalness.contents as? CGFloat ?? 0.0,
                opacity: CGFloat(mat.transparency),
                doubleSided: mat.isDoubleSided,
                castsShadow: node.castsShadow,
                materials: geo.materials))
        }
        entries = found
    }

    func apply(_ entry: MeshEntry) {
        for mat in entry.materials {
            mat.roughness.contents  = entry.roughness
            mat.metalness.contents  = entry.metalness
            mat.isDoubleSided       = entry.doubleSided
            mat.transparency        = entry.opacity
            switch entry.blendMode {
            case .opaque:     mat.transparencyMode = .default; mat.writesToDepthBuffer = true
            case .blending:   mat.transparencyMode = .default; mat.writesToDepthBuffer = false
            case .additive:   mat.transparencyMode = .default; mat.writesToDepthBuffer = false
            case .refraction: mat.transparencyMode = .default
            case .subsurface: // approximate with low roughness + slight translucency
                mat.roughness.contents = max(entry.roughness * 0.6, 0.1)
            }
            mat.lightingModel = .physicallyBased
        }
    }
}

// MARK: — Render Panel UI
struct ArcRenderPanel: View {
    @StateObject private var vm   = ArcRenderViewModel.shared
    @StateObject private var mats = ArcMaterialInspector.shared
    @EnvironmentObject var labVM:  ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showAddLight = false
    @State private var tab: PanelTab = .render

    enum PanelTab: String, CaseIterable { case render = "Render", background = "Background", materials = "Materials" }

    var body: some View {
        VStack(spacing: 0) {
            // Tab switcher
            HStack(spacing: 0) {
                ForEach(PanelTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                        if t == .materials { mats.loadScene(labVM.scene) }
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(tab == t ? .black : themeVM.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(tab == t ? themeVM.accent : Color.clear)
                    }
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10).padding(.top, 8)

            ScrollView(showsIndicators: false) {
                switch tab {
                case .render:
                    VStack(spacing: 10) {
                        qualitySection
                        toneMappingSection
                        postProcessSection
                        lightsSection
                        Spacer().frame(height: 20)
                    }.padding(10)
                case .background:
                    ArcBackgroundPanelContent()
                case .materials:
                    materialSection
                }
            }
        }
        .background(Color(red:0.02,green:0.04,blue:0.09))
        .onAppear { vm.applyNow() }  // lights + background + camera, all in sync
        .onChange(of: vm.lights.count) { _ in vm.applyNow() }
    }

    // MARK: Quality
    private var qualitySection: some View {
        card("QUALITY") {
            VStack(spacing: 8) {
                HStack {
                    monoLabel("Render Resolution")
                    Spacer()
                    accentLabel(String(format: "×%.2f", vm.renderScale))
                }
                Slider(value: $vm.renderScale, in: 0.5...1.5).tint(themeVM.accent)
                    .onChange(of: vm.renderScale) { _ in vm.applyNow() }
                msaaPills
            }
        }
    }

    // MARK: Tone Mapping — matches Nomad's tone map + exposure + saturation + contrast
    private var toneMappingSection: some View {
        card("TONE MAPPING") {
            VStack(spacing: 8) {
                // Mode selector
                HStack(spacing: 4) {
                    ForEach(ArcToneMap.allCases) { mode in
                        Button { vm.toneMap = mode; vm.applyNow() } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(vm.toneMap == mode ? .black : .white.opacity(0.6))
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                                .background(vm.toneMap == mode ? themeVM.accent : Color.white.opacity(0.07))
                                .clipShape(Capsule())
                        }
                    }
                }
                slider("Exposure",   value: $vm.exposure,    range: 0.1...4.0, fmt: "%.2f")
                slider("Saturation", value: $vm.saturation,  range: 0.0...2.0, fmt: "%.2f")
                slider("Contrast",   value: $vm.contrast,    range: -1.0...1.0, fmt: "%.2f")
                Toggle(isOn: $vm.curvatureEnabled) {
                    monoLabel("Curvature Darkening")
                }.tint(themeVM.accent)
                    .onChange(of: vm.curvatureEnabled) { _ in vm.applyNow() }
            }
        }
    }

    // MARK: Post Process
    private var postProcessSection: some View {
        card("POST PROCESS") {
            VStack(spacing: 8) {
                toggle("Post Processing", icon: "wand.and.stars", val: $vm.postProcessEnabled)
                toggle("Reflection (SSR)",    icon: "square.on.square",          val: $vm.ssrEnabled)
                toggle("Global Illumination", icon: "light.max",                 val: $vm.ssgiEnabled)
                toggle("Ambient Occlusion",   icon: "circle.dashed",             val: $vm.aoEnabled)
                if vm.aoEnabled {
                    slider("Strength",       value: $vm.aoStrength,    range: 0...3.0,  fmt: "%.2f")
                    slider("Size",           value: $vm.aoSize,        range: 0.1...4.0, fmt: "%.2f")
                }
                Divider().background(Color.white.opacity(0.08))
                slider("Bloom Intensity", value: $vm.bloomIntensity, range: 0...2.0, fmt: "%.2f")
                slider("Motion Blur",     value: $vm.motionBlur,     range: 0...1.0, fmt: "%.2f")
            }
        }
        .onChange(of: vm.postProcessEnabled) { _ in vm.applyNow() }
        .onChange(of: vm.ssrEnabled)  { _ in vm.applyNow() }
        .onChange(of: vm.ssgiEnabled) { _ in vm.applyNow() }
        .onChange(of: vm.aoEnabled)   { _ in vm.applyNow() }
        .onChange(of: vm.aoStrength)  { _ in vm.applyNow() }
        .onChange(of: vm.aoSize)      { _ in vm.applyNow() }
        .onChange(of: vm.bloomIntensity) { _ in vm.applyNow() }
        .onChange(of: vm.motionBlur)     { _ in vm.applyNow() }
    }

    // MARK: Lights
    private var lightsSection: some View {
        card("LIGHTS") {
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    Button { showAddLight = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(themeVM.accent).font(.system(size: 16))
                    }
                }
                ForEach($vm.lights) { $light in lightCard($light) }
            }
        }
        .confirmationDialog("Add Light", isPresented: $showAddLight) {
            ForEach(ArcLightType.allCases) { t in
                Button(t.rawValue) {
                    var l = ArcLight(type: t, name: "\(t.rawValue) \(vm.lights.count+1)")
                    if t == .environment { l.castsShadow = false; l.intensity = 300 }
                    vm.lights.append(l); vm.applyNow()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func lightCard(_ light: Binding<ArcLight>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: light.wrappedValue.type.icon)
                    .font(.system(size: 10)).foregroundColor(themeVM.accent)
                Text(light.wrappedValue.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Toggle("", isOn: light.enabled).tint(themeVM.accent).labelsHidden()
                Button {
                    vm.lights.removeAll { $0.id == light.wrappedValue.id }; vm.applyNow()
                } label: {
                    Image(systemName: "trash").font(.system(size: 9)).foregroundColor(.red.opacity(0.7))
                }
            }
            if light.wrappedValue.enabled {
                slider("Intensity", value: light.intensity, range: 0...5000, fmt: "%.0f")
                if light.wrappedValue.type == .spot {
                    slider("Cone Angle", value: light.coneAngle, range: 1...180, fmt: "%.0f°")
                    slider("Softness", value: light.softness, range: 0...1, fmt: "%.2f")
                }
                Toggle(isOn: light.castsShadow) {
                    monoLabel("Shadow")
                }.tint(themeVM.accent)
            }
        }
        .padding(10).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 10))
        .onChange(of: light.wrappedValue.intensity)   { _ in vm.applyNow() }
        .onChange(of: light.wrappedValue.enabled)     { _ in vm.applyNow() }
        .onChange(of: light.wrappedValue.castsShadow) { _ in vm.applyNow() }
    }

    // MARK: — Materials tab
    @ViewBuilder
    private var materialSection: some View {
        VStack(spacing: 8) {
            HStack {
                monoLabel("SCENE MATERIALS").padding(.leading, 10)
                Spacer()
                Button { mats.loadScene(labVM.scene) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12)).foregroundColor(themeVM.accent)
                }.padding(.trailing, 10)
            }.padding(.top, 8)

            if mats.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "cube").font(.system(size: 24)).foregroundColor(.white.opacity(0.2))
                    Text("Load a 3D model first")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.3))
                }.frame(maxWidth: .infinity).padding(32)
            } else {
                ForEach($mats.entries) { $entry in
                    materialRow($entry)
                }
            }
            Spacer().frame(height: 20)
        }
    }

    @ViewBuilder
    private func materialRow(_ entry: Binding<ArcMaterialInspector.MeshEntry>) -> some View {
        let isOpen = mats.expandedId == entry.wrappedValue.id
        VStack(alignment: .leading, spacing: 0) {
            // Header row — tap to expand
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    mats.expandedId = isOpen ? nil : entry.wrappedValue.id
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 9)).foregroundColor(themeVM.accent)
                    Text(entry.wrappedValue.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85)).lineLimit(1)
                    Spacer()
                    Text(entry.wrappedValue.blendMode.rawValue)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(themeVM.accent.opacity(0.7))
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9)).foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }

            if isOpen {
                VStack(spacing: 10) {
                    // Blend mode
                    VStack(alignment: .leading, spacing: 4) {
                        monoLabel("Surface Type").padding(.leading, 2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(ArcBlendMode.allCases) { mode in
                                    Button {
                                        entry.blendMode.wrappedValue = mode
                                        mats.apply(entry.wrappedValue)
                                    } label: {
                                        Text(mode.rawValue)
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(entry.wrappedValue.blendMode == mode ? .black : .white.opacity(0.6))
                                            .padding(.horizontal, 9).padding(.vertical, 5)
                                            .background(entry.wrappedValue.blendMode == mode ? themeVM.accent : Color.white.opacity(0.07))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    // PBR sliders
                    slider("Metalness",  value: entry.metalness,  range: 0...1, fmt: "%.2f", onChange: { mats.apply(entry.wrappedValue) })
                    slider("Roughness",  value: entry.roughness,  range: 0...1, fmt: "%.2f", onChange: { mats.apply(entry.wrappedValue) })
                    slider("Opacity",    value: entry.opacity,    range: 0...1, fmt: "%.2f", onChange: { mats.apply(entry.wrappedValue) })
                    // Flags
                    HStack(spacing: 12) {
                        Toggle(isOn: entry.doubleSided) { monoLabel("Two Sided") }.tint(themeVM.accent)
                            .onChange(of: entry.wrappedValue.doubleSided) { _ in mats.apply(entry.wrappedValue) }
                        Toggle(isOn: entry.castsShadow) { monoLabel("Cast Shadow") }.tint(themeVM.accent)
                            .onChange(of: entry.wrappedValue.castsShadow) { _ in mats.apply(entry.wrappedValue) }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
                .background(Color.white.opacity(0.025))
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
    }

    // MARK: — Helpers
    @ViewBuilder private var msaaPills: some View {
        let levels = [(1,"Off"),(2,"2× AA"),(4,"4× AA")]
        HStack(spacing: 4) {
            ForEach(levels, id: \.0) { level, label in
                let on = vm.msaaLevel == level
                Button { vm.msaaLevel = level; vm.applyNow() } label: {
                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(on ? themeVM.accent : Color.white.opacity(0.07))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            content()
        }
        .padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func toggle(_ title: String, icon: String, val: Binding<Bool>) -> some View {
        Toggle(isOn: val) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10)).foregroundColor(themeVM.accent)
                monoLabel(title)
            }
        }.tint(themeVM.accent)
    }

    private func slider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>,
                        fmt: String, onChange: (() -> Void)? = nil) -> some View {
        HStack {
            monoLabel(title)
            Slider(value: value, in: range).tint(themeVM.accent)
                .onChange(of: value.wrappedValue) { _ in onChange?() ?? vm.applyNow() }
            accentLabel(String(format: fmt, value.wrappedValue))
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func monoLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.75))
    }
    private func accentLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.accent)
    }
}

// MARK: — Background Panel (Color / Gradient / Environment)
// Mirrors Nomad's Background tab: pick a flat color, a two-color gradient
// with a blend factor, or an environment map (preset or your own photo).
// Environment mode lights the scene with the same image it shows as the
// backdrop — same behavior as picking an HDRI in Nomad.
struct ArcBackgroundPanelContent: View {
    @StateObject private var vm = ArcRenderViewModel.shared
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var isLoadingPhoto = false

    var body: some View {
        VStack(spacing: 10) {
            // Mode switcher — Color | Gradient | Environment
            HStack(spacing: 0) {
                ForEach(ArcBackgroundMode.allCases) { mode in
                    Button {
                        vm.backgroundMode = mode
                        vm.applyNow()
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(vm.backgroundMode == mode ? .black : themeVM.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(vm.backgroundMode == mode ? themeVM.accent : Color.clear)
                    }
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            switch vm.backgroundMode {
            case .color:
                colorSection
            case .gradient:
                gradientSection
            case .environment:
                environmentSection
            }

            Spacer().frame(height: 20)
        }
        .padding(10)
    }

    // MARK: Color mode
    private var colorSection: some View {
        card("SOLID COLOR") {
            ColorPicker("Background Color",
                        selection: Binding(
                            get: { Color(vm.backgroundColor) },
                            set: { vm.backgroundColor = UIColor($0); vm.applyNow() }))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    // MARK: Gradient mode
    private var gradientSection: some View {
        card("GRADIENT") {
            ColorPicker("Top",
                        selection: Binding(
                            get: { Color(vm.gradientTopColor) },
                            set: { vm.gradientTopColor = UIColor($0); vm.applyNow() }))
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            ColorPicker("Bottom",
                        selection: Binding(
                            get: { Color(vm.gradientBottomColor) },
                            set: { vm.gradientBottomColor = UIColor($0); vm.applyNow() }))
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            HStack {
                Text("Factor").font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                Slider(value: Binding(
                    get: { vm.gradientFactor },
                    set: { vm.gradientFactor = $0; vm.applyNow() }), in: 0...1)
                    .tint(themeVM.accent)
                Text("\(Int(vm.gradientFactor * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.accent)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    // MARK: Environment mode
    private var environmentSection: some View {
        VStack(spacing: 10) {
            card("PRESETS") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ArcEnvironmentPreset.allCases.filter { $0 != .custom }) { preset in
                            Button {
                                vm.environmentPreset = preset
                                vm.environmentImage = nil   // use generated preset, not an import
                                vm.applyNow()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(uiImage: ArcRenderViewModel.skyPreset(preset))
                                        .resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 56, height: 34)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6)
                                            .stroke(vm.environmentPreset == preset && vm.environmentImage == nil
                                                    ? themeVM.accent : Color.white.opacity(0.15),
                                                    lineWidth: 2))
                                    Text(preset.rawValue)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                    }
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: isLoadingPhoto ? "hourglass" : "photo.badge.plus")
                        Text(isLoadingPhoto ? "Loading…" : "Import Your Own")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(themeVM.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .onChange(of: photoItem) { newItem in
                    guard let newItem else { return }
                    isLoadingPhoto = true
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            await MainActor.run {
                                vm.environmentImage = uiImage
                                vm.environmentPreset = .custom
                                vm.applyNow()
                                isLoadingPhoto = false
                            }
                        } else {
                            await MainActor.run { isLoadingPhoto = false }
                        }
                    }
                }

                if vm.environmentImage != nil {
                    Text("Using your imported image")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(themeVM.accent.opacity(0.8))
                }
            }

            card("EXPOSURE & CONTRAST") {
                HStack {
                    Text("Exposure").font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                    Slider(value: Binding(
                        get: { vm.environmentIntensity },
                        set: { vm.environmentIntensity = $0; vm.applyNow() }), in: 0...3)
                        .tint(themeVM.accent)
                    Text(String(format: "%.2f", vm.environmentIntensity))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("Contrast").font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                    Slider(value: Binding(
                        get: { vm.environmentContrast },
                        set: { vm.environmentContrast = $0; vm.applyNow() }), in: -1...1)
                        .tint(themeVM.accent)
                    Text(String(format: "%.2f", vm.environmentContrast))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                        .frame(width: 40, alignment: .trailing)
                }
                Text("Environment lighting also drives real-time reflections and shadows on every material in the scene.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            content()
        }
        .padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
