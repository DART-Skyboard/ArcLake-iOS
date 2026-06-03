
import SwiftUI

public struct MolCanvasView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var canvasOffset = CGSize.zero
    @State private var canvasScale: CGFloat = 1.0
    @State private var showBondTool = false
    @State private var showDeltaTool = false
    @State private var showAddToScenePrompt = false
    @State private var dragStartOffset = CGSize.zero
    @State private var selectedForBond: UUID? = nil

    public var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ─────────────────────────────────────────────
            HStack(spacing: 6) {
                Text("Mol Canvas")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.accent)

                Spacer()

                // Bond order buttons
                ForEach([1,2,3], id: \.self) { order in
                    Button {
                        labVM.molBondMode = order
                        labVM.molDeltaMode = false
                    } label: {
                        Text(["—","═","≡"][order-1])
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(labVM.molBondMode == order && !labVM.molDeltaMode ?
                                themeVM.accent : .white.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(labVM.molBondMode == order && !labVM.molDeltaMode ?
                                themeVM.accent.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                // Delta connection
                Button {
                    labVM.molDeltaMode.toggle()
                    if labVM.molDeltaMode { showDeltaTool = true }
                } label: {
                    Text("Δ")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(labVM.molDeltaMode ? .purple : .white.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(labVM.molDeltaMode ? Color.purple.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Label tool
                Button {
                    labVM.molLabelMode.toggle()
                } label: {
                    Image(systemName: "textformat")
                        .font(.system(size: 12))
                        .foregroundColor(labVM.molLabelMode ? themeVM.accent : .white.opacity(0.4))
                        .frame(width: 28, height: 28)
                }

                // Clear
                Button {
                    labVM.clearMolCanvas()
                } label: {
                    Image(systemName: "trash").font(.caption)
                        .foregroundColor(.red.opacity(0.7)).frame(width: 28, height: 28)
                }

                // Add to scene
                Button {
                    showAddToScenePrompt = true
                } label: {
                    Label("→ Scene", systemImage: "cube.fill")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(themeVM.accent.opacity(0.12))
                        .clipShape(Capsule())
                }

                Button {
                    labVM.isMolCanvasVisible = false
                } label: {
                    Image(systemName: "xmark").font(.caption2)
                        .foregroundColor(.white.opacity(0.4)).frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.black.opacity(0.4))

            // ── Canvas area ──────────────────────────────────────────
            GeometryReader { geo in
                ZStack {
                    // Grid background
                    Canvas { ctx, size in
                        let step: CGFloat = 30
                        var x: CGFloat = 0
                        while x < size.width {
                            ctx.stroke(Path { p in
                                p.move(to: CGPoint(x:x, y:0))
                                p.addLine(to: CGPoint(x:x, y:size.height))
                            }, with: .color(.cyan.opacity(0.06)), lineWidth: 0.5)
                            x += step
                        }
                        var y: CGFloat = 0
                        while y < size.height {
                            ctx.stroke(Path { p in
                                p.move(to: CGPoint(x:0, y:y))
                                p.addLine(to: CGPoint(x:size.width, y:y))
                            }, with: .color(.cyan.opacity(0.06)), lineWidth: 0.5)
                            y += step
                        }
                    }

                    // Bonds
                    Canvas { ctx, _ in
                        for bond in labVM.molBonds {
                            guard let fromNode = labVM.molAtoms.first(where: { $0.id == bond.fromId }),
                                  let toNode   = labVM.molAtoms.first(where: { $0.id == bond.toId })
                            else { continue }

                            let from = CGPoint(
                                x: fromNode.position.x + canvasOffset.width,
                                y: fromNode.position.y + canvasOffset.height)
                            let to = CGPoint(
                                x: toNode.position.x + canvasOffset.width,
                                y: toNode.position.y + canvasOffset.height)

                            let color: Color = bond.isDelta ? .purple : .cyan
                            let width: CGFloat = [1:1.5, 2:3.0, 3:4.5][bond.order] ?? 1.5

                            // Draw bond lines (offset for double/triple)
                            for i in 0..<bond.order {
                                let offset = CGFloat(i - bond.order/2) * 4.0
                                let dx = to.y - from.y; let dy = from.x - to.x
                                let len = sqrt(dx*dx + dy*dy)
                                let nx = len > 0 ? dx/len : 0; let ny = len > 0 ? dy/len : 0
                                ctx.stroke(Path { p in
                                    p.move(to: CGPoint(x: from.x + nx*offset, y: from.y + ny*offset))
                                    p.addLine(to: CGPoint(x: to.x + nx*offset, y: to.y + ny*offset))
                                }, with: .color(color.opacity(0.8)), lineWidth: width/CGFloat(bond.order))
                            }

                            // Bond order label
                            let mid = CGPoint(x:(from.x+to.x)/2, y:(from.y+to.y)/2 - 10)
                            if bond.order > 1 {
                                ctx.draw(Text("\(bond.order)").font(.system(size:8)).foregroundColor(color),
                                         at: mid)
                            }
                            if bond.isDelta {
                                ctx.draw(Text("Δ").font(.system(size:9)).foregroundColor(.purple),
                                         at: CGPoint(x:mid.x+10, y:mid.y))
                            }
                        }
                    }

                    // Atom nodes
                    ForEach($labVM.molAtoms) { $atom in
                        MolAtomNodeView(atom: $atom,
                            isSelected: labVM.selectedMolAtomId == atom.id,
                            isLabelMode: labVM.molLabelMode,
                            accent: themeVM.accent,
                            onTap: { handleAtomTap(atom) },
                            onDragChanged: { val in
                                atom.position = CGPoint(
                                    x: atom.position.x + val.translation.width - (val.predictedEndTranslation.width - val.translation.width) * 0,
                                    y: atom.position.y + val.translation.height)
                            })
                        .offset(canvasOffset)
                    }
                }
                // 2-finger pan
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { val in
                            if val.startLocation != val.location {
                                canvasOffset = CGSize(
                                    width: dragStartOffset.width + val.translation.width,
                                    height: dragStartOffset.height + val.translation.height)
                            }
                        }
                        .onEnded { _ in dragStartOffset = canvasOffset }
                        .simultaneously(with: MagnificationGesture()
                            .onChanged { canvasScale = max(0.3, min(3.0, $0)) })
                )
                // Receive pending atom from probe
                .onAppear {
                    if let pending = labVM.pendingMolAtom {
                        let pos = CGPoint(
                            x: geo.size.width / 2 + Double(labVM.molAtoms.count % 3) * 70,
                            y: geo.size.height / 2 + Double(labVM.molAtoms.count / 3) * 60)
                        labVM.molAtoms.append(MolAtomNode(
                            symbol: pending.symbol, z: pending.z,
                            color: pending.color, at: pos))
                        labVM.pendingMolAtom = nil
                    }
                }
            }

            // ── Status bar ────────────────────────────────────────────
            HStack(spacing: 12) {
                Label("\(labVM.molAtoms.count) atoms", systemImage: "atom")
                Label("\(labVM.molBonds.count) bonds", systemImage: "link")
                if !labVM.deltaConnections.isEmpty {
                    Label("\(labVM.deltaConnections.count) Δ", systemImage: "function")
                        .foregroundColor(.purple)
                }
                Spacer()
                Text(labVM.molDeltaMode ? "Δ MODE" : "BOND \(labVM.molBondMode)×")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(labVM.molDeltaMode ? .purple : themeVM.accent)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.black.opacity(0.3))
        }
        .background(Color(red:0.02, green:0.04, blue:0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(themeVM.accent.opacity(0.25), lineWidth: 0.5))
        // Delta tool sheet
        .sheet(isPresented: $showDeltaTool) {
            DeltaConnectionSheet()
        }
        // Add to scene prompt
        .confirmationDialog("Add to Scene", isPresented: $showAddToScenePrompt, titleVisibility: .visible) {
            Button("Add to Current Scene") { labVM.addMolCanvasToScene(newTab: false) }
            Button("Add to New Scene Tab") { labVM.addMolCanvasToScene(newTab: true) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func handleAtomTap(_ atom: MolAtomNode) {
        let vm = labVM  // capture before closure
        if vm.molDeltaMode {
            // Delta mode — first tap selects from, second tap creates connection
            if let fromId = selectedForBond {
                if fromId != atom.id {
                    vm.addBond(from: fromId, to: atom.id)  // adds as delta bond
                    showDeltaTool = true
                }
                selectedForBond = nil
            } else {
                selectedForBond = atom.id
            }
            vm.selectedMolAtomId = atom.id
        } else if vm.molLabelMode {
            labVM.selectedMolAtomId = atom.id
        } else {
            // Bond mode — connect atoms
            if let fromId = selectedForBond {
                if fromId != atom.id {
                    vm.addMolBond(from: fromId, to: atom.id)
                }
                selectedForBond = nil
                vm.selectedMolAtomId = nil
            } else {
                selectedForBond = atom.id
                vm.selectedMolAtomId = atom.id
            }
        }
    }
}

extension ArcLabViewModel {
    func addBond(from: UUID, to: UUID) {
        molBonds.removeAll { ($0.fromId==from && $0.toId==to)||($0.fromId==to && $0.toId==from) }
        molBonds.append(MolBond(from: from, to: to, order: molBondMode, isDelta: true))
    }
    var pendingMolAtom: (symbol: String, z: Int, color: UIColor)? {
        get { MolCanvasState.shared.pendingAtom }
        set { MolCanvasState.shared.pendingAtom = newValue }
    }
}

// MARK: — Individual mol atom node view
struct MolAtomNodeView: View {
    @Binding var atom: MolAtomNode
    let isSelected: Bool
    let isLabelMode: Bool
    let accent: Color
    let onTap: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    @State private var isEditing = false
    @State private var labelText = ""

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(atom.color).opacity(0.25))
                .overlay(Circle().stroke(
                    isSelected ? accent : Color(atom.color).opacity(0.8),
                    lineWidth: isSelected ? 2 : 1))
                .frame(width: 36, height: 36)
            Text(atom.symbol)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .overlay(alignment: .bottom) {
            if atom.label != atom.symbol {
                Text(atom.label)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(accent)
                    .offset(y: 20)
            }
        }
        .position(atom.position)
        .onTapGesture {
            if isLabelMode {
                isEditing = true
                labelText = atom.label
            } else {
                onTap()
            }
        }
        .gesture(DragGesture().onChanged { val in
            atom.position = CGPoint(x: atom.position.x + val.translation.width,
                                    y: atom.position.y + val.translation.height)
        })
        .sheet(isPresented: $isEditing) {
            NavigationView {
                Form {
                    Section("Atom Label") {
                        TextField("Label", text: $labelText)
                    }
                }
                .navigationTitle("Edit Label")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { atom.label = labelText; isEditing = false }
                    }
                }
            }
            .presentationDetents([.height(200)])
        }
    }
}

// MARK: — Delta connection sheet
struct DeltaConnectionSheet: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var fromShell = 0
    @State private var toShell = 0
    @State private var op = "+"
    @State private var fromAtomIdx = 0
    @State private var toAtomIdx = 1

    var body: some View {
        NavigationView {
            Form {
                Section("Atoms") {
                    if labVM.molAtoms.count >= 2 {
                        Picker("From Atom", selection: $fromAtomIdx) {
                            ForEach(labVM.molAtoms.indices, id: \.self) { i in
                                Text(labVM.molAtoms[i].symbol).tag(i)
                            }
                        }
                        Picker("To Atom", selection: $toAtomIdx) {
                            ForEach(labVM.molAtoms.indices, id: \.self) { i in
                                Text(labVM.molAtoms[i].symbol).tag(i)
                            }
                        }
                    } else {
                        Text("Add at least 2 atoms to create a Δ connection")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Section("Shell Connection") {
                    Picker("From Shell", selection: $fromShell) {
                        ForEach(0..<7) { Text("Shell \($0+1) (\(["K","L","M","N","O","P","Q"][$0]))").tag($0) }
                    }
                    Picker("To Shell", selection: $toShell) {
                        ForEach(0..<7) { Text("Shell \($0+1) (\(["K","L","M","N","O","P","Q"][$0]))").tag($0) }
                    }
                    Picker("Operator", selection: $op) {
                        ForEach(["+","-","×","÷","√","²"], id:\.self) { Text($0).tag($0) }
                    }
                }
                Section("Preview") {
                    if labVM.molAtoms.count >= 2 {
                        Text("Δ(\(labVM.molAtoms[safe: fromAtomIdx]?.symbol ?? "?") shell \(fromShell+1)) \(op) Δ(\(labVM.molAtoms[safe: toAtomIdx]?.symbol ?? "?") shell \(toShell+1))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                }
            }
            .navigationTitle("Δ Algebra Connection")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if labVM.molAtoms.count >= 2 {
                            let lvm = labVM
                            lvm.addDeltaConnection(
                                from: labVM.molAtoms[fromAtomIdx].id,
                                to: labVM.molAtoms[toAtomIdx].id,
                                fromShell: fromShell, toShell: toShell, op: op)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
