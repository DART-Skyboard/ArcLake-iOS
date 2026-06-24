import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcFluidView — Arc Edge Fluid Dynamics UI
// Mesh-conformal SPH · Alloy material editor · Thermal colormap
// References: See ArcFluidEngine.swift header
// ═══════════════════════════════════════════════════════════════════

struct ArcFluidView: View {
    @StateObject private var eng = ArcFluidEngine.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var panelTab: FTab = .setup
    @State private var expandedComponent: UUID? = nil

    enum FTab: String, CaseIterable { case setup="Setup", materials="Materials", measure="Measure" }

    var body: some View {
        VStack(spacing:0) {
            header
            tabBar
            ScrollView(showsIndicators:false) {
                VStack(spacing:10) {
                    switch panelTab {
                    case .setup:    setupPanel
                    case .materials: materialsPanel
                    case .measure:  measurePanel
                    }
                    Spacer(minLength:20)
                }.padding(10)
            }
        }
        .background(Color(red:0.02,green:0.04,blue:0.09))
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing:8) {
            Image(systemName:"wind").foregroundColor(themeVM.accent).font(.system(size:13))
            VStack(alignment:.leading, spacing:1) {
                Text("ARC EDGE CFD")
                    .font(.system(size:10,weight:.bold,design:.monospaced))
                    .foregroundColor(themeVM.accent).tracking(2)
                Text("Mesh-conformal SPH · Alloy specs · Thermal colormap")
                    .font(.system(size:7,design:.monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            if eng.isRunning {
                HStack(spacing:4) {
                    Circle().fill(.green).frame(width:6,height:6)
                        .overlay(Circle().fill(.green).frame(width:10,height:10).opacity(0.3))
                    Text("RUNNING").font(.system(size:7,weight:.bold,design:.monospaced))
                        .foregroundColor(.green)
                }
            }
        }.padding(.horizontal,10).padding(.top,8)
    }

    private var tabBar: some View {
        HStack(spacing:0) {
            ForEach(FTab.allCases, id:\.self) { t in
                Button { panelTab = t } label: {
                    Text(t.rawValue)
                        .font(.system(size:9,weight:.bold,design:.monospaced))
                        .foregroundColor(panelTab==t ? .black : .white.opacity(0.5))
                        .frame(maxWidth:.infinity).padding(.vertical,7)
                        .background(panelTab==t ? themeVM.accent : Color.clear)
                }
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius:8))
        .padding(.horizontal,10).padding(.vertical,6)
    }

    // MARK: — SETUP TAB
    private var setupPanel: some View {
        VStack(spacing:10) {
            // Fluid type
            card("FLUID TYPE") {
                HStack(spacing:4) {
                    ForEach(ArcFluidMode.allCases) { m in
                        Button { eng.mode = m } label: {
                            VStack(spacing:3) {
                                Image(systemName:m.icon).font(.system(size:13))
                                Text(m.rawValue).font(.system(size:7,design:.monospaced))
                            }
                            .foregroundColor(eng.mode==m ? .black : .white.opacity(0.6))
                            .frame(maxWidth:.infinity).padding(.vertical,8)
                            .background(eng.mode==m ? themeVM.accent : Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius:8))
                        }
                    }
                }
            }

            // Scene preset
            card("SCENE PRESET") {
                ScrollView(.horizontal, showsIndicators:false) {
                    HStack(spacing:4) {
                        ForEach(ArcFluidScene.allCases) { s in
                            Button { eng.setScene(s) } label: {
                                Text(s.rawValue.uppercased())
                                    .font(.system(size:8,weight:.bold,design:.monospaced))
                                    .foregroundColor(eng.scenePreset==s ? .black : .white.opacity(0.6))
                                    .padding(.horizontal,10).padding(.vertical,5)
                                    .background(eng.scenePreset==s ? themeVM.accent : Color.white.opacity(0.07))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            // Simulation parameters
            card("PARAMETERS") {
                VStack(spacing:8) {
                    sldr("Particles", val: Binding(
                        get:{Double(eng.particleCount)},
                        set:{eng.particleCount=Int($0)}), lo:100, hi:2000, fmt:"%.0f")
                    sldrF("Gravity ×", val: $eng.gravityScale, lo:0, hi:4, fmt:"%.2f")
                    sldrF("Smoothing H", val: $eng.smoothingH, lo:8, hi:80, fmt:"%.0f")
                    // Sync env physics from labVM
                    HStack {
                        mono("Env Temp").frame(maxWidth:.infinity,alignment:.leading)
                        accent(String(format:"%.0f K", eng.envTempK))
                    }
                    HStack {
                        mono("Env Pressure").frame(maxWidth:.infinity,alignment:.leading)
                        accent(String(format:"%.1f psi", eng.envPressurePa/6894.76))
                    }
                }
            }

            // Start / Stop
            if eng.isRunning {
                VStack(spacing:6) {
                    Button { eng.stop() } label: {
                        HStack(spacing:6) {
                            Image(systemName:"stop.fill").font(.system(size:12))
                            Text("STOP CFD").font(.system(size:11,weight:.bold,design:.monospaced))
                        }
                        .foregroundColor(.red).frame(maxWidth:.infinity).padding(.vertical,12)
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius:10))
                    }
                    Text("Thermal colormap active on imported models")
                        .font(.system(size:8,design:.monospaced)).foregroundColor(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                }
            } else {
                Button {
                    let syms = labVM.selectedElements.isEmpty
                        ? ["O","H","H"]
                        : labVM.selectedElements.map{$0.elementSymbol}
                    let tempK = Float((labVM.physics.envData.temperature-32)*5/9+273.15)
                    let pressurePa = Float(labVM.physics.envData.pressure * 6894.76)
                    eng.start(in: labVM.scene, elementSymbols: syms,
                              envTempK: tempK, envPressurePa: pressurePa)
                } label: {
                    HStack(spacing:8) {
                        Image(systemName:"water.waves").font(.system(size:14))
                        Text("LAUNCH CFD SIMULATION")
                            .font(.system(size:11,weight:.bold,design:.monospaced)).tracking(1)
                    }
                    .foregroundColor(.black).frame(maxWidth:.infinity).padding(.vertical,14)
                    .background(themeVM.accent).clipShape(RoundedRectangle(cornerRadius:12))
                }
                Text("\(eng.particleCount) particles · \(eng.mode.rawValue) · mesh collision + thermal colormap")
                    .font(.system(size:8,design:.monospaced)).foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
            }

            // Credits
            credits
        }
    }

    // MARK: — MATERIALS TAB (per-component alloy editor)
    private var materialsPanel: some View {
        VStack(spacing:8) {
            HStack {
                mono("COMPONENT ALLOYS").tracking(2).frame(maxWidth:.infinity,alignment:.leading)
                Button {
                    ArcFluidEngine.shared.scanComponentSpecsPublic(labVM.scene)
                } label: {
                    Image(systemName:"arrow.clockwise").font(.system(size:12))
                        .foregroundColor(themeVM.accent)
                }
            }
            if eng.componentSpecs.isEmpty {
                VStack(spacing:8) {
                    Image(systemName:"cube.transparent").font(.system(size:24))
                        .foregroundColor(.white.opacity(0.2))
                    mono("Import a 3D model to specify component alloys")
                        .multilineTextAlignment(.center).foregroundColor(.white.opacity(0.3))
                }.frame(maxWidth:.infinity).padding(24)
            } else {
                ForEach($eng.componentSpecs) { $spec in
                    componentCard($spec)
                }
            }
            // Designation key
            HStack(spacing:12) {
                HStack(spacing:4) { Circle().fill(.green).frame(width:8,height:8); mono("Inlet") }
                HStack(spacing:4) { Circle().fill(.orange).frame(width:8,height:8); mono("Outlet") }
                HStack(spacing:4) { Circle().fill(.red.opacity(0.7)).frame(width:8,height:8); mono("Over limit") }
            }.padding(.top,4)
        }
    }

    @ViewBuilder
    private func componentCard(_ spec: Binding<ArcComponentSpec>) -> some View {
        let isOpen = expandedComponent == spec.wrappedValue.id
        let stress = spec.wrappedValue.stressLevel
        let stressColor: Color = stress > 0.85 ? .red : stress > 0.6 ? .orange : themeVM.accent

        VStack(alignment:.leading, spacing:0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration:0.15)) {
                    expandedComponent = isOpen ? nil : spec.wrappedValue.id
                }
            } label: {
                HStack(spacing:8) {
                    // Designation dots
                    if spec.wrappedValue.isInlet  { Circle().fill(.green).frame(width:6,height:6) }
                    if spec.wrappedValue.isOutlet { Circle().fill(.orange).frame(width:6,height:6) }
                    Text(spec.wrappedValue.displayName)
                        .font(.system(size:11,design:.monospaced)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
                    Spacer()
                    Text(spec.wrappedValue.alloy.name)
                        .font(.system(size:8,design:.monospaced)).foregroundColor(themeVM.accent.opacity(0.7))
                    if eng.isRunning {
                        Text(String(format:"%.0f K", spec.wrappedValue.currentTempK))
                            .font(.system(size:8,design:.monospaced)).foregroundColor(stressColor)
                    }
                    Image(systemName:isOpen ? "chevron.up":"chevron.down")
                        .font(.system(size:9)).foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal,12).padding(.vertical,9)
            }

            if isOpen {
                VStack(spacing:10) {
                    // Designation
                    HStack(spacing:12) {
                        Toggle(isOn: spec.isInlet)  { mono("Inlet") }.tint(.green)
                        Toggle(isOn: spec.isOutlet) { mono("Outlet") }.tint(.orange)
                    }
                    if spec.wrappedValue.isInlet {
                        sldrD("Flow m/s", val: spec.inletFlowRate, lo:0.1, hi:50, fmt:"%.1f")
                    }
                    Divider().background(Color.white.opacity(0.06))

                    // Alloy preset selector
                    VStack(alignment:.leading, spacing:4) {
                        mono("Alloy Preset")
                        ScrollView(.horizontal, showsIndicators:false) {
                            HStack(spacing:4) {
                                ForEach(ArcAlloySpec.presets) { preset in
                                    Button { spec.wrappedValue.alloy = preset } label: {
                                        Text(preset.name)
                                            .font(.system(size:7,weight:.bold,design:.monospaced))
                                            .foregroundColor(spec.wrappedValue.alloy.name==preset.name ? .black : .white.opacity(0.6))
                                            .padding(.horizontal,8).padding(.vertical,4)
                                            .background(spec.wrappedValue.alloy.name==preset.name ? themeVM.accent : Color.white.opacity(0.07))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    // Physical properties
                    VStack(spacing:6) {
                        propRow("Density",         val: spec.wrappedValue.alloy.densityKgM3,    unit:"kg/m³")
                        propRow("Thermal Cond.",   val: spec.wrappedValue.alloy.thermalConductivity, unit:"W/m·K")
                        propRow("Tensile Str.",    val: spec.wrappedValue.alloy.tensileStrengthMPa, unit:"MPa")
                        propRow("Max Temp",        val: spec.wrappedValue.alloy.maxTempK,       unit:"K")
                        propRow("Max Pressure",    val: spec.wrappedValue.alloy.maxPressureMPa, unit:"MPa")
                        propRow("Specific Heat",   val: spec.wrappedValue.alloy.specificHeat,   unit:"J/kg·K")
                    }

                    // Live CFD readout
                    if eng.isRunning {
                        Divider().background(Color.white.opacity(0.06))
                        VStack(spacing:4) {
                            liveRow("Current Temp",     val: spec.wrappedValue.currentTempK,         unit:"K",   warn: spec.wrappedValue.currentTempK > spec.wrappedValue.alloy.maxTempK*0.85)
                            liveRow("Current Pressure", val: spec.wrappedValue.currentPressureMPa,   unit:"MPa", warn: spec.wrappedValue.currentPressureMPa > spec.wrappedValue.alloy.maxPressureMPa*0.85)
                            // Stress bar
                            VStack(alignment:.leading, spacing:2) {
                                HStack {
                                    mono("Stress Level")
                                    Spacer()
                                    accent(String(format:"%.0f%%", spec.wrappedValue.stressLevel*100))
                                        .foregroundColor(stressColor)
                                }
                                GeometryReader { g in
                                    ZStack(alignment:.leading) {
                                        RoundedRectangle(cornerRadius:3).fill(Color.white.opacity(0.08)).frame(height:6)
                                        RoundedRectangle(cornerRadius:3).fill(stressColor)
                                            .frame(width:g.size.width*CGFloat(min(1,spec.wrappedValue.stressLevel)), height:6)
                                    }
                                }.frame(height:6)
                            }
                        }
                    }

                    // Custom overrides
                    sldrD("Density override", val: spec.alloy.densityKgM3, lo:500, hi:20000, fmt:"%.0f")
                }
                .padding(.horizontal,12).padding(.bottom,10)
                .background(Color.white.opacity(0.02))
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius:10))
    }

    // MARK: — MEASURE TAB
    private var measurePanel: some View {
        VStack(spacing:10) {
            card("ARC EDGE MEASUREMENT") {
                VStack(spacing:8) {
                    Grid(alignment:.leading, horizontalSpacing:12, verticalSpacing:6) {
                        measureRow("Particles",       "\(eng.measure.particleCount)")
                        measureRow("Avg Density",     String(format:"%.1f kg/m³", eng.measure.avgDensity))
                        measureRow("Avg Speed",       String(format:"%.2f m/s", eng.measure.avgSpeed))
                        measureRow("Avg Temperature", String(format:"%.1f K", eng.measure.avgTempK))
                        measureRow("Reynolds No.",    String(format:"%.2e", eng.measure.reynoldsNum))
                        measureRow("Flow Regime",     eng.measure.regime)
                        measureRow("Total KE",        String(format:"%.0f J", eng.measure.totalKE))
                        measureRow("Max Pressure",    String(format:"%.1f Pa", eng.measure.maxPressurePa))
                        measureRow("Inlet Count",     "\(Int(eng.measure.inletFlow))")
                        measureRow("Outlet Count",    "\(Int(eng.measure.outletFlow))")
                    }
                    // Regime visualization
                    let re = eng.measure.reynoldsNum
                    VStack(alignment:.leading, spacing:3) {
                        HStack {
                            mono("Regime Indicator")
                            Spacer()
                            accent(eng.measure.regime)
                        }
                        GeometryReader { g in
                            ZStack(alignment:.leading) {
                                RoundedRectangle(cornerRadius:3).fill(LinearGradient(
                                    colors:[.blue,.cyan,.green,.yellow,.orange,.red],
                                    startPoint:.leading, endPoint:.trailing)).frame(height:8)
                                let pos = min(1.0, re/6000)
                                Rectangle().fill(.white).frame(width:2, height:14)
                                    .offset(x: g.size.width*CGFloat(pos)-1, y:-3)
                            }
                        }.frame(height:8)
                        HStack { mono("0 (Laminar)"); Spacer(); mono("6000 (Turbulent)") }
                            .font(.system(size:6,design:.monospaced)).foregroundColor(.white.opacity(0.3))
                    }
                }
            }

            // Component stress overview
            if !eng.componentSpecs.isEmpty {
                card("COMPONENT HEALTH") {
                    VStack(spacing:6) {
                        ForEach(eng.componentSpecs) { spec in
                            HStack(spacing:6) {
                                let stress = spec.stressLevel
                                let color: Color = stress>0.85 ? .red : stress>0.6 ? .orange : .green
                                Circle().fill(color).frame(width:6,height:6)
                                Text(spec.displayName).font(.system(size:9,design:.monospaced))
                                    .foregroundColor(.white.opacity(0.7)).lineLimit(1)
                                Spacer()
                                Text(String(format:"%.0f K / %.2f MPa",
                                           spec.currentTempK, spec.currentPressureMPa))
                                    .font(.system(size:8,design:.monospaced)).foregroundColor(color)
                            }
                        }
                    }
                }
            }

            credits
        }
    }

    // MARK: — Credits
    private var credits: some View {
        VStack(alignment:.leading, spacing:2) {
            Text("PHYSICS REFERENCES").font(.system(size:7,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.2)).tracking(2)
            ForEach([
                "Müller et al. SCA 2003 — SPH kernels",
                "SebLague/Fluid-Sim (MIT) — step pipeline",
                "dartsolarpunk/fluid · dartsolarpunk/Fluid-Sim",
                "SPH Tutorial — physics-simulation.org",
                "Ihmsen et al. CGI 2012 — spray foam",
                "LEATR / Arc Edge framework — Radical Deepscale LLC"
            ], id:\.self) { ref in
                Text(ref).font(.system(size:6,design:.monospaced)).foregroundColor(.white.opacity(0.18))
            }
        }.padding(.horizontal,4)
    }

    // MARK: — Helpers
    private func card<C:View>(_ title:String, @ViewBuilder content:()->C) -> some View {
        VStack(alignment:.leading, spacing:8) {
            Text(title).font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            content()
        }.padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:12))
    }

    private func mono(_ s:String) -> some View {
        Text(s).font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.65))
    }
    private func accent(_ s:String) -> some View {
        Text(s).font(.system(size:9,design:.monospaced)).foregroundColor(themeVM.accent)
    }
    private func sldr(_ label:String, val:Binding<Double>, lo:Double, hi:Double, fmt:String) -> some View {
        HStack {
            mono(label)
            Slider(value:val, in:lo...hi).tint(themeVM.accent)
            accent(String(format:fmt,val.wrappedValue)).frame(width:44,alignment:.trailing)
        }
    }
    private func sldrF(_ label:String, val:Binding<Float>, lo:Float, hi:Float, fmt:String) -> some View {
        HStack {
            mono(label)
            Slider(value:val, in:lo...hi).tint(themeVM.accent)
            accent(String(format:fmt,val.wrappedValue)).frame(width:44,alignment:.trailing)
        }
    }
    private func sldrD(_ label:String, val:Binding<Double>, lo:Double, hi:Double, fmt:String) -> some View {
        HStack {
            mono(label)
            Slider(value:val, in:lo...hi).tint(themeVM.accent)
            accent(String(format:fmt,val.wrappedValue)).frame(width:44,alignment:.trailing)
        }
    }
    private func propRow(_ label:String, val:Double, unit:String) -> some View {
        HStack {
            mono(label).frame(maxWidth:.infinity,alignment:.leading)
            accent(String(format:"%.1f %@",val,unit))
        }
    }
    private func liveRow(_ label:String, val:Double, unit:String, warn:Bool) -> some View {
        HStack {
            mono(label).frame(maxWidth:.infinity,alignment:.leading)
            Text(String(format:"%.2f %@",val,unit))
                .font(.system(size:9,design:.monospaced)).foregroundColor(warn ? .red : themeVM.accent)
        }
    }
    private func measureRow(_ label:String, _ val:String) -> some View {
        GridRow {
            mono(label).frame(maxWidth:.infinity,alignment:.leading)
            accent(val)
        }
    }
}

// MARK: — Public accessor for scan
extension ArcFluidEngine {
    public func scanComponentSpecsPublic(_ scene: SCNScene) {
        scanComponentSpecs(scene)
    }
}
