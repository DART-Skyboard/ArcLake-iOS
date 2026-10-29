import SwiftUI
import SceneKit
import UIKit

// ═══════════════════════════════════════════════════════════════════
// ArcFluidView — Arc Edge Fluid Dynamics UI
// Mesh-conformal SPH · Alloy material editor · Thermal colormap
// References: See ArcFluidEngine.swift header
// ═══════════════════════════════════════════════════════════════════

struct ArcFluidView: View {
    @StateObject private var eng = ArcFluidEngine.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var panelTab: FTab = .build
    @State private var expandedComponent: UUID? = nil
    @State private var showMantisSettings = false
    @StateObject private var compoundLibrary = ArcCompoundLibrary.shared
    @State private var showSaveCompoundPrompt = false
    @State private var showCompoundLibrarySheet = false
    @State private var newCompoundName = ""

    // "Build" merges in the element/compound-building flow (previously a
    // separate Atoms tab) so designing a compound and simulating its fluid
    // behavior are one continuous flow, per user request — not two tabs
    // the user has to hop between.
    enum FTab: String, CaseIterable { case build="Build", setup="Setup", materials="Materials", measure="Measure" }

    var body: some View {
        VStack(spacing:0) {
            header
            tabBar
            ScrollView(showsIndicators:false) {
                VStack(spacing:10) {
                    switch panelTab {
                    case .build:     buildPanel
                    case .setup:     setupPanel
                    case .materials: materialsPanel
                    case .measure:   measurePanel
                    }
                    Spacer(minLength:20)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red:0.02,green:0.04,blue:0.09))
        .overlay {
            if eng.isLoading {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    ArcLoadingOverlay(eng: eng, accent: themeVM.accent)
                        .padding(.horizontal, 16)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: eng.isLoading)
    }

    private func launchCFD() {
        let syms: [String] = labVM.selectedElements.isEmpty
            ? ["O","H","H"]
            : labVM.selectedElements.map { $0.elementSymbol }
        let tempF = labVM.physics.temperature   // °F direct on PhysicsState
        let tempK = Float((tempF - 32.0) * 5.0/9.0 + 273.15)
        let pressurePa = Float(labVM.physics.pressure * 6894.76)
        // Auto-play: when the simulation is up, start the bottom transport
        // (play only — never auto-REC) so the module's own animation runs.
        let vm = labVM
        eng.onReady = { if !vm.isPlaying { vm.transportPlay() } }
        eng.start(in: labVM.scene, elementSymbols: syms,
                  envTempK: tempK, envPressurePa: pressurePa)
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
                    .fixedSize(horizontal: false, vertical: true)
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
        }.padding(.horizontal,12).padding(.top,8)
    }

    private var tabBar: some View {
        HStack(spacing:0) {
            ForEach(FTab.allCases, id:\.self) { t in
                Button { panelTab = t } label: {
                    Text(t.rawValue)
                        // Was size:9 — fit fine at 3 tabs (Setup/Materials/
                        // Measure), but adding "Build" as a 4th tab narrowed
                        // each one enough that "Materials" wrapped mid-word
                        // ("Material" / "s") instead of fitting on one line.
                        // lineLimit+minimumScaleFactor is the real fix (it
                        // shrinks instead of wrapping at any tab count),
                        // with the smaller base size so it rarely needs to.
                        .font(.system(size:8,weight:.bold,design:.monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundColor(panelTab==t ? .black : .white.opacity(0.5))
                        .frame(maxWidth:.infinity).padding(.vertical,7)
                        .padding(.horizontal, 2)
                        .background(panelTab==t ? themeVM.accent : Color.clear)
                }
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius:8))
        .padding(.horizontal,12).padding(.vertical,6)
    }

    // MARK: — BUILD TAB (element/compound builder, merged in from the old
    // standalone Atoms tab so building a compound and simulating it are one
    // continuous flow)
    private var buildPanel: some View {
        VStack(spacing:10) {
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

            // All 7 original action tiles from the old standalone Atoms
            // tab (DARTMoleculePanel) — a prior pass here only brought
            // over 3 of them (Periodic Table/Mol Canvas/Clear All) and
            // silently dropped Export GLB, Export Blender, Mantis Nav and
            // Node Editor. Restored to the full original set; nothing
            // should be missing from what build 388 had.
            DARTPanelCard(title: "Build Actions", icon: "sparkles") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 68, maximum: 120), spacing: 8)],
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
                    DARTActionTile(label: "Export\nBlender", icon: "cube.transparent",
                                   color: Color(red:1.0,green:0.45,blue:0.0)) {
                        // Export Arc Lake scene as Blender Python setup script + JSON
                        if let exportDir = ArcBlenderExporter.exportToZip(labVM: labVM) {
                            var shareItems: [URL] = []
                            if let contents = try? FileManager.default.contentsOfDirectory(
                                at: exportDir, includingPropertiesForKeys: nil) {
                                shareItems = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
                            }
                            if shareItems.isEmpty { shareItems = [exportDir] }
                            let av = UIActivityViewController(
                                activityItems: shareItems, applicationActivities: nil)
                            av.completionWithItemsHandler = { _, _, _, _ in
                                try? FileManager.default.removeItem(at: exportDir)
                            }
                            UIApplication.shared.connectedScenes
                                .compactMap { $0 as? UIWindowScene }
                                .first?.windows.first?
                                .rootViewController?.present(av, animated: true)
                        }
                    }
                    DARTActionTile(label: "Mantis\nNav", icon: "paperplane.fill",
                                   color: Color(red: 0.35, green: 0.78, blue: 1.0)) {
                        labVM.openMantisTab()      // dedicated tab + live flight
                        showMantisSettings = true  // settings apply instantly
                    }
                    DARTActionTile(label: "Node\nEditor", icon: "circle.grid.cross",
                                   color: .orange) {
                        withAnimation(.spring()) { labVM.isNodeEditorVisible.toggle() }
                    }
                    DARTActionTile(label: "Clear\nAll", icon: "trash",
                                   color: .red.opacity(0.8)) {
                        labVM.clearElements()
                    }
                }
            }
            .sheet(isPresented: $showMantisSettings) { MantisSettingsSheet(model: labVM.mantis) }

