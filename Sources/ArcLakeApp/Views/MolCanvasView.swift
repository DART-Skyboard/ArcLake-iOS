
import SwiftUI

struct MolAtom: Identifiable {
    let id = UUID()
    var symbol: String
    var position: CGPoint
    var atomicNumber: Int
    var color: Color
    var label: String = ""
}

struct MolBond: Identifiable {
    let id = UUID()
    var fromId: UUID
    var toId: UUID
    var order: Int = 1  // 1=single, 2=double, 3=triple
}

public struct MolCanvasView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var atoms: [MolAtom] = []
    @State private var bonds: [MolBond] = []
    @State private var selectedAtomId: UUID? = nil
    @State private var bondingFromId: UUID? = nil
    @State private var canvasOffset = CGSize.zero
    @State private var canvasScale: CGFloat = 1.0
    @State private var showBondOrder = false

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Text("Mol Canvas")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(themeVM.accent)

                Spacer()

                // Bond mode toggle
                Button {
                    bondingFromId = nil
                    showBondOrder.toggle()
                } label: {
                    Label("Bond", systemImage: "line.diagonal")
                        .font(.caption2)
                        .foregroundColor(showBondOrder ? themeVM.accent : .white.opacity(0.5))
                }

                // Clear
                Button {
                    atoms.removeAll()
                    bonds.removeAll()
                    bondingFromId = nil
                    labVM.log("Mol canvas cleared")
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }

                // Send to 3D
                Button {
                    sendTo3D()
                } label: {
                    Image(systemName: "cube.transparent")
                        .foregroundColor(themeVM.accent)
                }

                // Close
                Button {
                    withAnimation { labVM.isMolCanvasVisible = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.7))

            // Canvas
            ZStack {
                // Background grid
                canvasGrid

                // Bonds
                ForEach(bonds) { bond in
                    if let from = atoms.first(where: { $0.id == bond.fromId }),
                       let to   = atoms.first(where: { $0.id == bond.toId }) {
                        BondLine(from: from.position, to: to.position, order: bond.order)
                    }
                }

                // Atoms
                ForEach(atoms) { atom in
                    AtomDot(atom: atom,
                            isSelected: selectedAtomId == atom.id,
                            isBondTarget: bondingFromId != nil && bondingFromId != atom.id)
                        .position(atom.position)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    moveAtom(id: atom.id, to: val.location)
                                }
                        )
                        .onTapGesture {
                            handleAtomTap(atom)
                        }
                }

                // Bonding line preview
                if let fromId = bondingFromId,
                   let from = atoms.first(where: { $0.id == fromId }) {
                    Text("Tap another atom to bond")
                        .font(.caption2)
                        .foregroundColor(themeVM.accent.opacity(0.8))
                        .position(x: from.position.x, y: from.position.y - 30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.02, green: 0.05, blue: 0.1))
            .clipShape(Rectangle())
            // Drop target — receive elements dragged from periodic table
            .onDrop(of: [.plainText], isTargeted: nil) { providers, location in
                providers.first?.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let symbol = obj as? String else { return }
                    Task { @MainActor in
                        addAtom(symbol: symbol, at: location)
                        labVM.log("Dropped \(symbol) onto mol canvas")
                    }
                }
                return true
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeVM.accent.opacity(0.3), lineWidth: 0.5)
        )
        .frame(maxWidth: 500, maxHeight: 500)
        .padding()
        .shadow(color: themeVM.accent.opacity(0.15), radius: 20)
    }

    private var canvasGrid: some View {
        Canvas { context, size in
            let spacing: CGFloat = 30
            context.stroke(
                Path { path in
                    var x: CGFloat = 0
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += spacing
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += spacing
                    }
                },
                with: .color(.white.opacity(0.05)),
                lineWidth: 0.5
            )
        }
    }

    private func addAtom(symbol: String, at position: CGPoint) {
        let element = ElementStore.shared.elements.first { $0.elementSymbol == symbol }
        let color = element.map { Color($0.category.color) } ?? Color.cyan
        let atom = MolAtom(symbol: symbol, position: position,
                           atomicNumber: element?.protons ?? 0, color: color)
        atoms.append(atom)
    }

    private func moveAtom(id: UUID, to position: CGPoint) {
        if let idx = atoms.firstIndex(where: { $0.id == id }) {
            atoms[idx].position = position
        }
    }

    private func handleAtomTap(_ atom: MolAtom) {
        if let fromId = bondingFromId {
            // Create bond
            if fromId != atom.id {
                bonds.append(MolBond(fromId: fromId, toId: atom.id))
                labVM.log("Bonded \(atoms.first(where:{$0.id==fromId})?.symbol ?? "?") — \(atom.symbol)")
            }
            bondingFromId = nil
        } else if showBondOrder {
            bondingFromId = atom.id
        } else {
            selectedAtomId = selectedAtomId == atom.id ? nil : atom.id
        }
    }

    private func sendTo3D() {
        // Add all mol canvas atoms to 3D scene
        for atom in atoms {
            if let element = ElementStore.shared.elements.first(where: { $0.elementSymbol == atom.symbol }) {
                labVM.addElement(element)
            }
        }
        labVM.isMolCanvasVisible = false
        labVM.log("Sent \(atoms.count) atoms to 3D scene")
    }
}

struct BondLine: View {
    let from: CGPoint
    let to: CGPoint
    let order: Int

    var body: some View {
        Canvas { ctx, _ in
            let path = Path { p in
                p.move(to: from)
                p.addLine(to: to)
            }
            ctx.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: CGFloat(order))
            if order > 1 {
                // Offset second line
                let dx = to.y - from.y
                let dy = from.x - to.x
                let len = sqrt(dx*dx + dy*dy)
                guard len > 0 else { return }
                let offset: CGFloat = 3
                let path2 = Path { p in
                    p.move(to: CGPoint(x: from.x + dx/len*offset, y: from.y + dy/len*offset))
                    p.addLine(to: CGPoint(x: to.x + dx/len*offset, y: to.y + dy/len*offset))
                }
                ctx.stroke(path2, with: .color(.white.opacity(0.6)), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

struct AtomDot: View {
    let atom: MolAtom
    let isSelected: Bool
    let isBondTarget: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(atom.color.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.yellow :
                            isBondTarget ? Color.green :
                            atom.color,
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            Text(atom.symbol)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .shadow(color: atom.color.opacity(isSelected ? 0.6 : 0.2), radius: 6)
    }
}
