import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcComponentConfigView — tap a 3D component → set its CFD properties
//
// Accessed by tapping any named mesh in the scene while CFD panel is open.
// Lets you specify: alloy, fluid/propellant, particle density, pressure,
// flow direction (entry/exit faces), and fill the cavity with particles.
//
// Propellant presets from common rocketry combinations.
// ═══════════════════════════════════════════════════════════════════

// MARK: — Propellant presets
public struct ArcPropellant: Identifiable {
    public let id: String
    public let name: String
    public let elements: [String]       // element symbols for SPH coloring
    public let densityKgM3: Double      // liquid density
    public let baseColor: (r:Float,g:Float,b:Float)
    public let description: String

    static let presets: [ArcPropellant] = [
        ArcPropellant(id:"lox", name:"LOX (Liquid O₂)",
            elements:["O","O"], densityKgM3:1141,
            baseColor:(1,0.15,0.05), description:"Liquid oxidizer — cryogenic"),
        ArcPropellant(id:"lh2", name:"LH₂ (Liquid H₂)",
            elements:["H","H"], densityKgM3:71,
            baseColor:(0.2,0.6,1.0), description:"Liquid fuel — cryogenic"),
        ArcPropellant(id:"kerosene", name:"RP-1 Kerosene",
            elements:["C","H","H","C"], densityKgM3:820,
            baseColor:(0.8,0.5,0.1), description:"Refined kerosene fuel"),
        ArcPropellant(id:"methane", name:"Methane (CH₄)",
            elements:["C","H","H","H","H"], densityKgM3:423,
            baseColor:(0.3,0.8,0.3), description:"Methalox fuel"),
        ArcPropellant(id:"n2o4", name:"N₂O₄ Oxidizer",
            elements:["N","O","O","N","O","O"], densityKgM3:1443,
            baseColor:(0.9,0.3,0.1), description:"Nitrogen tetroxide oxidizer"),
        ArcPropellant(id:"udmh", name:"UDMH Fuel",
            elements:["N","C","H"], densityKgM3:791,
            baseColor:(0.4,0.2,0.8), description:"Unsymmetrical dimethylhydrazine"),
        ArcPropellant(id:"h2o2", name:"H₂O₂ Peroxide",
            elements:["H","O","O","H"], densityKgM3:1450,
            baseColor:(0.9,0.9,1.0), description:"Hydrogen peroxide oxidizer"),
        ArcPropellant(id:"al2o3", name:"Al₂O₃ (Solid ox.)",
            elements:["Al","O","Al","O","O"], densityKgM3:3970,
            baseColor:(0.95,0.9,0.85), description:"Aluminum oxide solid oxidizer"),
        ArcPropellant(id:"custom", name:"Custom Molecule",
            elements:[], densityKgM3:800,
            baseColor:(0.6,0.9,0.6), description:"From Molecule Canvas"),
    ]
}