            // Task #39: named/saved compound library — lets the user give
            // whatever is currently on the canvas a scientific/display name
            // and keep it forever, instead of it only existing as transient
            // selectedElements state. Feeds task #40 (the component-fill
            // picker) and the Mantis Nav propellant system.
            DARTPanelCard(title: "Compound Library", icon: "flask.fill") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            newCompoundName = ""
                            showSaveCompoundPrompt = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down").font(.system(size: 11))
                                Text("Save Compound").font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(labVM.selectedElements.isEmpty ? Color.gray : themeVM.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .disabled(labVM.selectedElements.isEmpty)

                        Button {
                            showCompoundLibrarySheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet.rectangle").font(.system(size: 11))
                                Text("Manage (\(compoundLibrary.compounds.count))")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .foregroundColor(.white.opacity(0.8)).frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    Text("Saved compounds become selectable fills for any tank/channel in the 3D scene — tap a component, pick it under Propellant / Fluid.")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                }
            }
            .alert("Save Compound", isPresented: $showSaveCompoundPrompt) {
                TextField("Compound name (e.g. \"My Fuel Mix\")", text: $newCompoundName)
                Button("Save") {
                    _ = compoundLibrary.save(name: newCompoundName, elements: labVM.selectedElements)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saves the \(labVM.selectedElements.count) atom(s) currently on the canvas as a named compound you can reuse later.")
            }
            .sheet(isPresented: $showCompoundLibrarySheet) {
                ArcCompoundLibraryView()
            }

            Text("Build a compound here, then switch to Setup to simulate its fluid behavior.")
                .font(.system(size:8,design:.monospaced))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: — SETUP TAB
    private var setupPanel: some View {
        VStack(spacing:10) {
            // Task #43: one-tap built-in demo — lets a brand-new user see
            // the whole import → auto-classify → fill → simulate chain
            // work immediately, before ever importing their own model.
            demoLoadCard

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

            // Particle visual mode
            card("PARTICLE VISUAL") {
                HStack(spacing:4) {
                    ForEach(ArcParticleVisual.allCases) { v in
                        Button { eng.particleVisual = v } label: {
                            VStack(spacing:2) {
                                Image(systemName:v.icon).font(.system(size:12))
                                Text(v.rawValue).font(.system(size:7,weight:.bold,design:.monospaced))
                            }
                            .foregroundColor(eng.particleVisual==v ? .black : .white.opacity(0.6))
                            .frame(maxWidth:.infinity).padding(.vertical,7)
                            .background(eng.particleVisual==v ? themeVM.accent : Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius:8))
                        }
                    }
                }
                // Arc Grid Vector context note
                Text("Particles spawn within Arc Grid Vector cavity volumes — pressure-driven per component spec")
                    .font(.system(size:7,design:.monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
            }

            card("RENDER") {
                VStack(alignment:.leading, spacing:6) {
                    toggleRow("Volumetric render", isOn: Binding(
                        get:{ eng.particleVisual == .volumetric },
                        set:{ eng.particleVisual = $0 ? .volumetric : .points }), tint: .green)
                    toggleRow("X-ray interior glow", isOn: $eng.xrayGlow, tint: .cyan)
                    toggleRow("Floor thermal map", isOn: $eng.floorHeatEnabled, tint: .orange)
                    if let msg = eng.volumetricStatus {
                        Text(msg)
                            .font(.system(size:7,design:.monospaced))
                            .foregroundColor(.orange)
                    }
                    Text("Volumetric is on by default. Turn it off to fall back to point sprites if it runs choppy.")
                        .font(.system(size:7,design:.monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            // Auto-seal joints (geometric intersection + through-cavity test)
            card("JOINTS") {
                VStack(alignment:.leading, spacing:6) {
                    toggleRow("Auto-seal intersecting parts", isOn: $eng.autoSealEnabled, tint: .green)
                    toggleRow("Live leaks when a seal breaks", isOn: $eng.liveLeaksEnabled, tint: .red)
                    if eng.joints.isEmpty {
                        Text(eng.sealStatus.isEmpty
                             ? "Starts with the simulation: overlapping parts whose hollow interiors connect become sealed fluid links."
                             : eng.sealStatus)
                            .font(.system(size:7,design:.monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    } else {
                        ForEach(eng.joints) { j in
                            HStack(alignment:.top, spacing:5) {
                                Text(j.sealed && !eng.leakingJointIDs.contains(j.id) ? "✓" : "✕")
                                    .font(.system(size:9,weight:.bold,design:.monospaced))
                                    .foregroundColor(j.sealed && !eng.leakingJointIDs.contains(j.id) ? .green : .red)
                                VStack(alignment:.leading, spacing:1) {
                                    Text("\(jointName(j.partA)) ↔ \(jointName(j.partB))")
                                        .font(.system(size:8,design:.monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                    Text(eng.leakingJointIDs.contains(j.id)
                                         ? "LEAKING · " + (eng.leakInfo[j.id] ?? "venting")
                                         : (j.sealed ? "sealed · auto, from mesh overlap" : "non-flowing · overlap, no fluid path"))
                                        .font(.system(size:7,design:.monospaced))
                                        .foregroundColor(eng.leakingJointIDs.contains(j.id) ? Color.red.opacity(0.85) : Color.white.opacity(0.4))
                                }
                            }
                        }
                        Text(eng.sealStatus)
                            .font(.system(size:7,design:.monospaced))
                            .foregroundColor(.white.opacity(0.3))
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
                        accent(String(format:"%.0f K", eng.envTempK > 0 ? eng.envTempK : 293))
                    }
                    HStack {
                        mono("Env Pressure").frame(maxWidth:.infinity,alignment:.leading)
                        accent(String(format:"%.1f psi",
                               Double(eng.envPressurePa > 0 ? eng.envPressurePa : 101325) / 6894.76))
                    }
                    // Task #44: these sliders only drive the GENERIC preset
                    // scenes (dam/wave/drop/orbital/stream) that have no
                    // imported-model components to scan — they do NOT
                    // affect a per-component CFD run against an imported
                    // GLB. Kept as a one-line caption rather than removing
                    // or redesigning anything, since the generic presets
                    // are still real, used paths.
                    Text(eng.componentSpecs.isEmpty
                         ? "Generic preset scene controls — no imported components detected"
                         : "Generic preset controls only — this scene's imported components are configured per-part: tap one in the 3D view")
                        .font(.system(size:7,design:.monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
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
                Button { launchCFD() } label: {
                    HStack(spacing:8) {
                        Image(systemName:"flame.fill").font(.system(size:14))
                        Text("IGNITE — FILL & SIMULATE")
                            .font(.system(size:11,weight:.bold,design:.monospaced)).tracking(1)
                    }
                    .foregroundColor(.black).frame(maxWidth:.infinity).padding(.vertical,14)
                    .background(themeVM.accent).clipShape(RoundedRectangle(cornerRadius:12))
                }
                VStack(spacing:3) {
                    if !ArcFluidEngine.shared.componentSpecs.isEmpty {
                        Text("Auto-fills named cavities (LOX + LH₂ at 200 psi)")
                            .font(.system(size:8,design:.monospaced)).foregroundColor(.green.opacity(0.7))
                    } else {
                        Text("\(eng.particleCount) particles · \(eng.mode.rawValue)")
                            .font(.system(size:8,design:.monospaced)).foregroundColor(.white.opacity(0.35))
                    }
                    Text("Tap any component in the 3D scene to select + configure it")
                        .font(.system(size:7,design:.monospaced)).foregroundColor(.white.opacity(0.28))
                }.multilineTextAlignment(.center)
            }

            // Credits
            credits
        }
    }

    // MARK: — Task #43: one-tap built-in demo
    @State private var loadingDemo = false
    @State private var demoLoadError: String? = nil

    private var demoLoadCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundColor(.orange).font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text("LOAD DEMO: ROCKET COMBUSTION")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Bundled model · auto-fills Fuel + Oxidizer · ready to ignite")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            }
            Button {
                loadCombustionDemo()
            } label: {
                HStack(spacing: 6) {
                    if loadingDemo {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 12))
                    }
                    Text(loadingDemo ? "LOADING…" : "LOAD & IGNITE DEMO")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                }
                .foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Color.orange).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            // Previously also `|| eng.isRunning`, which silently disabled
            // this button with NO visual change (a disabled button here
            // kept the exact same solid-orange look — SwiftUI's default
            // .disabled() dims content via opacity, but this label was
            // fully opaque black-on-orange either way) any time a sim was
            // already running from an earlier tap/session — e.g. an
            // earlier "Load & Ignite" attempt that actually succeeded in
            // calling eng.start() before the user reopened this tab, or
            // manually launching a sim another way first. The result
            // looked exactly like "nothing happens when I tap it": no
            // spinner, no error, no visible disabled state, because
            // nothing actually happened — the tap never reached
            // loadCombustionDemo() at all. Load & Ignite Demo should
            // always be able to (re)start the demo, so it now just stops
            // any existing sim first (loadCombustionDemo below calls
            // eng.stop() before eng.start() runs) instead of refusing to
            // run. .opacity(...) replaces the invisible .disabled() dimming
            // so a genuinely busy state (mid-download) is visually obvious
            // instead of silently absorbing the tap.
            .disabled(loadingDemo || eng.isLoading)
            .opacity(loadingDemo || eng.isLoading ? 0.6 : 1.0)
            if eng.isLoading {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(eng.loadStage)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text("\(Int(eng.loadProgress * 100))%")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    ProgressView(value: eng.loadProgress).tint(.orange)
                    Button { eng.cancelLoading(); loadingDemo = false } label: {
                        Text("CANCEL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.red.opacity(0.9))
                    }
                }
            }
            if let err = eng.loadError ?? demoLoadError {
                Text(err).font(.system(size: 7, design: .monospaced)).foregroundColor(.red.opacity(0.8))
            }
            if let vmsg = eng.volumetricStatus {
                Text(vmsg).font(.system(size: 7, design: .monospaced)).foregroundColor(.orange)
            }
            if eng.isRunning {
                Text("A simulation is already running — tapping this restarts it with the demo scene.")
                    .font(.system(size: 7, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(10).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Loads the bundled Combustion_flow demo asset (downloaded/cached via
    /// the same remote-asset mechanism Mantis Nav already uses for its
    /// built-in assets — see MantisNavModel.remoteAssets/loadRemoteAsset),
    /// scans components, auto-fills Fuel/Oxidizer via
    /// ArcFluidEngine.autoFillCombustionDemo (through eng.start, which
    /// already calls it), and starts the simulation — all in one tap so a
    /// new user sees the whole import → classify → fill → simulate chain
    /// work before ever importing their own model.
    private func loadCombustionDemo() {
        loadingDemo = true; demoLoadError = nil
        // Restart semantics: stop any running sim first, THEN show progress.
        if eng.isRunning { eng.stop() }
        eng.beginLoading(stage: "Downloading asset", progress: 0.02)
        guard let demoAsset = MantisNavModel.remoteAssets.first(where: { $0.resource == "Combustion_flow" }) else {
            demoLoadError = "Demo asset not found"; loadingDemo = false
            eng.failLoading("Demo asset not found"); return
        }
        Task(priority: .userInitiated) {
            // Download off the main actor first (cachedRemoteURL is
            // `nonisolated async`, a true suspending call with no blocking
            // wait anywhere inside it), THEN hop onto the main actor only
            // to parse the GLB and mutate the scene graph — SceneKit scene
            // access genuinely needs to be on-actor, but the multi-MB
            // network fetch does not, and doing the fetch inside
            // MainActor.run would freeze the UI for however long the
            // download takes.
            // Grab the (nonisolated-method-bearing) mantis reference while
            // still on the main actor — this Task closure itself is NOT
            // main-actor-isolated (a plain `Task { }` doesn't inherit the
            // enclosing View's actor), so reaching `labVM.mantis` from
            // inside it requires an isolation hop; doing that hop ONCE
            // here (cheap: just reads a stored property) and then calling
            // the nonisolated download method on the captured reference
            // keeps the actual multi-MB network fetch off the main actor.
            // MantisNavModel.labVM is a weak back-reference that is normally only
            // wired when the Mantis Nav panel appears. From the Fluid tab it is
            // still nil, so loadRemoteAsset() saw no scene and failed with
            // "No active scene" (the 404-406 'demo button does nothing' report).
            // Link it here, on the main actor, before any load.
            let mantis = await MainActor.run { () -> MantisNavModel in
                let m = labVM.mantis
                if m.labVM == nil { m.labVM = labVM }
                // Clean reload: a previous copy of the demo (from an earlier tap)
                // must go before loadRemoteAsset runs, otherwise it returns the
                // stale node early and the tap would not reset anything. Specs are
                // cleared too so no stale per-part state outlives the old node.
                let demoNodeName = "glb_import_\(demoAsset.resource)"
                for sc in labVM.allTabScenes() {
                    while let old = sc.rootNode.childNode(withName: demoNodeName, recursively: false) {
                        old.removeFromParentNode()
                    }
                }
                if m.vehicleAsset == demoNodeName { m.vehicleAsset = nil }
                eng.componentSpecs = []
                return m
            }
            var downloadErr: String?
            let preDownloadedURL: URL?
            do {
                // cachedRemoteURL is async + nonisolated now (no more
                // DispatchSemaphore.wait()): awaiting it here suspends
                // this Task without blocking Swift Concurrency's
                // cooperative thread pool. The pre-fix blocking version is
                // what caused "I hit the button and nothing happened" —
                // see cachedRemoteURL's own doc comment for the full
                // mechanism (a blocked cooperative thread can starve the
                // whole pool, silently hanging with no error and no
                // spinner update, rather than erroring out like a normal
                // network failure would).
                preDownloadedURL = try await mantis.cachedRemoteURL(resource: demoAsset.resource, remoteURL: demoAsset.url)
            } catch {
                preDownloadedURL = nil
                downloadErr = (error as? ArcAssetDownloadError)?.userMessage ?? error.localizedDescription
            }
            await MainActor.run { eng.updateLoading(stage: "Loading model", progress: 0.08) }
            var loadErr: String? = downloadErr
            let nodeName: String? = preDownloadedURL == nil ? nil : await mantis.loadRemoteAsset(resource: demoAsset.resource, remoteURL: demoAsset.url, errorOut: &loadErr)
            await MainActor.run {
                loadingDemo = false
                if eng.loadCancelled { return }        // user cancelled during download/parse
                guard let loadedName = nodeName else {
                    // Surface the REAL failure reason (download transport
                    // error, bad HTTP status, or the file downloaded fine
                    // but failed to parse as a GLB) instead of a blanket
                    // "check network connection" — that message was
                    // actively misleading when the real cause (confirmed
                    // via direct curl of the asset URL: downloads cleanly,
                    // 8.5MB, HTTP 200) was the old loader's use of
                    // Data(contentsOf:), an unreliable synchronous
                    // Foundation API, not an actual network problem.
                    demoLoadError = loadErr ?? "Couldn't load the demo asset"
                    eng.failLoading(demoLoadError ?? "Couldn't load the demo asset")
                    return
                }
                // Stop any already-running sim first: ArcFluidEngine.start()
                // has `guard !isRunning else { return }` at its very top, so
                // calling launchCFD() below while eng.isRunning was already
                // true did nothing at all — no error, no state change, the
                // exact "I hit the button and nothing happened" symptom,
                // just one step further down the call chain than the
                // previous async-hang bug this build also fixes. Load &
                // Ignite Demo should always be able to (re)start the demo
                // regardless of what was running before.
                // Exactly the Assets-menu path (loadRemoteAsset + setActiveVehicle):
                // the demo becomes the active vehicle, so it sits at the origin with
                // its nozzle base flush on the grid (y = 0) and rises along +Y.
                mantis.setActiveVehicle(loadedName)
                eng.loadBase = 0.15          // download + parse already accounted for
                // Re-scan so the newly-added nodes are picked up as
                // components (hardcoded Combustion_flow.glb names resolve
                // via ArcCombustionFlow.componentRoles as usual), then
                // launch — eng.start already calls autoFillCombustionDemo
                // internally, which fills Fuel/Oxidizer at sensible
                // pressures and flips scenePreset to .stream.
                eng.scanComponentSpecsPublic(labVM.scene)
                launchCFD()
            }
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
                        toggleRow("Inlet", isOn: spec.isInlet, tint: .green)
                        toggleRow("Outlet", isOn: spec.isOutlet, tint: .orange)
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
    private func jointName(_ node: String) -> String {
        eng.componentSpecs.first(where:{ $0.nodeName == node })?.displayName ?? node
    }

    private func card<C:View>(_ title:String, @ViewBuilder content:()->C) -> some View {
        VStack(alignment:.leading, spacing:8) {
            Text(title).font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:12))
    }

    /// Label (wraps, never pushes the control off-panel) + trailing control.
    private func toggleRow(_ label: String, isOn: Binding<Bool>, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size:10,design:.monospaced))
                .foregroundColor(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Toggle("", isOn: isOn).labelsHidden().tint(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mono(_ s:String) -> some View {
        // .fixedSize(horizontal:true) stops this label from being
        // compressed below its natural width by a neighboring flexible
        // view (a Slider, Spacer, etc.) in a tight HStack — without it,
        // short labels like "Particles" or "Materials" can get squeezed
        // and wrap mid-word ("Particle" / "s") instead of staying on one
        // line, which is what was happening in the Parameters card.
        Text(s).font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.65))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
    private func accent(_ s:String) -> some View {
        Text(s).font(.system(size:9,design:.monospaced)).foregroundColor(themeVM.accent)
    }
    private func sldr(_ label:String, val:Binding<Double>, lo:Double, hi:Double, fmt:String) -> some View {
        HStack {
            mono(label)
            Slider(value:val, in:lo...hi).tint(themeVM.accent)
            accent(String(format:fmt,val.wrappedValue)).frame(minWidth:44,alignment:.trailing)
        }
    }
    private func sldrF(_ label:String, val:Binding<Float>, lo:Float, hi:Float, fmt:String) -> some View {
        HStack {
            mono(label)
            Slider(value:val, in:lo...hi).tint(themeVM.accent)
            accent(String(format:fmt,val.wrappedValue)).frame(minWidth:44,alignment:.trailing)
        }
    }
    private func sldrD(_ label:String, val:Binding<Double>, lo:Double, hi:Double, fmt:String) -> some View {
        HStack {
            mono(label)
            Slider(value:val, in:lo...hi).tint(themeVM.accent)
            accent(String(format:fmt,val.wrappedValue)).frame(minWidth:44,alignment:.trailing)
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



// MARK: — Loading overlay (spinner + real percentage + stage name + cancel)
struct ArcLoadingOverlay: View {
    @ObservedObject var eng: ArcFluidEngine
    let accent: Color
    @State private var spin = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                Text("\(Int(max(0, min(1, eng.loadProgress)) * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(width: 84, height: 84)

            Text(eng.loadStage.isEmpty ? "Working…" : eng.loadStage)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: max(0, min(1, eng.loadProgress)))
                .tint(accent)
                .frame(maxWidth: 260)

            Button { eng.cancelLoading() } label: {
                Text("CANCEL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(22)
        .frame(maxWidth: 320)
        .background(Color(red: 0.04, green: 0.07, blue: 0.14).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.35), lineWidth: 1))
        .onAppear { spin = true }
    }
}
