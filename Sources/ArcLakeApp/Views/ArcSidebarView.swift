import SwiftUI

// MARK: — Molecule Panel
struct DARTMoleculePanel: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {

                // Active elements
                DARTPanelCard(title: "Active Elements", icon: "atom") {
                    if labVM.selectedElements.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "atom")
                                .font(.system(size: 24))
                                .foregroundColor(themeVM.accent.opacity(0.25))
                            Text("Open the Periodic Table to add elements")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                    } else {
                        ForEach(labVM.selectedElements) { el in
                            DARTElementRow(element: el)
                        }
                    }
                }

                // Quick actions grid
                DARTPanelCard(title: "Actions", icon: "sparkles") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 8) {
                        DARTActionTile(label: "Periodic\nTable", icon: "tablecells",
                                       color: themeVM.accent) {
                            withAnimation(.spring()) { labVM.isPeriodicTableVisible.toggle() }
                        }
                        DARTActionTile(label: "Mol\nCanvas", icon: "scribble",
                                       color: .purple) {
                            withAnimation(.spring()) { labVM.isMolCanvasVisible.toggle() }
                        }
                        DARTActionTile(label: "Export\nGLB", icon: "square.and.arrow.up",
                                       color: .green) {
                            if let url = labVM.exportGLB() {
                                let av = UIActivityViewController(
                                    activityItems: [url], applicationActivities: nil)
                                UIApplication.shared.connectedScenes
                                    .compactMap { $0 as? UIWindowScene }
                                    .first?.windows.first?
                                    .rootViewController?.present(av, animated: true)
                            }
                        }
                        DARTActionTile(label: "Clear\nAll", icon: "trash",
                                       color: .red.opacity(0.8)) {
                            labVM.clearElements()
                        }
                    }
                }
            }
            .padding(10)
        }
    }
}

struct DARTElementRow: View {
    let element: ArcElement
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        HStack(spacing: 10) {
            // Element chip
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(element.category.color).opacity(0.15))
                    .frame(width: 36, height: 36)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(element.category.color).opacity(0.4), lineWidth: 0.7)
                    .frame(width: 36, height: 36)
                Text(element.elementSymbol)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(element.category.color))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(element.elementName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Text("Z=\(element.protons)  n=\(element.neutrons)  e=\(element.electrons)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()

            // Probe button
            Button {
                labVM.openProbe(for: element)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(themeVM.accent.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(themeVM.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Button {
                labVM.removeElement(element)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 4)
    }
}

struct DARTActionTile: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 0.7))
        }
    }
}

// MARK: — Physics Panel
struct DARTPhysicsPanel: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {

