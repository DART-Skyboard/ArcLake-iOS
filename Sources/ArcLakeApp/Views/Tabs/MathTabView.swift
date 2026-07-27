import SwiftUI

// MARK: — Algebra Menu (formerly the read-only Math tab)
// Builds Equation Nodes here; wire their curve connections in the Node
// Editor; both read/write the same labVM.equationNodes / equationConnections
// / molBonds / deltaConnections — there is no separate copy of this data
// anywhere, so changes here show up immediately in the Node Editor and the
// Molecule Canvas, and vice versa.
public struct MathTabView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var selectedElement: ArcElement? = nil
    @State private var customZ: Int = 1
    @State private var showReference = false
    @State private var newNodeRole: EquationNodeRole = .algebra
    @State private var newNodeAtomId: UUID? = nil
    @State private var newNodeElementSymbol: String? = nil

    private var element: ArcElement? {
        selectedElement ?? labVM.selectedElements.first ??
        ElementStore.shared.elements.first(where: { $0.protons == customZ })
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                buildNodeSection
                nodesListSection

                DisclosureGroup("Neutron-First Reference", isExpanded: $showReference) {
                    referenceSection
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(themeVM.accent)
                .padding(12)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(12)
        }
    }

    // MARK: — Build Equation Node
    private var buildNodeSection: some View {
        SectionCard(title: "Algebra Menu — Build Equation Node", icon: "function") {
            Text("n⁰ → p⁺ resolves state → algebra propagates outward")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeVM.accent.opacity(0.7))
                .padding(.bottom, 4)

            Text("ROLE (order-of-operations)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Picker("Role", selection: $newNodeRole) {
                ForEach(EquationNodeRole.allCases, id: \.self) { r in
                    Text(r.shortLabel).tag(r)
                }
            }
            .pickerStyle(.segmented)

            // Primary binding: elements actually in the scene (the "Active
            // Elements" list) — this is the main path, always shown, no
            // Molecule Canvas needed for it.
            Text("ELEMENT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .padding(.top, 6)
            if labVM.selectedElements.isEmpty {
                Text("No elements in the scene yet — add some from the Periodic Table first.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        elementChip(nil, "Freestanding")
                        ForEach(labVM.selectedElements, id: \.elementSymbol) { el in
                            elementChip(el.elementSymbol, el.elementSymbol)
                        }
                    }
                }
            }

            // Secondary binding: a specific placed Molecule Canvas atom
            // instance — only relevant once something's actually been put on
            // the canvas, since that's what it's for (bond/delta sync with a
            // real placed instance rather than "this element in general").
            if !labVM.molAtoms.isEmpty {
                Text("OR BIND TO A PLACED MOLECULE CANVAS ATOM")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(labVM.molAtoms) { atom in
                            atomChip(atom.id, atom.symbol)
                        }
                    }
                }
            }

            Button {
                let title = newNodeAtomId.flatMap { id in labVM.molAtoms.first(where: {$0.id==id})?.symbol }
                    ?? newNodeElementSymbol
                    ?? "Node \(labVM.equationNodes.count + 1)"
                labVM.addEquationNode(title: title, role: newNodeRole,
                                       boundAtomId: newNodeAtomId, boundElementSymbol: newNodeElementSymbol)
                // Open the Node Editor so the node just built is immediately
                // visible — it renders directly alongside everything else
                // there now, no separate mode to switch into.
                withAnimation(.spring()) { labVM.isNodeEditorVisible = true }
            } label: {
                Label("Build Equation Node", systemImage: "plus.diamond.fill")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(themeVM.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.top, 8)
        }
    }

    private func elementChip(_ symbol: String?, _ label: String) -> some View {
        Button { newNodeElementSymbol = symbol; newNodeAtomId = nil } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(newNodeElementSymbol == symbol ? .black : themeVM.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(newNodeElementSymbol == symbol ? themeVM.accent : themeVM.accent.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    private func atomChip(_ id: UUID?, _ label: String) -> some View {
        Button { newNodeAtomId = id; newNodeElementSymbol = nil } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(newNodeAtomId == id ? .black : themeVM.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(newNodeAtomId == id ? themeVM.accent : themeVM.accent.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    // MARK: — Existing nodes, editable inline
    private var nodesListSection: some View {
        Group {
            if !labVM.equationNodes.isEmpty {
                SectionCard(title: "Equation Nodes (\(labVM.equationNodes.count))", icon: "circle.grid.cross") {
                    ForEach(labVM.equationNodes) { node in
                        EquationNodeCard(node: node)
                    }
                }
            }
        }
    }

    // MARK: — Reference display (unchanged from before)
    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Atomic Number (Z):")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Stepper("\(customZ)", value: $customZ, in: 1...128)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(themeVM.accent)
            }

            if let el = element {
                Divider().background(themeVM.accent.opacity(0.2))
                mathRow("Neutrons (n⁰)", value: "\(el.neutrons)", color: .orange)
                mathRow("Protons (p⁺)",  value: "\(el.protons)",  color: .red)
                mathRow("Electrons (e⁻)", value: "\(el.electrons)", color: .cyan)
                mathRow("Orbits",         value: "\(el.orbits)",   color: .purple)
                Divider().background(themeVM.accent.opacity(0.2))

                Text("Shell Distribution:")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                let shellNames = ["K","L","M","N","O","P","Q"]
                ForEach(Array(el.electronOrbits.enumerated()), id: \.0) { idx, count in
                    HStack {
                        Text(idx < shellNames.count ? shellNames[idx] : "?")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                            .frame(width: 20)
                        ProgressView(value: Double(count), total: Double(max(el.electronOrbits.max() ?? 1, 1)))
                            .tint(themeVM.accent)
                        Text("\(count) e⁻")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 36)
                    }
                }
                Divider().background(themeVM.accent.opacity(0.2))
                mathRow("Atomic Mass", value: String(format: "%.6f u", el.atomicMass), color: .green)
                mathRow("Neutron-First Mass", value: String(format: "%.6f u", el.neutronFirstMass), color: .yellow)
                mathRow("Arc Edge C", value: String(format: "%.4f pm", el.arcEdgeCircumference), color: themeVM.accent)
            }

            Divider().background(themeVM.accent.opacity(0.2))
            formulaBlock("Core", "(xa²√xa)±1")
            formulaBlock("Arc Edge", "C = √(d × 3.0)²")
            formulaBlock("Quantum Socket", "(b·b)·(p(a²))/r")
            formulaBlock("Sigma Meridian", "φ = 1.618...")
            formulaBlock("Nucleus Blast", "F > φ × stable → blast")
        }
    }

    private func mathRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(color)
        }
        .padding(.vertical, 1)
    }

    private func formulaBlock(_ name: String, _ formula: String) -> some View {
        HStack {
            Text(name + ":").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                .frame(width: 90, alignment: .leading)
            Text(formula).font(.system(size: 10, design: .monospaced)).foregroundColor(themeVM.accent)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: — One equation node's card: role, socket list, +/- per socket kind
private struct EquationNodeCard: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    let node: EquationNode

    private var liveNode: EquationNode {
        labVM.equationNodes.first(where: { $0.id == node.id }) ?? node
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Color(uiColor: .systemCyan)).frame(width: 6, height: 6)
                Text(liveNode.title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(liveNode.role.displayName)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.7))
                Spacer()
                Button { labVM.removeEquationNode(node.id) } label: {
                    Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.red.opacity(0.6))
                }
            }

            physicsSection

            socketRow("Incoming", liveNode.incomingSockets, direction: .incoming)
            socketRow("Outgoing", liveNode.outgoingSockets, direction: .outgoing)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(EquationSocketKind.allCases, id: \.self) { kind in
                        Menu {
                            Button("+ Incoming") { labVM.addEquationSocket(to: node.id, kind: kind, direction: .incoming) }
                            Button("+ Outgoing") { labVM.addEquationSocket(to: node.id, kind: kind, direction: .outgoing) }
                        } label: {
                            Text("+ " + kind.displayName)
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(uiColor: kind.color))
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(Color(uiColor: kind.color).opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 2)
    }

    // Six-input physics (mass/volume/weight/density/temperature/velocity) —
    // looked up by matching the bound element's symbol against whatever's
    // actually placed in the scene, since equation nodes bind by symbol, not
    // a specific placed instance (see computeAlgebraModulation for the same
    // scoping note). Shows nothing if the bound element isn't placed yet.
    private var boundPhysics: ArcAtomPhysics? {
        guard let symbol = liveNode.boundElementSymbol,
              let el = labVM.selectedElements.first(where: { $0.elementSymbol == symbol }) else { return nil }
        return labVM.atomPhysics[el.id]
    }

    @ViewBuilder
    private var physicsSection: some View {
        if let p = boundPhysics {
            VStack(alignment: .leading, spacing: 2) {
                Text("PHYSICS (Earth default — adjustable)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                HStack(spacing: 10) {
                    physicsStat("mass", String(format: "%.2f u", p.massU))
                    physicsStat("vol", String(format: "%.1f Å³", p.volumeAngstrom3))
                    physicsStat("wt", String(format: "%.1e N", p.weightN))
                }
                HStack(spacing: 10) {
                    physicsStat("ρ", String(format: "%.0f kg/m³", p.densityKgM3))
                    physicsStat("T", String(format: "%.0f K", p.temperatureK))
                    physicsStat("v", String(format: "%.0f m/s", p.velocityMS))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func physicsStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 6, design: .monospaced)).foregroundColor(.white.opacity(0.3))
            Text(value).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(themeVM.accent.opacity(0.85))
        }
    }

    private func socketRow(_ label: String, _ sockets: [EquationSocket], direction: EquationSocketDirection) -> some View {
        Group {
            if !sockets.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                    ForEach(sockets) { socket in
                        HStack(spacing: 6) {
                            Circle().fill(Color(uiColor: socket.kind.color)).frame(width: 5, height: 5)
                            Text(socket.label)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            TextField("", text: Binding(
                                get: { labVM.socketDisplayValue(socket) },
                                set: { labVM.setEquationSocketValue(socket.id, onNode: node.id, to: $0) }
                            ))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(uiColor: socket.kind.color))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            Button { labVM.removeEquationSocket(socket.id, from: node.id) } label: {
                                Image(systemName: "minus.circle").font(.system(size: 9)).foregroundColor(.red.opacity(0.4))
                            }
                        }
                    }
                }
            }
        }
    }
}
