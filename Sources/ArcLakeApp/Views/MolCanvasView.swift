
import SwiftUI

// MARK: — Mol Canvas View
public struct MolCanvasView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var canvasOffset = CGSize.zero
    @State private var dragStartOffset = CGSize.zero
    @State private var showDeltaTool = false
    @State private var showAddToScenePrompt = false
    @State private var selectedForBond: UUID? = nil

    public var body: some View {
        VStack(spacing: 0) {
            MolToolbar(showDeltaTool: $showDeltaTool,
                       showAddToScenePrompt: $showAddToScenePrompt)
            MolCanvas(canvasOffset: $canvasOffset,
                      dragStartOffset: $dragStartOffset,
                      selectedForBond: $selectedForBond)
            MolStatusBar()
        }
        .background(Color(red:0.02, green:0.04, blue:0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(themeVM.accent.opacity(0.25), lineWidth: 0.5))
        .sheet(isPresented: $showDeltaTool) { DeltaConnectionSheet() }
        .confirmationDialog("Add to Scene", isPresented: $showAddToScenePrompt,
                            titleVisibility: .visible) {
            Button("Add to Current Scene") { labVM.addMolCanvasToScene(newTab: false) }
            Button("Add to New Scene Tab")  { labVM.addMolCanvasToScene(newTab: true) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: — Toolbar
private struct MolToolbar: View {
    @Binding var showDeltaTool: Bool
    @Binding var showAddToScenePrompt: Bool
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Mol Canvas")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.accent)
            Spacer()
            MolBondButtons()
            deltaButton
            labelButton
            clearButton
            addToSceneButton
            closeButton
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
    }

    private var deltaButton: some View {
        Button {
            labVM.molDeltaMode.toggle()
            if labVM.molDeltaMode { showDeltaTool = true }
        } label: {
            Text("Δ").font(.system(size: 14, weight: .bold))
                .foregroundColor(labVM.molDeltaMode ? .purple : .white.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(labVM.molDeltaMode ? Color.purple.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var labelButton: some View {
        Button { labVM.molLabelMode.toggle() } label: {
            Image(systemName: "textformat").font(.system(size: 12))
                .foregroundColor(labVM.molLabelMode ? themeVM.accent : .white.opacity(0.4))
                .frame(width: 28, height: 28)
        }
    }

    private var clearButton: some View {
        Button { labVM.clearMolCanvas() } label: {
            Image(systemName: "trash").font(.caption)
                .foregroundColor(.red.opacity(0.7)).frame(width: 28, height: 28)
        }
    }

    private var addToSceneButton: some View {
        Button { showAddToScenePrompt = true } label: {
            Label("→ Scene", systemImage: "cube.fill")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeVM.accent)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(themeVM.accent.opacity(0.12)).clipShape(Capsule())
        }
    }

    private var closeButton: some View {
        Button { labVM.isMolCanvasVisible = false } label: {
            Image(systemName: "xmark").font(.caption2)
                .foregroundColor(.white.opacity(0.4)).frame(width: 24, height: 24)
        }
    }
}

// MARK: — Bond Order Buttons
private struct MolBondButtons: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    private let labels = ["—", "═", "≡"]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { i in
                Button {
                    labVM.molBondMode = i + 1
                    labVM.molDeltaMode = false
                } label: {
                    Text(labels[i]).font(.system(size: 14, weight: .bold))
                        .foregroundColor(labVM.molBondMode == i+1 && !labVM.molDeltaMode ?
                            themeVM.accent : .white.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(labVM.molBondMode == i+1 && !labVM.molDeltaMode ?
                            themeVM.accent.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}

// MARK: — Canvas
private struct MolCanvas: View {
    @Binding var canvasOffset: CGSize
    @Binding var dragStartOffset: CGSize
    @Binding var selectedForBond: UUID?
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                molGrid
                MolBondsCanvas(canvasOffset: canvasOffset)
                atomNodes(geoSize: geo.size)
            }
            .gesture(panGesture)
            .onAppear { receivePendingAtom(geo: geo) }
        }
    }

    private var molGrid: some View {
        Canvas { ctx, size in
            let step: CGFloat = 30
            var x: CGFloat = 0
            while x < size.width {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x:x, y:0)); p.addLine(to: CGPoint(x:x, y:size.height))
                }, with: .color(.cyan.opacity(0.06)), lineWidth: 0.5)
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x:0, y:y)); p.addLine(to: CGPoint(x:size.width, y:y))
                }, with: .color(.cyan.opacity(0.06)), lineWidth: 0.5)
                y += step
            }
        }
    }

    private func atomNodes(geoSize: CGSize) -> some View {
        ForEach($labVM.molAtoms) { $atom in
            MolAtomNodeView(
                atom: $atom,
                isSelected: labVM.selectedMolAtomId == atom.id,
                isLabelMode: labVM.molLabelMode,
                accent: themeVM.accent,
                onTap: { handleTap($0) })
            .offset(canvasOffset)
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { val in
                canvasOffset = CGSize(
                    width: dragStartOffset.width + val.translation.width,
                    height: dragStartOffset.height + val.translation.height)
            }
            .onEnded { _ in dragStartOffset = canvasOffset }
    }

    private func receivePendingAtom(geo: GeometryProxy) {
        if let pending = MolCanvasState.shared.pendingAtom {
            let pos = CGPoint(
                x: geo.size.width/2 + Double(labVM.molAtoms.count % 3) * 70,
                y: geo.size.height/2 + Double(labVM.molAtoms.count / 3) * 60)
            labVM.molAtoms.append(MolAtomNode(
                symbol: pending.symbol, z: pending.z,
                color: pending.color, at: pos))
            MolCanvasState.shared.pendingAtom = nil
        }
    }

    private func handleTap(_ atom: MolAtomNode) {
        if labVM.molDeltaMode || labVM.molLabelMode {
            labVM.selectedMolAtomId = atom.id
        } else {
            if let fromId = selectedForBond, fromId != atom.id {
                labVM.addMolBond(from: fromId, to: atom.id)
                selectedForBond = nil
                labVM.selectedMolAtomId = nil
            } else {
                selectedForBond = atom.id
                labVM.selectedMolAtomId = atom.id
            }
        }
    }
}