// MARK: — Component config sheet
struct ArcComponentConfigView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @StateObject private var eng = ArcFluidEngine.shared
    @Environment(\.dismiss) private var dismiss

    let nodeName: String

    @State private var specIdx: Int = 0     // index into componentSpecs
    @State private var selectedPropellant: ArcPropellant? = nil
    @State private var particleDensityUnit: DensityUnit = .perCubicCm
    @State private var particleDensity: Double = 30     // particles per unit
    @State private var fillFraction: Double = 1.0       // 0-1 how full to fill
    @State private var flowDir: FlowDir = .auto
    @State private var filling = false

    enum DensityUnit: String, CaseIterable, Identifiable {
        case perCubicCm = "/cm³", perCubicM = "/m³"
        public var id: String { rawValue }
    }
    enum FlowDir: String, CaseIterable, Identifiable {
        case auto = "Auto", topIn = "Top→Down", bottomIn = "Bottom→Up", custom = "Custom"
        public var id: String { rawValue }
    }

    private var displayName: String {
        var d = nodeName
        for p in ["glb_import_","imported_"] where nodeName.hasPrefix(p) {
            d = String(nodeName.dropFirst(p.count)); break
        }
        return d
    }

    private var spec: ArcComponentSpec? { eng.componentSpecs.first(where:{$0.nodeName==nodeName}) }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    componentHeader
                    propellantSection
                    densitySection
                    flowSection
                    alloySection
                    fillButton
                    if spec?.isCombustionChamber == true { combustionNote }
                    Spacer(minLength: 20)
                }
                .padding(12)
            }
            .background(Color(red:0.02,green:0.04,blue:0.09))
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Pre-select existing propellant if set
            if let s = spec, let ft = s.fluidType {
                selectedPropellant = ft == .fuel
                    ? ArcPropellant.presets.first(where:{$0.id=="kerosene"})
                    : ArcPropellant.presets.first(where:{$0.id=="lox"})
            }
        }
    }

    // MARK: — Header with role badge
    private var componentHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = spec {
                HStack(spacing: 8) {
                    Image(systemName: componentIcon(s)).font(.system(size: 22))
                        .foregroundColor(componentColor(s))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text(roleName(s))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(componentColor(s))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(s.alloy.name)
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.accent)
                        Text("\(s.particleCapacity) max particles")
                            .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        Text(String(format: "%.2f m³", s.volumeM3))
                            .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(12)
                .background(componentColor(s).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: — Propellant selection
    private var propellantSection: some View {
        card("PROPELLANT / FLUID") {
            VStack(spacing: 8) {
                // Presets grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                    ForEach(ArcPropellant.presets) { prop in
                        Button {
                            selectedPropellant = prop
                            applyPropellant(prop)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(red:Double(prop.baseColor.r),
                                               green:Double(prop.baseColor.g),
                                               blue:Double(prop.baseColor.b)))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(prop.name)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(selectedPropellant?.id == prop.id ? .black : .white.opacity(0.8))
                                        .lineLimit(1)
                                    Text(String(format:"%.0f kg/m³", prop.densityKgM3))
                                        .font(.system(size: 7, design: .monospaced))
                                        .foregroundColor(selectedPropellant?.id == prop.id ? .black.opacity(0.7) : .white.opacity(0.35))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(selectedPropellant?.id == prop.id ? themeVM.accent : Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                // Custom molecule from canvas
                if selectedPropellant?.id == "custom" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MOLECULE CANVAS ELEMENTS")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35)).tracking(2)
                        if labVM.selectedElements.isEmpty {
                            Text("Add elements in the Atoms tab first")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(labVM.selectedElements, id: \.id) { el in
                                        Text(el.elementSymbol)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 7).padding(.vertical, 4)
                                            .background(themeVM.accent).clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(8).background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: — Particle density
    private var densitySection: some View {
        card("PARTICLE DENSITY") {
            VStack(spacing: 8) {
                // Unit selector
                HStack(spacing: 4) {
                    ForEach(DensityUnit.allCases) { u in
                        Button { particleDensityUnit = u } label: {
                            Text(u.rawValue)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(particleDensityUnit == u ? .black : .white.opacity(0.5))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(particleDensityUnit == u ? themeVM.accent : Color.white.opacity(0.07))
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                HStack {
                    Text("Density").font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    let range: ClosedRange<Double> = particleDensityUnit == .perCubicCm ? 1...200 : 1...50000
                    Slider(value: $particleDensity, in: range).tint(themeVM.accent)
                    Text(String(format: "%.0f%@", particleDensity, particleDensityUnit.rawValue))
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.accent)
                        .frame(width: 60, alignment: .trailing)
                }
                // Fill fraction
                HStack {
                    Text("Fill Level").font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    Slider(value: $fillFraction, in: 0.01...1.0).tint(themeVM.accent)
                    Text(String(format: "%.0f%%", fillFraction * 100))
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.accent)
                        .frame(width: 36, alignment: .trailing)
                }
                // Computed particle count
                // Volume in scene units³ (1 scene unit ≈ 1 m for GLB models)
                let vol = spec?.volumeSceneUnits ?? 1.0
                // Max useful particle count: 50/unit³ at scene scale → hundreds per tank
                let density = particleDensityUnit == .perCubicCm
                    ? particleDensity * 0.000001  // /cm³ → /scene-unit³ (1m³)
                    : particleDensity * 0.000001  // /m³  → /scene-unit³
                let totalParticles = min(2000, max(5, Int(vol * density * fillFraction)))
                HStack {
                    Text("Computed particles").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text("\(totalParticles.formatted()) particles")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(themeVM.accent)
                }
                Text(String(format: "Volume: %.3f scene units³", vol))
                    .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.3))
            }
        }
    }

    // MARK: — Flow direction
    private var flowSection: some View {
        card("FLOW DIRECTION") {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(FlowDir.allCases) { dir in
                        Button { flowDir = dir; applyFlowDir(dir) } label: {
                            Text(dir.rawValue)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(flowDir == dir ? .black : .white.opacity(0.5))
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(flowDir == dir ? themeVM.accent : Color.white.opacity(0.07))
                                .clipShape(Capsule())
                        }
                    }
                }
                // Pressure slider
                if let s = spec {
                    HStack {
                        Text("Operating Pressure").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                        Slider(value: Binding(
                            get: { s.pressurePsi },
                            set: { v in updateSpec { $0.pressurePsi = v } }
                        ), in: 0...1000).tint(.orange)
                        Text(String(format: "%.0f psi", s.pressurePsi))
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(.orange)
                            .frame(width: 52, alignment: .trailing)
                    }
                    // Auto-detected flow info
                    if flowDir == .auto, let role = ArcCombustionFlow.componentRoles[displayName] {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").font(.system(size: 9)).foregroundColor(themeVM.accent)
                            Text(autoFlowDescription(role))
                                .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
        }
    }

    // MARK: — Alloy
    private var alloySection: some View {
        card("ALLOY") {
            VStack(spacing: 6) {
                if let s = spec {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(ArcAlloySpec.presets) { preset in
                                Button { updateSpec { $0.alloy = preset } } label: {
                                    Text(preset.name)
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(s.alloy.name==preset.name ? .black : .white.opacity(0.6))
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(s.alloy.name==preset.name ? themeVM.accent : Color.white.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                        GridRow {
                            mono("Density").frame(maxWidth:.infinity,alignment:.leading)
                            accent("\(Int(s.alloy.densityKgM3)) kg/m³")
                        }
                        GridRow {
                            mono("Thermal Cond.").frame(maxWidth:.infinity,alignment:.leading)
                            accent(String(format:"%.1f W/m·K",s.alloy.thermalConductivity))
                        }
                        GridRow {
                            mono("Max Temp").frame(maxWidth:.infinity,alignment:.leading)
                            accent("\(Int(s.alloy.maxTempK)) K")
                        }
                        GridRow {
                            mono("Max Pressure").frame(maxWidth:.infinity,alignment:.leading)
                            accent("\(Int(s.alloy.maxPressureMPa)) MPa")
                        }
                    }
                }
            }
        }
    }

    // MARK: — Fill button
    private var fillButton: some View {
        VStack(spacing: 8) {
            Button {
                fillCavity()
            } label: {
                HStack(spacing: 8) {
                    if filling {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "drop.fill").font(.system(size: 14))
                    }
                    Text(filling ? "FILLING..." : "FILL CAVITY")
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1)
                }
                .foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(selectedPropellant != nil ? themeVM.accent : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selectedPropellant == nil || filling)

            if let prop = selectedPropellant, let s = spec {
                let vol = s.volumeM3
                let volCm3 = vol * 1_000_000
                let density = particleDensityUnit == .perCubicCm ? particleDensity : particleDensity / 1_000_000
                let n = Int(volCm3 * density * fillFraction)
                Text("Will spawn \(n.formatted()) \(prop.name) particles inside \(displayName)")
                    .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var combustionNote: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundColor(.orange)
                Text("COMBUSTION CHAMBER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.orange)
            }
            Text("Fuel + Oxidizer particles that meet here will react — temperature spikes, particles shift to orange-white, exhaust exits downward. Ensure both Fuel and Oxidizer tanks are filled before starting simulation.")
                .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(10).background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: — Fill cavity action
    private func fillCavity() {
        guard let prop = selectedPropellant, let s = spec else { return }
        filling = true
        let scene = labVM.scene
        let vol = s.volumeM3
        let volCm3 = vol * 1_000_000
        let density = particleDensityUnit == .perCubicCm ? particleDensity : particleDensity / 1_000_000
        let count = max(5, min(3000, Int(volCm3 * density * fillFraction)))

        // Get element symbols — either from preset or molecule canvas
        let syms: [String]
        if prop.id == "custom" {
            syms = labVM.selectedElements.isEmpty ? ["H","H","O"] : labVM.selectedElements.map{$0.elementSymbol}
        } else {
            syms = prop.elements
        }

        // Set molecule symbols on engine for reaction
        if s.fluidType == .fuel || prop.id.contains("h2") || prop.id == "kerosene" || prop.id == "methane" || prop.id == "udmh" {
            ArcFluidEngine.shared.currentFuelSymbols = syms
        } else {
            ArcFluidEngine.shared.currentOxidizerSymbols = syms
        }

        // Spawn particles inside this component's bounding box
        Task(priority: .userInitiated) {
            await MainActor.run {
                ArcFluidEngine.shared.fillComponentCavity(
                    spec: s,
                    count: count,
                    propellant: prop,
                    scene: scene,
                    gravityScale: Float(labVM.physics.activeTab.gravity / 9.8),
                    envTempK: Float(labVM.physics.activeTab.ambientTempK))
                // Update fill level
                if let idx = ArcFluidEngine.shared.componentSpecs.firstIndex(where:{$0.nodeName==nodeName}) {
                    ArcFluidEngine.shared.componentSpecs[idx].fillLevel = fillFraction
                }
            }
            await MainActor.run { filling = false }
        }
    }

    private func applyPropellant(_ prop: ArcPropellant) {
        if prop.id == "lox" || prop.id == "n2o4" || prop.id == "h2o2" || prop.id == "al2o3" {
            updateSpec { $0.fluidType = .oxidizer }
        } else if prop.id != "custom" {
            updateSpec { $0.fluidType = .fuel }
        }
    }

    private func applyFlowDir(_ dir: FlowDir) {
        switch dir {
        case .topIn:   updateSpec { $0.isInlet = true;  $0.isOutlet = false }
        case .bottomIn: updateSpec { $0.isInlet = false; $0.isOutlet = true }
        case .auto: break
        case .custom: break
        }
    }

    private func updateSpec(_ mutate: (inout ArcComponentSpec)->Void) {
        guard let idx = ArcFluidEngine.shared.componentSpecs.firstIndex(where:{$0.nodeName==nodeName})
        else { return }
        mutate(&ArcFluidEngine.shared.componentSpecs[idx])
    }

    private func componentIcon(_ s: ArcComponentSpec) -> String {
        if s.isCombustionChamber { return "flame.fill" }
        if s.fluidType == .fuel  { return "drop.fill" }
        if s.fluidType == .oxidizer { return "bolt.fill" }
        if s.isInlet  { return "arrow.down.circle.fill" }
        return "cube.fill"
    }

    private func componentColor(_ s: ArcComponentSpec) -> Color {
        if s.isCombustionChamber { return .orange }
        if s.fluidType == .fuel  { return .blue }
        if s.fluidType == .oxidizer { return .red }
        if s.isInlet  { return .green }
        return themeVM.accent
    }

    private func roleName(_ s: ArcComponentSpec) -> String {
        if s.isCombustionChamber { return "COMBUSTION CHAMBER" }
        if let ft = s.fluidType { return "\(ft.rawValue.uppercased()) TANK" }
        if s.isInlet  { return "PRESSURE INLET" }
        if s.isOutlet { return "EXHAUST OUTLET" }
        return "COMPONENT"
    }

    private func autoFlowDescription(_ role: ArcCombustionFlow.ComponentRole) -> String {
        switch role {
        case .pressureChamber(let tank): return "Inlet pressure feeds \(tank) tank from top"
        case .tank: return "Gravity-assisted downward flow via channel"
        case .channel(let from, let to): return "\(from) → \(to) (gravity-fed)"
        case .combustionChamber: return "Receives fuel + oxidizer, exhaust exits bottom"
        }
    }

    private func card<C:View>(_ title: String, @ViewBuilder content:()->C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            content()
        }.padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func mono(_ s: String) -> some View {
        Text(s).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.55))
    }
    private func accent(_ s: String) -> some View {
        Text(s).font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.accent)
    }
}
