import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// ArcFieldArrayViews — UI for the Arc Edge Field Array, Math SET
// cards, Physics environment presets, and the transport bar.
// Mirrors the arclake.html web-app panels (IMG_1068–1072 reference).
// ═══════════════════════════════════════════════════════════════════

// MARK: — ARC EDGE FIELD ARRAY (Arc tab)
struct ArcFieldArraySection: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ARC EDGE FIELD ARRAY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45)).tracking(2)

            // Mode 1 — All-Scene component for all-to-all links
            Text("Arc Edge Generation Mode (All Scene)")
                .font(.custom("Exo2-Regular", size: 11))
                .foregroundColor(themeVM.accent.opacity(0.85))
            Menu {
                Button("Select Component for All-to-All Links") {
                    labVM.arcAllSceneComponent = nil; labVM.rebuildArcMeasures()
                }
                ForEach(ArcComponentField.allCases) { f in
                    Button(f.label) {
                        labVM.arcAllSceneComponent = f; labVM.rebuildArcMeasures()
                    }
                }
            } label: {
                HStack {
                    Text(labVM.arcAllSceneComponent?.label ?? "Select Component for All-to-All Links")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(labVM.arcAllSceneComponent == nil ? 0.4 : 0.9))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8)).foregroundColor(.white.opacity(0.35))
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Mode 2 — Sequential selection
            Text("SEQUENTIAL SELECTION (MULTI-SELECT)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.accent).tracking(1.5)

            ForEach(ArcComponentField.allCases) { f in
                Toggle(isOn: Binding(
                    get: { labVM.arcFieldComponents.contains(f) },
                    set: { on in
                        if on { labVM.arcFieldComponents.insert(f) }
                        else  { labVM.arcFieldComponents.remove(f) }
                        labVM.rebuildArcMeasures()
                    })) {
                    HStack(spacing: 6) {
                        Circle().fill(f.swiftColor).frame(width: 7, height: 7)
                        Text(f.label)
                            .font(.custom("Exo2-Regular", size: 12))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .tint(themeVM.accent)
            }
            Toggle(isOn: Binding(
                get: { labVM.arcSameKindFilter },
                set: { labVM.arcSameKindFilter = $0; labVM.rebuildArcMeasures() })) {
                Text("Elements of Same Kind (Filter)")
                    .font(.custom("Exo2-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.85))
            }
            .tint(themeVM.accent)

            // Atom list — tap toggles in LINK ORDER, badge shows the order
            VStack(spacing: 4) {
                if labVM.selectedElements.isEmpty {
                    Text("0 Items")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                } else {
                    ForEach(labVM.selectedElements, id: \.id) { el in
                        let order = labVM.arcSeqSelection.firstIndex(of: el.id)
                        Button { labVM.toggleArcSelection(el.id) } label: {
                            HStack {
                                ZStack {
                                    Circle()
                                        .stroke(order != nil ? themeVM.accent : Color.white.opacity(0.25),
                                                lineWidth: 1.2)
                                        .frame(width: 20, height: 20)
                                    if let o = order {
                                        Text("\(o + 1)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(themeVM.accent)
                                    }
                                }
                                Text("\(el.elementSymbol) (\(el.id))")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(order != nil ? 0.95 : 0.6))
                                Spacer()
                                Text("Z=\(el.protons)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .padding(.vertical, 5).padding(.horizontal, 8)
                            .background(Color.white.opacity(order != nil ? 0.07 : 0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
            Text("Tap atoms in link order — N1 → N2 → N3…")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))

            if !labVM.arcSeqSelection.isEmpty || labVM.arcAllSceneComponent != nil {
                Button {
                    labVM.arcSeqSelection = []
                    labVM.arcAllSceneComponent = nil
                    labVM.rebuildArcMeasures()
                } label: {
                    Text("CLEAR LINKS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            // Live results — length, finite curvature κ, velocity potentials
            if !labVM.arcMeasureResults.isEmpty {
                Divider().background(Color.white.opacity(0.08))
                HStack {
                    Text("MEASUREMENTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.accent).tracking(1.5)
                    Spacer()
                    Text("Σ " + labVM.lengthLabel(labVM.arcEdgeLengthSum))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                }
                ForEach(labVM.arcMeasureResults) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(r.field.swiftColor).frame(width: 7, height: 7)
                            Text(r.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Text(labVM.lengthLabel(r.length))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(r.field.swiftColor)
                        }
                        Text("κ \(labVM.fmtMath(r.curvature))  ·  Φa \(labVM.fmtMath(r.phiA))  ·  Φb \(labVM.fmtMath(r.phiB))")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.leading, 13)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: — MATH SET CARDS (Math tab)
struct MathSetsSection: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    private let comps: [(String, String)] = {
        var c: [(String, String)] = [
            ("all", "Full Atom"), ("neutron", "Neutron(s)"),
            ("proton", "Proton(s)"), ("all_electrons", "All Electrons")]
        for s in ARC_SHELL_NAMES { c.append(("shell_\(s)", "Shell \(s)")) }
        c.append(("phys_temperature", "Phys: Temp"))
        c.append(("phys_gravity", "Phys: Gravity"))
        c.append(("phys_velocity", "Phys: Velocity"))
        return c
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Math flows neutron→proton (radian/degree)→electron/shell. Results update the 3D scene, Mol Canvas, Orbit Delta and CFD nodes.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(labVM.mathSets.indices, id: \.self) { i in
                setCard(i)
                if i < labVM.mathSets.count - 1 {
                    Toggle(isOn: Binding(
                        get: { labVM.mathSets[i+1].linked },
                        set: { if i+1 < labVM.mathSets.count { labVM.mathSets[i+1].linked = $0 } })) {
                        Text("🔗 Link set \(i+1) → \(i+2) (nest outward)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .tint(themeVM.accent)
                    .padding(.horizontal, 4)
                }
            }

            Toggle(isOn: $labVM.mathSigmaEnv) {
                Text("Σ vs Environment (× gravity × pressure/14.7)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .tint(themeVM.accent)

            Button { labVM.executeAdvMath() } label: {
                Text("CALCULATE  Σ")
                    .font(.custom("Orbitron-Bold", size: 12))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(themeVM.accent)
                    .clipShape(Capsule())
            }

            if labVM.mathSigma != 0 || !labVM.mathChain.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Σ Result = \(labVM.fmtMath(labVM.mathSigma))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                    ForEach(labVM.mathChain.indices, id: \.self) { i in
                        Text(labVM.mathChain[i])
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func setCard(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SET \(i + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.accent).tracking(1.5)
                Spacer()
                Toggle(isOn: Binding(
                    get: { labVM.mathSets[i].vsEnv },
                    set: { if i < labVM.mathSets.count { labVM.mathSets[i].vsEnv = $0 } })) {
                    Text("vs Env")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .tint(themeVM.accent)
                .fixedSize()
            }

            HStack(spacing: 8) {
                atomCompColumn(i, isSource: true)
                // Operator + radical
                VStack(spacing: 5) {
                    Menu {
                        ForEach(ARC_MATH_OPS, id: \.val) { op in
                            Button(op.label) {
                                if i < labVM.mathSets.count { labVM.mathSets[i].op = op.val }
                            }
                        }
                    } label: {
                        Text(ARC_MATH_OPS.first(where: { $0.val == labVM.mathSets[i].op })?.label ?? "×")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                            .frame(width: 44, height: 30)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    Toggle(isOn: Binding(
                        get: { labVM.mathSets[i].radical },
                        set: { if i < labVM.mathSets.count { labVM.mathSets[i].radical = $0 } })) {
                        Text("√").font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .toggleStyle(.button).tint(themeVM.accent)
                }
                atomCompColumn(i, isSource: false)
            }

            if let r = labVM.mathSets[i].result {
                Text("= \(labVM.fmtMath(r))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(themeVM.accent.opacity(0.12), lineWidth: 0.7))
    }

    @ViewBuilder
    private func atomCompColumn(_ i: Int, isSource: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isSource ? "⚙ Source" : "⚡ Target")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(isSource ? Color.orange.opacity(0.8) : themeVM.accent.opacity(0.8))
            Menu {
                Button("Env") { setAtom(i, isSource: isSource, id: -1) }
                ForEach(labVM.selectedElements, id: \.id) { el in
                    Button("\(el.elementSymbol) (\(el.id))") {
                        setAtom(i, isSource: isSource, id: el.id)
                    }
                }
            } label: {
                let cur = isSource ? labVM.mathSets[i].atomA : labVM.mathSets[i].atomB
                Text(cur != nil ? labVM.mathLabel(cur) : "Atom (?)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(cur == nil ? 0.4 : 0.9))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Menu {
                ForEach(comps, id: \.0) { c in
                    Button(c.1) {
                        if i < labVM.mathSets.count {
                            if isSource { labVM.mathSets[i].compA = c.0 }
                            else        { labVM.mathSets[i].compB = c.0 }
                        }
                    }
                }
            } label: {
                let cur = isSource ? labVM.mathSets[i].compA : labVM.mathSets[i].compB
                Text(comps.first(where: { $0.0 == cur })?.1 ?? cur)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func setAtom(_ i: Int, isSource: Bool, id: Int) {
        guard i < labVM.mathSets.count else { return }
        if isSource { labVM.mathSets[i].atomA = id }
        else        { labVM.mathSets[i].atomB = id }
    }
}

// MARK: — PHYSICS ENVIRONMENT (Physics tab)
struct PhysicsEnvSection: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🌍 ENVIRONMENT PRESET")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.accent).tracking(1.5)
            Text("Applied to active tab. Every new tab loads Earth defaults.")
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 6) {
                ForEach(EnvPreset.allCases, id: \.self) { p in
                    Button { labVM.applyEnvPreset(p) } label: {
                        Text(p.rawValue)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(labVM.envPreset == p ? .black : .white.opacity(0.7))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(labVM.envPreset == p ? themeVM.accent : Color.white.opacity(0.05))
                            .clipShape(Capsule())
                    }
                }
            }
            if let v = labVM.envPreset.values {
                Text("\(labVM.envPreset.rawValue) — \(String(format: "%.2f", v.g)) m/s² · \(String(format: "%.2f", v.p)) psi · \(String(format: "%.0f", v.t))°F")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.7))
            }

            Divider().background(Color.white.opacity(0.08))

            Text("🌫 MATTER STATE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.accent).tracking(1.5)
            Text("Drives the proton bridge angle in the Math engine.")
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
            Picker("Matter", selection: $labVM.matterState) {
                ForEach(MatterState.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Divider().background(Color.white.opacity(0.08))

            Text("💨 WIND")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.accent).tracking(1.5)
            HStack {
                Text("Velocity")
                    .font(.custom("Exo2-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.8))
                Slider(value: $labVM.windVelocity, in: 0...100)
                    .tint(themeVM.accent)
                Text("\(Int(labVM.windVelocity)) mph")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(themeVM.accent)
                    .frame(width: 56, alignment: .trailing)
            }
            Menu {
                ForEach(WindDir.allCases, id: \.self) { d in
                    Button(d.rawValue) { labVM.windDirection = d }
                }
            } label: {
                HStack {
                    Text("Wind Direction")
                        .font(.custom("Exo2-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(labVM.windDirection.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: — TRANSPORT BAR (footer, above sigma strip)
struct ArcTransportBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        HStack(spacing: 10) {
            // REC — records frames for playback + file export
            Button {
                labVM.isRecording ? labVM.transportStopRecording() : labVM.transportRecord()
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(labVM.isRecording ? Color.red : Color.red.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(labVM.isRecording ? "REC" : "REC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(labVM.isRecording ? .red : .white.opacity(0.55))
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(labVM.isRecording ? Color.red.opacity(0.14) : Color.white.opacity(0.05))
                .clipShape(Capsule())
            }

            // Play / Stop
            Button {
                labVM.isPlaying ? labVM.transportStop() : labVM.transportPlay()
            } label: {
                Image(systemName: labVM.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(labVM.isPlaying ? .black : themeVM.accent)
                    .frame(width: 30, height: 26)
                    .background(labVM.isPlaying ? themeVM.accent : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            // Scrubber — seeks recorded frames
            Slider(
                value: Binding(
                    get: { Double(labVM.playheadFrame) },
                    set: { labVM.transportSeek(frame: Int($0)) }),
                in: 0...Double(max(labVM.recordedFrameCount - 1, 1)))
                .tint(themeVM.accent)
                .disabled(labVM.recordedFrameCount == 0 || labVM.isPlaying)

            Text(String(format: "%.1fs %df",
                        Double(labVM.playheadFrame) / 30.0, labVM.recordedFrameCount))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(red: 0.02, green: 0.04, blue: 0.07).opacity(0.92))
    }
}
