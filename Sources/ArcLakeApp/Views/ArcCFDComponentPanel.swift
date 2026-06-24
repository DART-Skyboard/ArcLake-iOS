import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// ArcCFDComponentPanel — embedded in the Arc tab sidebar.
// Exposes: fluid type, component alloy specs, inlet/outlet
// designation, volumetric capacity, flow direction, and live
// Arc Edge fluid measurement — all accessible from the Arc tab.
// ═══════════════════════════════════════════════════════════════════

struct ArcCFDComponentPanel: View {
    @StateObject private var eng = ArcFluidEngine.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var expanded: UUID? = nil
    @State private var showMeshSelector = false

    var body: some View {
        VStack(spacing: 0) {
            // Header — always visible
            header

            // CFD launch / status strip
            cfdStrip

            // Component specs (when models are loaded)
            if !eng.componentSpecs.isEmpty {
                componentList
            }

            // Live Arc Edge measurement (when CFD running)
            if eng.isRunning {
                arcMeasurement
            }
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showMeshSelector) {
            ArcMeshSelectorView()
                .environmentObject(labVM)
                .environmentObject(themeVM)
        }
    }

    // MARK: — Header
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wind").foregroundColor(themeVM.accent).font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("ARC EDGE CFD")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.accent).tracking(2)
                Text("Mesh-conformal SPH · Alloy specs · Thermal colormap")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            if eng.isRunning {
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("LIVE").font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
    }

