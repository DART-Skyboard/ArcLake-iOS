import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcFluidView — UI for the Arc Edge Fluid Dynamics engine.
// Activates from the Arc tab in the sidebar.
// References:
//   SebLague/Fluid-Sim (MIT): https://github.com/SebLague/Fluid-Sim
//   dartsolarpunk/Fluid-Sim:  https://github.com/dartsolarpunk/Fluid-Sim
//   Müller et al. SCA 2003:   https://matthias-research.github.io/pages/publications/sca03.pdf
//   SPH Tutorial:             https://sph-tutorial.physics-simulation.org/pdf/SPH_Tutorial.pdf
//   Radical Deepscale LEATR / Arc Edge framework
// ═══════════════════════════════════════════════════════════════════

struct ArcFluidView: View {
    @StateObject private var eng = ArcFluidEngine.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showMeshSelect = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                header
                if eng.isRunning {
                    measureHUD
                    scenePresetBar
                    simControls
                    meshZoneCard
                    stopButton
                } else {
                    startCard
                }
                creditsNote
                Spacer(minLength: 20)
            }.padding(10)
        }
        .background(Color(red:0.02,green:0.04,blue:0.09))
        .sheet(isPresented: $showMeshSelect) {
            ArcMeshSelectorView()
                .environmentObject(labVM)
                .environmentObject(themeVM)
        }
    }

    // MARK: — Header
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "water.waves").foregroundColor(themeVM.accent).font(.system(size:14))
            VStack(alignment: .leading, spacing: 1) {
                Text("ARC EDGE FLUID DYNAMICS")
                    .font(.custom("Orbitron-Bold", size: 10))
                    .foregroundColor(themeVM.accent).tracking(1.5)
                Text("SPH · Navier-Stokes · Reynolds · Arc Measure")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
        }
    }

    // MARK: — Live HUD
    private var measureHUD: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ARC EDGE MEASUREMENT").font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            HStack(spacing: 0) {
                hudStat("Particles", "\(eng.measure.particleCount)")
                hudStat("Re", String(format:"%.1e", eng.measure.reynoldsNum))
                hudStat("Regime", eng.measure.regime)
            }
            HStack(spacing: 0) {
                hudStat("ρ avg", String(format:"%.1f", eng.measure.avgDensity))
                hudStat("v avg", String(format:"%.2f", eng.measure.avgSpeed))
                hudStat("KE", String(format:"%.0f", eng.measure.totalKE))
            }
            if eng.inletZone != nil || eng.outletZone != nil {
                HStack(spacing: 0) {
                    if eng.inletZone != nil {
                        hudStat("Inlet pts", "\(Int(eng.measure.inletFlow))")
                    }
                    if eng.outletZone != nil {
                        hudStat("Outlet pts", "\(Int(eng.measure.outletFlow))")
                    }
                }
            }
        }
        .padding(10).background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10)
            .stroke(themeVM.accent.opacity(0.25), lineWidth: 0.8))
    }

    private func hudStat(_ label: String, _ val: String) -> some View {
        VStack(spacing: 1) {
            Text(val).font(.system(size:10,weight:.bold,design:.monospaced))
                .foregroundColor(themeVM.accent)
            Text(label).font(.system(size:7,design:.monospaced))
                .foregroundColor(.white.opacity(0.4))
        }.frame(maxWidth:.infinity)
    }

    // MARK: — Scene preset bar
    private var scenePresetBar: some View {
        VStack(alignment:.leading, spacing:6) {
            Text("SCENE PRESET").font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            ScrollView(.horizontal, showsIndicators:false) {
                HStack(spacing:4) {
                    ForEach(ArcFluidScene.allCases) { s in
                        Button { eng.setScene(s) } label: {
                            Text(s.rawValue.uppercased())
                                .font(.system(size:8,weight:.bold,design:.monospaced))
                                .foregroundColor(eng.scenePreset==s ? .black : .white.opacity(0.6))
                                .padding(.horizontal,9).padding(.vertical,5)
                                .background(eng.scenePreset==s ? themeVM.accent : Color.white.opacity(0.07))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:10))
    }

    // MARK: — Simulation controls
    private var simControls: some View {
        VStack(spacing:8) {
            Text("SIMULATION").font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2).frame(maxWidth:.infinity,alignment:.leading)
            // Fluid mode
            HStack(spacing:4) {
                ForEach(ArcFluidMode.allCases) { m in
                    Button { eng.mode = m } label: {
                        Text(m.rawValue)
                            .font(.system(size:8,weight:.bold,design:.monospaced))
                            .foregroundColor(eng.mode==m ? .black : .white.opacity(0.6))
                            .padding(.horizontal,8).padding(.vertical,5)
                            .background(eng.mode==m ? themeVM.accent : Color.white.opacity(0.07))
                            .clipShape(Capsule())
                    }
                }
            }
            sliderRow("Gravity ×", val: $eng.gravityScale, range: 0...4, fmt: "%.2f")
            sliderRow("Smoothing H", val: $eng.smoothingH, range: 10...80, fmt: "%.0f")
        }
        .padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:10))
    }

    // MARK: — Mesh zone selector
    private var meshZoneCard: some View {
        VStack(alignment:.leading, spacing:6) {
            HStack {
                Text("INLET / OUTLET ZONES").font(.system(size:8,weight:.bold,design:.monospaced))
                    .foregroundColor(.white.opacity(0.4)).tracking(2)
                Spacer()
                Button { showMeshSelect = true } label: {
                    Text("Select Mesh").font(.system(size:9,design:.monospaced))
                        .foregroundColor(themeVM.accent)
                        .padding(.horizontal,8).padding(.vertical,4)
                        .background(themeVM.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            if let iz = eng.inletZone {
                zoneRow("Inlet",  pos: iz, color: .green,  radius: $eng.inletRadius)
            } else {
                Text("No inlet set — tap Select Mesh")
                    .font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.3))
            }
            if let oz = eng.outletZone {
                zoneRow("Outlet", pos: oz, color: .orange, radius: $eng.outletRadius)
            } else {
                Text("No outlet set — tap Select Mesh")
                    .font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:10))
    }

    private func zoneRow(_ label: String, pos: SIMD3<Float>, color: Color, radius: Binding<Float>) -> some View {
        VStack(spacing:4) {
            HStack {
                Circle().fill(color).frame(width:6,height:6)
                Text(label).font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(String(format:"(%.0f, %.0f, %.0f)", pos.x, pos.y, pos.z))
                    .font(.system(size:8,design:.monospaced)).foregroundColor(.white.opacity(0.35))
            }
            HStack {
                Text("Radius").font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.5))
                Slider(value: radius, in: 5...100).tint(color)
                Text(String(format:"%.0f", radius.wrappedValue))
                    .font(.system(size:8,design:.monospaced)).foregroundColor(color)
                    .frame(width:28,alignment:.trailing)
            }
        }
    }

    // MARK: — Start card
    private var startCard: some View {
        VStack(spacing:12) {
            Text("FLUID TYPE").font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2).frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:4) {
                ForEach(ArcFluidMode.allCases) { m in
                    Button { eng.mode = m } label: {
                        VStack(spacing:3) {
                            Image(systemName: fluidIcon(m)).font(.system(size:14))
                            Text(m.rawValue).font(.system(size:8,design:.monospaced))
                        }
                        .foregroundColor(eng.mode==m ? .black : .white.opacity(0.6))
                        .frame(maxWidth:.infinity).padding(.vertical,8)
                        .background(eng.mode==m ? themeVM.accent : Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius:8))
                    }
                }
            }
            // Particle count
            HStack {
                Text("Particles").font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.7))
                Slider(value: Binding(
                    get: { Double(eng.particleCount) },
                    set: { eng.particleCount = Int($0) }
                ), in: 100...3000, step: 100).tint(themeVM.accent)
                Text("\(eng.particleCount)").font(.system(size:9,design:.monospaced))
                    .foregroundColor(themeVM.accent).frame(width:40,alignment:.trailing)
            }
            // Scene preset
            ScrollView(.horizontal, showsIndicators:false) {
                HStack(spacing:4) {
                    ForEach(ArcFluidScene.allCases) { s in
                        Button { eng.scenePreset = s } label: {
                            Text(s.rawValue)
                                .font(.system(size:8,weight:.bold,design:.monospaced))
                                .foregroundColor(eng.scenePreset==s ? .black : .white.opacity(0.6))
                                .padding(.horizontal,9).padding(.vertical,5)
                                .background(eng.scenePreset==s ? themeVM.accent : Color.white.opacity(0.07))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            // Launch button
            Button {
                let syms = labVM.currentElementSymbols()
                eng.start(in: labVM.scene, elementSymbols: syms)
                eng.setScene(eng.scenePreset)
            } label: {
                HStack(spacing:8) {
                    Image(systemName:"water.waves").font(.system(size:14))
                    Text("LAUNCH FLUID SIMULATION")
                        .font(.custom("Orbitron-Bold", size:11)).tracking(1)
                }
                .foregroundColor(.black)
                .frame(maxWidth:.infinity).padding(.vertical,14)
                .background(themeVM.accent)
                .clipShape(RoundedRectangle(cornerRadius:12))
            }
        }
        .padding(12).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:12))
    }

    private var stopButton: some View {
        Button { eng.stop() } label: {
            HStack(spacing:6) {
                Image(systemName:"stop.circle").font(.system(size:13))
                Text("Stop Simulation").font(.system(size:11,design:.monospaced))
            }
            .foregroundColor(.red.opacity(0.8))
            .frame(maxWidth:.infinity).padding(.vertical,10)
            .background(Color.red.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius:10))
        }
    }

    // MARK: — Credits
    private var creditsNote: some View {
        VStack(alignment:.leading, spacing:3) {
            Text("REFERENCES").font(.system(size:7,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.25)).tracking(2)
            Text("SPH: Müller et al. 2003 (SCA) · SebLague/Fluid-Sim (MIT)")
                .font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.2))
            Text("Kernels: dartsolarpunk/Fluid-Sim · LEATR Arc Edge framework")
                .font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.2))
            Text("Radical Deepscale LLC / DART Meadow — Arc Edge CFD v1.0")
                .font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.2))
        }
        .padding(.horizontal,4)
    }

    // MARK: Helpers
    private func sliderRow(_ label: String, val: Binding<Float>, range: ClosedRange<Float>, fmt: String) -> some View {
        HStack {
            Text(label).font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.7))
            Slider(value: val, in: range).tint(themeVM.accent)
            Text(String(format:fmt, val.wrappedValue))
                .font(.system(size:9,design:.monospaced)).foregroundColor(themeVM.accent)
                .frame(width:44,alignment:.trailing)
        }
    }

    private func fluidIcon(_ mode: ArcFluidMode) -> String {
        switch mode {
        case .liquid:   return "drop.fill"
        case .gas:      return "wind"
        case .viscous:  return "drop.degreesign"
        case .granular: return "circle.grid.3x3.fill"
        }
    }
}

// MARK: — ArcLabViewModel extension for element symbols
extension ArcLabViewModel {
    /// Collect element symbols from all atom groups in the current scene tab
    func currentElementSymbols() -> [String] {
        // selectedElements reflects the current tab's atoms (@Published public)
        if selectedElements.isEmpty { return ["O","H","H"] }
        return selectedElements.map { $0.elementSymbol }
    }
}