// MARK: — Bonds canvas layer
private struct MolBondsCanvas: View {
    let canvasOffset: CGSize
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        Canvas { ctx, _ in
            for bond in labVM.molBonds {
                guard let fn = labVM.molAtoms.first(where:{$0.id==bond.fromId}),
                      let tn = labVM.molAtoms.first(where:{$0.id==bond.toId}) else { continue }
                let f = CGPoint(x: fn.position.x+canvasOffset.width,
                                y: fn.position.y+canvasOffset.height)
                let t = CGPoint(x: tn.position.x+canvasOffset.width,
                                y: tn.position.y+canvasOffset.height)
                let c: Color = bond.isDelta ? .purple : .cyan
                let w: CGFloat = [1:1.5, 2:3.0, 3:4.5][bond.order] ?? 1.5
                for i in 0..<bond.order {
                    let off = CGFloat(i - bond.order/2) * 4.0
                    let dx = t.y-f.y; let dy = f.x-t.x
                    let len = sqrt(dx*dx+dy*dy)
                    let nx = len>0 ? dx/len : 0; let ny = len>0 ? dy/len : 0
                    ctx.stroke(Path { p in
                        p.move(to:CGPoint(x:f.x+nx*off,y:f.y+ny*off))
                        p.addLine(to:CGPoint(x:t.x+nx*off,y:t.y+ny*off))
                    }, with:.color(c.opacity(0.8)), lineWidth:w/CGFloat(bond.order))
                }
            }
        }
    }
}

// MARK: — Status bar
private struct MolStatusBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
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
}

// MARK: — Mol Atom Node View
struct MolAtomNodeView: View {
    @Binding var atom: MolAtomNode
    let isSelected: Bool
    let isLabelMode: Bool
    let accent: Color
    let onTap: (MolAtomNode) -> Void
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
        .position(atom.position)
        .onTapGesture {
            if isLabelMode { isEditing = true; labelText = atom.label }
            else { onTap(atom) }
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { val in
                    // Use startLocation + translation — no accumulation, tracks finger exactly
                    atom.position = CGPoint(
                        x: val.startLocation.x + val.translation.width,
                        y: val.startLocation.y + val.translation.height
                    )
                }
        )
        .sheet(isPresented: $isEditing) {
            NavigationView {
                Form {
                    Section("Atom Label") { TextField("Label", text: $labelText) }
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

// MARK: — Delta Connection Sheet
struct DeltaConnectionSheet: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var fromShell = 0
    @State private var toShell = 0
    @State private var op = "+"
    @State private var fromIdx = 0
    @State private var toIdx = 1

    var body: some View {
        NavigationView {
            Form {
                Section("Atoms") {
                    if labVM.molAtoms.count >= 2 {
                        Picker("From", selection: $fromIdx) {
                            ForEach(labVM.molAtoms.indices, id:\.self) { i in
                                Text(labVM.molAtoms[i].symbol).tag(i)
                            }
                        }
                        Picker("To", selection: $toIdx) {
                            ForEach(labVM.molAtoms.indices, id:\.self) { i in
                                Text(labVM.molAtoms[i].symbol).tag(i)
                            }
                        }
                    } else {
                        Text("Add at least 2 atoms").font(.caption).foregroundColor(.secondary)
                    }
                }
                Section("Shell") {
                    let names = ["K","L","M","N","O","P","Q"]
                    Picker("From Shell", selection: $fromShell) {
                        ForEach(0..<7) { Text("Shell \($0+1) (\(names[$0]))").tag($0) }
                    }
                    Picker("To Shell", selection: $toShell) {
                        ForEach(0..<7) { Text("Shell \($0+1) (\(names[$0]))").tag($0) }
                    }
                    Picker("Op", selection: $op) {
                        ForEach(["+","-","×","÷","√","²"], id:\.self) { Text($0).tag($0) }
                    }
                }
            }
            .navigationTitle("Δ Algebra")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if labVM.molAtoms.count >= 2 {
                            let f = labVM.molAtoms[fromIdx].id
                            let t = labVM.molAtoms[toIdx].id
                            labVM.addDeltaConnection(from:f, to:t,
                                fromShell:fromShell, toShell:toShell, op:op)
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