                DARTPanelCard(title: "Particle Resolution", icon: "circle.grid.3x3") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("pts / component")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                            Spacer()
                            Text("\(labVM.ptsPerComponent)")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(themeVM.accent)
                        }
                        Slider(value: Binding(
                            get: { Double(labVM.ptsPerComponent) },
                            set: { labVM.ptsPerComponent = max(1, Int($0)) }),
                               in: 1...500, step: 1)
                        .tint(themeVM.accent)

                        // Presets
                        HStack(spacing: 6) {
                            ForEach([("Low",10),("Def",30),("Med",300),("Hi",1000),("Max",3000)], id: \.0) { lbl, val in
                                Button {
                                    labVM.ptsPerComponent = val
                                    labVM.rebuildAllAtoms()
                                } label: {
                                    Text(lbl)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(labVM.ptsPerComponent == val ? .black : .white.opacity(0.5))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(labVM.ptsPerComponent == val ? themeVM.accent : Color.white.opacity(0.07))
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        Button { labVM.rebuildAllAtoms() } label: {
                            Label("Apply to Scene", systemImage: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity).frame(height: 34)
                                .background(themeVM.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                DARTPanelCard(title: "Environment Physics", icon: "waveform.path") {
                    VStack(spacing: 6) {
                        DARTPhysicsRow(label: "Temperature", value: labVM.physics.temperature,
                                       unit: "°F", range: -200...2000,
                                       binding: Binding(get:{labVM.physics.temperature},
                                                       set:{labVM.physics.temperature=$0}))
                        DARTPhysicsRow(label: "Gravity", value: labVM.physics.gravity,
                                       unit: "m/s²", range: 0...30,
                                       binding: Binding(get:{labVM.physics.gravity},
                                                       set:{labVM.physics.gravity=$0}))
                        DARTPhysicsRow(label: "Pressure", value: labVM.physics.pressure,
                                       unit: "psi", range: 0...100,
                                       binding: Binding(get:{labVM.physics.pressure},
                                                       set:{labVM.physics.pressure=$0}))
                        DARTPhysicsRow(label: "Viscosity", value: labVM.physics.viscosity,
                                       unit: "cP", range: 0...5000,
                                       binding: Binding(get:{labVM.physics.viscosity},
                                                       set:{labVM.physics.viscosity=$0}))

                        Button { labVM.physics.reset() } label: {
                            Text("Reset to Standard Atmosphere")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(maxWidth: .infinity).frame(height: 28)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                // CFD
                DARTPanelCard(title: "Fluid Dynamics", icon: "wind") {
                    HStack(spacing: 10) {
                        Button {
                            if labVM.isCFDActive { labVM.stopCFD() }
                            else { labVM.startCFD() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: labVM.isCFDActive ? "stop.fill" : "play.fill")
                                    .font(.system(size: 11))
                                Text(labVM.isCFDActive ? "Stop CFD" : "Start CFD")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(labVM.isCFDActive ? .red : .black)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(labVM.isCFDActive ? Color.red.opacity(0.2) : themeVM.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(labVM.isCFDActive ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(labVM.cfdParticles.count) particles")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(themeVM.accent.opacity(0.7))
                            Text("SPH engine")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                }
            }
            .padding(10)
        }
    }
}

struct DARTPhysicsRow: View {
    let label: String
    let value: Double
    let unit: String
    let range: ClosedRange<Double>
    @Binding var binding: Double
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text(String(format: "%.1f", value) + " " + unit)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeVM.accent)
            }
            Slider(value: $binding, in: range).tint(themeVM.accent)
        }
    }
}

// MARK: — Math Panel
struct DARTMathPanel: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var customZ: Int = 1

    var element: ArcElement? {
        labVM.selectedElements.first ??
        ElementStore.shared.elements.first(where: { $0.protons == customZ })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {

                DARTPanelCard(title: "Neutron-First Math", icon: "function") {
                    VStack(spacing: 8) {
                        // Shell chain
                        Text("n⁰ → p⁺ → K → L → M → N → O → P → Q")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(themeVM.accent.opacity(0.7))

                        HStack {
                            Text("Atomic Number Z")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                            Spacer()
                            Stepper("\(customZ)", value: $customZ, in: 1...128)
                                .labelsHidden()
                            Text("\(customZ)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(themeVM.accent)
                                .frame(width: 32)
                        }

                        if let el = element {
                            Divider().background(themeVM.accent.opacity(0.15))

                            HStack(spacing: 6) {
                                DARTMathChip("n⁰", value: "\(el.neutrons)", color: .orange)
                                DARTMathChip("p⁺", value: "\(el.protons)", color: .red)
                                DARTMathChip("e⁻", value: "\(el.electrons)", color: .cyan)
                                DARTMathChip("orbits", value: "\(el.orbits)", color: .purple)
                            }

                            Divider().background(themeVM.accent.opacity(0.15))

                            // Shell distribution
                            let shells = ["K","L","M","N","O","P","Q"]
                            ForEach(Array(el.electronOrbits.enumerated()), id: \.0) { idx, count in
                                HStack(spacing: 8) {
                                    Text(idx < shells.count ? shells[idx] : "?")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(themeVM.accent)
                                        .frame(width: 16)
                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(themeVM.accent.opacity(0.08))
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(themeVM.accent.opacity(0.6))
                                                .frame(width: g.size.width * CGFloat(count) /
                                                       CGFloat(max(el.electronOrbits.max() ?? 1, 1)))
                                        }
                                    }
                                    .frame(height: 6)
                                    Text("\(count)e⁻")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                        .frame(width: 32)
                                }
                            }

                            Divider().background(themeVM.accent.opacity(0.15))

                            DARTMathRow("Atomic Mass",    String(format: "%.6f u", el.atomicMass),    .green)
                            DARTMathRow("n-First Mass",   String(format: "%.6f u", el.neutronFirstMass), .yellow)
                            DARTMathRow("Arc Edge C",     String(format: "%.4f pm", el.arcEdgeCircumference), themeVM.accent)
                        }
                    }
                }

                DARTPanelCard(title: "LEATR Formulas", icon: "angle") {
                    VStack(spacing: 5) {
                        DARTFormulaRow("Arc Edge",       "C = √(d × 3.0)²")
                        DARTFormulaRow("Quantum Socket", "(b·b)·(p(a²))/r")
                        DARTFormulaRow("Sigma Meridian", "φ = 1.618...")
                        DARTFormulaRow("CBS Switch",     "(xa²√xa) ± 1")
                        DARTFormulaRow("Nucleus Blast",  "F > φ × stable")
                    }
                }

                DARTPanelCard(title: "Quantum Socket", icon: "cpu") {
                    DARTQuantumCalc()
                }
            }
            .padding(10)
        }
    }
}

struct DARTMathChip: View {
    let label: String; let value: String; let color: Color
    init(_ label: String, value: String, color: Color) {
        self.label = label; self.value = value; self.color = color
    }
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct DARTMathRow: View {
    let label: String; let value: String; let color: Color
    init(_ l: String, _ v: String, _ c: Color) { label=l; value=v; color=c }
    var body: some View {
        HStack {
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(value).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(color)
        }
    }
}

struct DARTFormulaRow: View {
    let name: String; let formula: String
    @EnvironmentObject var themeVM: ArcThemeViewModel
    init(_ n: String, _ f: String) { name=n; formula=f }
    var body: some View {
        HStack(spacing: 8) {
            Text(name + ":")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 100, alignment: .leading)
            Text(formula)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(themeVM.accent)
            Spacer()
        }
    }
}

struct DARTQuantumCalc: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var b: Double = 1.0
    @State private var p: Double = 1.0
    @State private var a: Double = 1.0
    @State private var r: Double = 1.0
    var result: Double { ArcEdgeMath.quantumSocket(b:b,p:p,a:a,r:r) }

    var body: some View {
        VStack(spacing: 6) {
            Text("(b·b)·(p(a²))/r")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(themeVM.accent)
            ForEach([("b",$b),("p",$p),("a",$a),("r",$r)], id: \.0) { lbl, binding in
                HStack {
                    Text(lbl)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 14)
                    Slider(value: binding, in: 0.1...10.0).tint(themeVM.accent)
                    Text(String(format: "%.2f", binding.wrappedValue))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 36)
                }
            }
            HStack {
                Text("Result:")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                Spacer()
                Text(String(format: "%.6f", result))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.accent)
            }
        }
    }
}

