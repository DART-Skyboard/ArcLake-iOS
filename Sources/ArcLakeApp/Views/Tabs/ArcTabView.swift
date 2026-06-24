import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// ArcTabView — Arc Edge + Environment Physics + CFD (merged panel)
//
// Environment settings live here and auto-sync with the active scene
// tab — switching tabs restores each tab's own physics environment.
// CFD component spec, cavity fill, and Arc Edge measurement all here.
// ═══════════════════════════════════════════════════════════════════

public struct ArcTabView: View {
    @EnvironmentObject var labVM:  ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var section: ArcSection = .env

    enum ArcSection: String, CaseIterable {
        case env = "Environment", arc = "Arc Edge", cfd = "CFD"
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Section selector
            HStack(spacing: 0) {
                ForEach(ArcSection.allCases, id: \.self) { s in
                    Button { section = s } label: {
                        Text(s.rawValue)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(section == s ? .black : .white.opacity(0.5))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(section == s ? themeVM.accent : Color.clear)
                    }
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10).padding(.vertical, 6)

            ScrollView(showsIndicators: false) {
                switch section {
                case .env: envSection
                case .arc: arcSection
                case .cfd: cfdSection
                }
            }
        }
    }

    // MARK: — ENVIRONMENT (per active scene tab)
    private var envSection: some View {
        VStack(spacing: 10) {
            // Active tab indicator
            HStack(spacing: 6) {
                Circle().fill(themeVM.accent).frame(width: 6, height: 6)
                Text("SCENE \(labVM.activeTabIndex + 1) ENVIRONMENT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45)).tracking(2)
                Spacer()
                Text("auto-syncs with active tab")
                    .font(.system(size: 6, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }.padding(.horizontal, 12).padding(.top, 8)

            // Planet presets
            card("PRESET ENVIRONMENT") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        presetBtn("Earth 🌍") {
                            setTabPhysics(temp:72, grav:9.8, press:14.7, visc:1.0, hum:50, alt:0)
                        }
                        presetBtn("Mars 🔴") {
                            setTabPhysics(temp:-80, grav:3.72, press:0.087, visc:0.01, hum:0, alt:0)
                        }
                        presetBtn("Venus 🟡") {
                            setTabPhysics(temp:867, grav:8.87, press:1334, visc:28.5, hum:0, alt:0)
                        }
                        presetBtn("Orbit 🛸") {
                            setTabPhysics(temp:-450, grav:0, press:0, visc:0, hum:0, alt:400000)
                        }
                        presetBtn("Deep Sea 🌊") {
                            setTabPhysics(temp:34, grav:9.8, press:4351, visc:1.8, hum:100, alt:-4000)
                        }
                        presetBtn("High Alt ✈️") {
                            setTabPhysics(temp:-65, grav:9.72, press:1.45, visc:0.16, hum:0, alt:35000)
                        }
                    }
                }
                Button("Reset to Standard Atmosphere") {
                    setTabPhysics(temp:72, grav:9.8, press:14.7, visc:1.0, hum:50, alt:0)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            card("ATMOSPHERE") {
                VStack(spacing: 8) {
                    envRow("Temperature", val: Binding(
                        get:{labVM.physics.activeTab.temperature},
                        set:{setTemp($0)}), lo:-460, hi:2000, unit:"°F")
                    envRow("Gravity", val: Binding(
                        get:{labVM.physics.activeTab.gravity},
                        set:{setGrav($0)}), lo:0, hi:30, unit:"m/s²")
                    envRow("Pressure", val: Binding(
                        get:{labVM.physics.activeTab.pressure},
                        set:{setPress($0)}), lo:0, hi:5000, unit:"psi")
                    envRow("Viscosity", val: Binding(
                        get:{labVM.physics.activeTab.viscosity},
                        set:{setVisc($0)}), lo:0, hi:5000, unit:"cP")
                    envRow("Wind Speed", val: Binding(
                        get:{labVM.physics.activeTab.velocity},
                        set:{setVel($0)}), lo:0, hi:500, unit:"m/s")
                    envRow("Humidity", val: Binding(
                        get:{labVM.physics.activeTab.humidity},
                        set:{setHum($0)}), lo:0, hi:100, unit:"%")
                    envRow("Altitude", val: Binding(
                        get:{labVM.physics.activeTab.altitude},
                        set:{setAlt($0)}), lo:-11000, hi:420000, unit:"m")

                    // Derived BTU readouts
                    Divider().background(Color.white.opacity(0.07))
                    HStack {
                        monoLabel("Amb. Temp K")
                        Spacer()
                        accentLabel(String(format:"%.1f K", labVM.physics.activeTab.ambientTempK))
                    }
                    HStack {
                        monoLabel("Pressure Pa")
                        Spacer()
                        accentLabel(String(format:"%.0f Pa", labVM.physics.activeTab.pressurePa))
                    }
                    HStack {
                        monoLabel("Σ Arc Edge")
                        Spacer()
                        accentLabel(String(format:"%.4f", labVM.physics.activeTab.sigmaReadout))
                    }
                }
            }
        }.padding(10)
    }

    // MARK: — ARC EDGE section
    private var arcSection: some View {
        VStack(spacing: 10) {
            card("ARC EDGE ALGORITHM") {
                VStack(spacing: 6) {
                    HStack {
                        monoLabel("DOC (replaces π)")
                        Spacer()
                        accentLabel(String(format:"%.1f", ArcEdgeMath.DOC))
                    }
                    HStack {
                        monoLabel("Sigma Meridian φ")
                        Spacer()
                        Text(String(format:"%.6f", ArcEdgeMath.SIGMA_MERIDIAN))
                            .font(.system(size:9,design:.monospaced)).foregroundColor(.purple)
                    }
                    Divider().background(Color.white.opacity(0.07))
                    ArcFieldArraySection()
                }
            }
            card("ARC EDGE FORMULAS") {
                VStack(spacing:4) {
                    formulaRow("Arc Edge C", "C = √(d × 3.0)²")
                    formulaRow("Quantum Socket", "(b·b)·(p(a²))/r")
                    formulaRow("Sigma Meridian", "φ = 1.618...")
                    formulaRow("CBS Switch", "(xa²√xa) ± 1")
                    formulaRow("Nucleus Blast", "F > φ × stable")
                }
            }
            card("QUANTUM SOCKET") { QuantumSocketCalc() }
            card("ARC RESULTS") {
                if labVM.selectedElements.isEmpty {
                    monoLabel("Add elements to compute Arc Edge values")
                        .foregroundColor(.white.opacity(0.3))
                } else {
                    VStack(spacing:4) {
                        ForEach(labVM.selectedElements, id:\.id) { el in
                            let d = Double(el.protons + el.neutrons) * 0.1
                            let c = ArcEdgeMath.circumference(diameter: d)
                            HStack {
                                monoLabel(el.elementSymbol)
                                Spacer()
                                accentLabel(String(format:"%.4f pm", c))
                            }
                        }
                    }
                }
            }
        }.padding(10)
    }

    // MARK: — CFD section
    private var cfdSection: some View {
        VStack(spacing: 10) {
            ArcCFDComponentPanel()
        }.padding(10)
    }

    // MARK: — Helpers
    private func setTabPhysics(temp:Double,grav:Double,press:Double,visc:Double,hum:Double,alt:Double) {
        var t = labVM.physics.activeTab
        t.temperature=temp; t.gravity=grav; t.pressure=press
        t.viscosity=visc; t.humidity=hum; t.altitude=alt
        labVM.physics.activeTab = t
    }
    private func setTemp(_ v:Double) { labVM.physics.activeTab.temperature = v }
    private func setGrav(_ v:Double) { labVM.physics.activeTab.gravity = v }
    private func setPress(_ v:Double) { labVM.physics.activeTab.pressure = v }
    private func setVisc(_ v:Double) { labVM.physics.activeTab.viscosity = v }
    private func setVel(_ v:Double)  { labVM.physics.activeTab.velocity = v }
    private func setHum(_ v:Double)  { labVM.physics.activeTab.humidity = v }
    private func setAlt(_ v:Double)  { labVM.physics.activeTab.altitude = v }

    private func presetBtn(_ label: String, action: @escaping ()->Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal,8).padding(.vertical,5)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
        }
    }

