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

            if !labVM.molAtoms.isEmpty {
                Text("BIND TO ATOM (optional)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        atomChip(nil, "Freestanding")
                        ForEach(labVM.molAtoms) { atom in
                            atomChip(atom.id, atom.symbol)
                        }
                    }
                }
            }

            Button {
                let title = newNodeAtomId.flatMap { id in labVM.molAtoms.first(where: {$0.id==id})?.symbol }
                    ?? "Node \(labVM.equationNodes.count + 1)"
                labVM.addEquationNode(title: title, role: newNodeRole, boundAtomId: newNodeAtomId)
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

    private func atomChip(_ id: UUID?, _ label: String) -> some View {
        Button { newNodeAtomId = id } label: {
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