// MARK: — Arc Panel
struct DARTArcPanel: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var selectedComponents: Set<ArcEdgeMath.ArcComponent> = [.group]
    @State private var arcResults: [(String, Double)] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                DARTPanelCard(title: "Arc Edge Algorithm", icon: "circle.and.line.horizontal") {
                    VStack(spacing: 8) {
                        HStack {
                            DARTMathChip("DOC", value: "3.0", color: themeVM.accent)
                            DARTMathChip("φ", value: "1.618", color: .purple)
                        }

                        HStack(spacing: 6) {
                            ForEach(ArcEdgeMath.ArcComponent.allCases, id: \.self) { comp in
                                Toggle(comp.rawValue.capitalized, isOn: Binding(
                                    get: { selectedComponents.contains(comp) },
                                    set: { on in
                                        if on { selectedComponents.insert(comp) }
                                        else  { selectedComponents.remove(comp) }
                                    }))
                                .toggleStyle(.button)
                                .font(.system(size: 8, design: .monospaced))
                                .tint(themeVM.accent)
                            }
                        }

                        Button { computeArcEdge() } label: {
                            Label("Compute Arc Edge", systemImage: "play.circle.fill")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity).frame(height: 34)
                                .background(themeVM.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                if !arcResults.isEmpty {
                    DARTPanelCard(title: "Results", icon: "chart.xyaxis.line") {
                        ForEach(arcResults, id: \.0) { label, val in
                            HStack {
                                Text(label)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Text(String(format: "%.4f pm", val))
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(themeVM.accent)
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    private func computeArcEdge() {
        arcResults = []
        for el in labVM.selectedElements {
            for comp in selectedComponents {
                let d: Double
                switch comp {
                case .group:    d = Double(el.protons + el.neutrons) * 0.1
                case .neutron:  d = Double(el.neutrons) * 0.1
                case .proton:   d = Double(el.protons) * 0.1
                case .electron: d = Double(el.electrons) * 0.05
                }
                arcResults.append(("\(el.elementSymbol).\(comp.rawValue)", ArcEdgeMath.circumference(diameter: d)))
            }
        }
    }
}

// MARK: — Env Panel
struct DARTEnvPanel: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                DARTPanelCard(title: "Large Scale CFD", icon: "cloud.fill") {
                    VStack(spacing: 8) {
                        // Tab selector
                        HStack(spacing: 4) {
                            ForEach(0..<5) { idx in
                                Button { selectedTab = idx; labVM.physics.activeTabIndex = idx } label: {
                                    Text("Tab \(idx+1)")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(selectedTab==idx ? .black : .white.opacity(0.4))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(selectedTab==idx ? themeVM.accent : Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }

                        DARTPhysicsRow(label: "Temperature", value: labVM.physics.tabs[selectedTab].temperature,
                                       unit: "°F", range: -200...2000,
                                       binding: Binding(get:{labVM.physics.tabs[selectedTab].temperature},
                                                       set:{labVM.physics.tabs[selectedTab].temperature=$0}))
                        DARTPhysicsRow(label: "Gravity", value: labVM.physics.tabs[selectedTab].gravity,
                                       unit: "m/s²", range: 0...30,
                                       binding: Binding(get:{labVM.physics.tabs[selectedTab].gravity},
                                                       set:{labVM.physics.tabs[selectedTab].gravity=$0}))
                        DARTPhysicsRow(label: "Pressure", value: labVM.physics.tabs[selectedTab].pressure,
                                       unit: "psi", range: 0...100,
                                       binding: Binding(get:{labVM.physics.tabs[selectedTab].pressure},
                                                       set:{labVM.physics.tabs[selectedTab].pressure=$0}))
                        DARTPhysicsRow(label: "Viscosity", value: labVM.physics.tabs[selectedTab].viscosity,
                                       unit: "cP", range: 0...5000,
                                       binding: Binding(get:{labVM.physics.tabs[selectedTab].viscosity},
                                                       set:{labVM.physics.tabs[selectedTab].viscosity=$0}))

                        HStack {
                            Text("Σ")
                                .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                            Spacer()
                            Text(String(format: "%.4f", labVM.physics.tabs[selectedTab].sigmaReadout))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(themeVM.accent)
                        }
                    }
                }
            }
            .padding(10)
        }
    }
}

// MARK: — Log Panel
struct DARTLogPanel: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var filter = ""

    var logs: [LogEntry] {
        filter.isEmpty ? labVM.logEntries :
        labVM.logEntries.filter { $0.message.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(themeVM.accent.opacity(0.5))
                TextField("Filter...", text: $filter)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                Spacer()
                if !labVM.logEntries.isEmpty {
                    Button { labVM.logEntries.removeAll() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.5))
                    }
                }
                Text("\(labVM.logEntries.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.black.opacity(0.4))
            .overlay(Rectangle().frame(height: 0.5)
                .foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timeString)
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(themeVM.accent.opacity(0.4))
                                .frame(width: 50)
                            Text(entry.message)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 3)
                        .background(Color.white.opacity(0.015))
                        Divider().background(Color.white.opacity(0.04))
                    }
                    if logs.isEmpty {
                        Text(filter.isEmpty ? "No log entries" : "No matches")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                            .frame(maxWidth: .infinity).padding(20)
                    }
                }
            }
        }
    }
}