    private func envRow(_ label:String, val:Binding<Double>, lo:Double, hi:Double, unit:String) -> some View {
        HStack(spacing:6) {
            monoLabel(label).frame(width:80, alignment:.leading)
            Slider(value:val, in:lo...hi).tint(themeVM.accent)
            accentLabel(String(format:"%.1f %@", val.wrappedValue, unit))
                .frame(width:72, alignment:.trailing)
        }
    }
    private func formulaRow(_ label:String, _ formula:String) -> some View {
        HStack {
            monoLabel(label)
            Spacer()
            Text(formula).font(.system(size:8,design:.monospaced)).foregroundColor(.purple)
        }
    }
    private func card<C:View>(_ title:String, @ViewBuilder content:()->C) -> some View {
        VStack(alignment:.leading, spacing:8) {
            Text(title).font(.system(size:8,weight:.bold,design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
            content()
        }.padding(10).background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:12))
    }
    private func monoLabel(_ s:String) -> some View {
        Text(s).font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.65))
    }
    private func accentLabel(_ s:String) -> some View {
        Text(s).font(.system(size:9,design:.monospaced)).foregroundColor(themeVM.accent)
    }
}

struct QuantumSocketCalc: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var b:Double=1
    @State private var p:Double=1
    @State private var a:Double=1
    @State private var r:Double=1
    var result: Double { ArcEdgeMath.quantumSocket(b:b,p:p,a:a,r:r) }
    var body: some View {
        VStack(spacing:5) {
            Text("(b·b)·(p(a²))/r")
                .font(.system(size:10,design:.monospaced)).foregroundColor(themeVM.accent)
            ForEach([("b",$b),("p",$p),("a",$a),("r",$r)], id:\.0) { lbl,bind in
                HStack {
                    Text(lbl).font(.system(size:10,weight:.bold,design:.monospaced))
                        .foregroundColor(.white.opacity(0.5)).frame(width:14)
                    Slider(value:bind,in:0.1...10).tint(themeVM.accent)
                    Text(String(format:"%.2f",bind.wrappedValue))
                        .font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.4))
                        .frame(width:36)
                }
            }
            HStack {
                Text("Result:").font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.35))
                Spacer()
                Text(String(format:"%.6f",result))
                    .font(.system(size:11,weight:.bold,design:.monospaced)).foregroundColor(themeVM.accent)
            }
        }
    }
}