    // MARK: — CFD strip
    private var cfdStrip: some View {
        VStack(spacing: 6) {
            // Fluid mode selector
            HStack(spacing: 3) {
                ForEach(ArcFluidMode.allCases) { m in
                    Button { eng.mode = m } label: {
                        Text(m.rawValue)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(eng.mode == m ? .black : .white.opacity(0.5))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(eng.mode == m ? themeVM.accent : Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
            }

            // Scene preset
            HStack(spacing: 3) {
                ForEach(ArcFluidScene.allCases) { s in
                    Button { eng.setScene(s) } label: {
                        Text(s.rawValue)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(eng.scenePreset == s ? .black : .white.opacity(0.5))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(eng.scenePreset == s ? themeVM.accent.opacity(0.85) : Color.white.opacity(0.05))
                            .clipShape(Capsule())
                    }
                }
            }

            HStack(spacing: 8) {
                // Particle count compact
                Text("\(eng.particleCount) pts")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Slider(value: Binding(
                    get: { Double(eng.particleCount) },
                    set: { eng.particleCount = Int($0) }
                ), in: 100...2000, step: 100).tint(themeVM.accent)

                // Mesh zone selector
                Button { showMeshSelector = true } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 11)).foregroundColor(themeVM.accent)
                }
            }

            // Start / Stop
            if eng.isRunning {
                Button { eng.stop() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                        Text("STOP CFD").font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.red).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.red.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Button { launchCFD() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "water.waves").font(.system(size: 11))
                        Text("LAUNCH ARC EDGE CFD")
                            .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.8)
                    }
                    .foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(themeVM.accent).clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func launchCFD() {
        let syms: [String] = labVM.selectedElements.isEmpty
            ? ["O","H","H"]
            : labVM.selectedElements.map { $0.elementSymbol }
        let tempK = Float((labVM.physics.temperature - 32.0) * 5.0/9.0 + 273.15)
        let pressurePa = Float(labVM.physics.pressure * 6894.76)
        eng.start(in: labVM.scene, elementSymbols: syms,
                  envTempK: tempK, envPressurePa: pressurePa)
    }

    // MARK: — Component list
    private var componentList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COMPONENT ALLOYS")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35)).tracking(2)
                Spacer()
                Button {
                    eng.scanComponentSpecsPublic(labVM.scene)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10)).foregroundColor(themeVM.accent)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)

            ForEach($eng.componentSpecs) { $spec in
                componentRow($spec)
            }
        }
    }

    @ViewBuilder
    private func componentRow(_ spec: Binding<ArcComponentSpec>) -> some View {
        let isOpen = expanded == spec.wrappedValue.id
        let stress = spec.wrappedValue.stressLevel
        let stressColor: Color = stress > 0.85 ? .red : stress > 0.6 ? .orange : themeVM.accent

        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    expanded = isOpen ? nil : spec.wrappedValue.id
                }
            } label: {
                HStack(spacing: 6) {
                    if spec.wrappedValue.isInlet  { Circle().fill(.green).frame(width: 5, height: 5) }
                    if spec.wrappedValue.isOutlet { Circle().fill(.orange).frame(width: 5, height: 5) }
                    Text(spec.wrappedValue.displayName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8)).lineLimit(1)
                    Spacer()
                    Text(spec.wrappedValue.alloy.name)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(themeVM.accent.opacity(0.7))
                    if eng.isRunning {
                        Text(String(format: "%.0f K", spec.wrappedValue.currentTempK))
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(stressColor)
                    }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8)).foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            if isOpen {
                VStack(spacing: 8) {
                    // Inlet / Outlet designation + flow rate
                    HStack(spacing: 12) {
                        Toggle(isOn: spec.isInlet)  { label("Inlet") }.tint(.green).labelsHidden()
                        Text("Inlet").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                        Toggle(isOn: spec.isOutlet) { label("Outlet") }.tint(.orange).labelsHidden()
                        Text("Outlet").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    }
                    if spec.wrappedValue.isInlet {
                        HStack {
                            Text("Flow m/s").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                            Slider(value: spec.inletFlowRate, in: 0.1...50).tint(.green)
                            Text(String(format: "%.1f", spec.wrappedValue.inletFlowRate))
                                .font(.system(size: 8, design: .monospaced)).foregroundColor(.green)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }

                            // Cavity fill level + pressure
                    VStack(spacing: 4) {
                        HStack {
                            Text("Fill Level").font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius:2).fill(Color.white.opacity(0.07)).frame(height:6)
                                    let fillColor: Color = spec.wrappedValue.isCombustionChamber ? .orange :
                                        spec.wrappedValue.fluidType == .some(.fuel) ? .blue : .red
                                    RoundedRectangle(cornerRadius:2).fill(fillColor)
                                        .frame(width:g.size.width*CGFloat(min(1,spec.wrappedValue.fillLevel)), height:6)
                                }
                            }.frame(height:6)
                            Text(String(format:"%.0f%%", spec.wrappedValue.fillLevel*100))
                                .font(.system(size:8,design:.monospaced)).foregroundColor(themeVM.accent)
                                .frame(width:32,alignment:.trailing)
                        }
                        HStack {
                            Text("Pressure").font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                            Slider(value: spec.pressurePsi, in: 0...500).tint(.orange)
                            Text(String(format:"%.0f psi", spec.wrappedValue.pressurePsi))
                                .font(.system(size:8,design:.monospaced)).foregroundColor(.orange)
                                .frame(width:52,alignment:.trailing)
                        }
                        HStack {
                            Text("Capacity").font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text("\(spec.wrappedValue.particleCapacity) particles · \(String(format:"%.3f m³", spec.wrappedValue.volumeM3))")
                                .font(.system(size:8,design:.monospaced)).foregroundColor(themeVM.accent)
                        }
                        if spec.wrappedValue.isCombustionChamber {
                            HStack(spacing:4) {
                                Image(systemName:"flame.fill").font(.system(size:9)).foregroundColor(.orange)
                                Text("COMBUSTION CHAMBER").font(.system(size:8,weight:.bold,design:.monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                        if let ft = spec.wrappedValue.fluidType {
                            HStack(spacing:4) {
                                Circle().fill(ft == .fuel ? Color.blue : Color.red).frame(width:6,height:6)
                                Text("\(ft.rawValue.uppercased()) TANK").font(.system(size:8,weight:.bold,design:.monospaced))
                                    .foregroundColor(ft == .fuel ? .blue : .red)
                            }
                        }
                    }

                    // Alloy preset pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(ArcAlloySpec.presets) { preset in
                                Button { spec.wrappedValue.alloy = preset } label: {
                                    Text(preset.name)
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(spec.wrappedValue.alloy.name == preset.name ? .black : .white.opacity(0.55))
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(spec.wrappedValue.alloy.name == preset.name
                                                    ? themeVM.accent : Color.white.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Key physical properties
                    VStack(spacing: 3) {
                        propRow("Density",       "\(Int(spec.wrappedValue.alloy.densityKgM3)) kg/m³")
                        propRow("Thermal Cond.", String(format: "%.1f W/m·K", spec.wrappedValue.alloy.thermalConductivity))
                        propRow("Tensile Str.",  "\(Int(spec.wrappedValue.alloy.tensileStrengthMPa)) MPa")
                        propRow("Max Temp",      "\(Int(spec.wrappedValue.alloy.maxTempK)) K")
                        propRow("Max Pressure",  "\(Int(spec.wrappedValue.alloy.maxPressureMPa)) MPa")
                        if eng.isRunning {
                            Divider().background(Color.white.opacity(0.08))
                            propRowHighlight("Current T", String(format: "%.1f K", spec.wrappedValue.currentTempK),
                                            warn: spec.wrappedValue.currentTempK > spec.wrappedValue.alloy.maxTempK * 0.85)
                            propRowHighlight("Current P", String(format: "%.3f MPa", spec.wrappedValue.currentPressureMPa),
                                            warn: spec.wrappedValue.currentPressureMPa > spec.wrappedValue.alloy.maxPressureMPa * 0.85)
                            // Stress bar
                            HStack {
                                Text("Stress").font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.07)).frame(height: 5)
                                        RoundedRectangle(cornerRadius: 2).fill(stressColor)
                                            .frame(width: g.size.width * CGFloat(min(1, spec.wrappedValue.stressLevel)), height: 5)
                                    }
                                }.frame(height: 5)
                                Text(String(format: "%.0f%%", spec.wrappedValue.stressLevel * 100))
                                    .font(.system(size: 7, design: .monospaced)).foregroundColor(stressColor)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
                .background(Color.white.opacity(0.025))
            }
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8).padding(.vertical, 2)
    }

    // MARK: — Live Arc Edge measurement
    private var arcMeasurement: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ARC EDGE FLUID MEASUREMENT")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35)).tracking(2)
                .padding(.horizontal, 12).padding(.top, 8)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                mRow("Particles",  "\(eng.measure.particleCount)")
                mRow("Avg Temp",   String(format: "%.1f K", eng.measure.avgTempK))
                mRow("Avg Speed",  String(format: "%.2f m/s", eng.measure.avgSpeed))
                mRow("Reynolds",   String(format: "%.2e", eng.measure.reynoldsNum))
                mRow("Regime",     eng.measure.regime)
                mRow("Max Press.", String(format: "%.0f Pa", eng.measure.maxPressurePa))
                mRow("KE Total",   String(format: "%.0f J", eng.measure.totalKE))
                if eng.measure.inletFlow > 0 || eng.measure.outletFlow > 0 {
                    mRow("Inlet pts",  "\(Int(eng.measure.inletFlow))")
                    mRow("Outlet pts", "\(Int(eng.measure.outletFlow))")
                }
            }
            .padding(.horizontal, 12)

            // Regime bar
            VStack(spacing: 2) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(LinearGradient(
                            colors: [.blue,.cyan,.green,.yellow,.orange,.red],
                            startPoint: .leading, endPoint: .trailing)).frame(height: 6)
                        let pos = min(1.0, eng.measure.reynoldsNum / 6000)
                        Rectangle().fill(.white).frame(width: 2, height: 12)
                            .offset(x: g.size.width * CGFloat(pos) - 1, y: -3)
                    }
                }.frame(height: 6)
                HStack {
                    Text("0 Laminar").font(.system(size: 6, design: .monospaced)).foregroundColor(.white.opacity(0.25))
                    Spacer()
                    Text("Turbulent 6000+").font(.system(size: 6, design: .monospaced)).foregroundColor(.white.opacity(0.25))
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(themeVM.accent.opacity(0.2), lineWidth: 0.8))
        .padding(.horizontal, 8).padding(.bottom, 8)
    }

    // MARK: — Helpers
    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 9, design: .monospaced))
    }
    private func propRow(_ label: String, _ val: String) -> some View {
        HStack {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            Spacer()
            Text(val).font(.system(size: 8, design: .monospaced)).foregroundColor(themeVM.accent)
        }
    }
    private func propRowHighlight(_ label: String, _ val: String, warn: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            Spacer()
            Text(val).font(.system(size: 8, design: .monospaced)).foregroundColor(warn ? .red : themeVM.accent)
        }
    }
    private func mRow(_ label: String, _ val: String) -> some View {
        GridRow {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            Text(val).font(.system(size: 8, design: .monospaced)).foregroundColor(themeVM.accent)
        }
    }
}
