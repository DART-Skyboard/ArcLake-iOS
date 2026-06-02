
import SwiftUI

struct MolAtom: Identifiable {
    let id = UUID()
    var symbol: String
    var position: CGPoint
    var atomicNumber: Int
    var color: Color
}

struct MolBond: Identifiable {
    let id = UUID()
    var fromId: UUID
    var toId: UUID
    var order: Int = 1
}

public struct MolCanvasView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var atoms: [MolAtom] = []
    @State private var bonds: [MolBond] = []
    @State private var selectedAtomId: UUID? = nil
    @State private var bondingFromId: UUID? = nil
    @State private var bondMode = false

    // Pan + zoom state
    @State private var canvasOffset: CGSize = .zero
    @State private var lastOffset:   CGSize = .zero
    @State private var canvasScale:  CGFloat = 1.0
    @State private var lastScale:    CGFloat = 1.0

    public var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ──
            HStack(spacing: 10) {
                Text("Mol Canvas")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(themeVM.accent)

                Spacer()

                Button {
                    bondMode.toggle()
                    bondingFromId = nil
                } label: {
                    Label("Bond", systemImage: "line.diagonal")
                        .font(.caption2)
                        .foregroundColor(bondMode ? themeVM.accent : .white.opacity(0.4))
                }

                Button {
                    canvasOffset = .zero
                    canvasScale  = 1.0
                } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.caption)
                }

                Button {
                    atoms.removeAll(); bonds.removeAll(); bondingFromId = nil
                    labVM.log("Mol canvas cleared")
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }

                Button {
                    for atom in atoms {
                        if let el = ElementStore.shared.elements.first(where: { $0.elementSymbol == atom.symbol }) {
                            labVM.addElement(el)
                        }
                    }
                    labVM.isMolCanvasVisible = false
                    labVM.log("Sent \(atoms.count) atoms to 3D")
                } label: {
                    Image(systemName: "cube.transparent")
                        .foregroundColor(themeVM.accent)
                }

                Button {
                    withAnimation { labVM.isMolCanvasVisible = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.8))

            // ── Canvas ──
            GeometryReader { geo in
                ZStack {
                    // Background grid (fixed, not transformed)
                    canvasGridBackground(size: geo.size)

                    // Transformed content
                    ZStack {
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
                                    isSelected:   selectedAtomId == atom.id,
                                    isBondTarget: bondMode && bondingFromId != nil && bondingFromId != atom.id)
                                .position(atom.position)
                                .gesture(
                                    DragGesture()
                                        .onChanged { val in
                                            if !bondMode {
                                                moveAtom(id: atom.id, to: val.location)
                                            }
                                        }
                                )
                                .onTapGesture { handleAtomTap(atom) }
                        }

                        // Bonding hint
                        if bondMode, let fid = bondingFromId,
                           let from = atoms.first(where: { $0.id == fid }) {
                            Text("Tap atom to bond →")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(themeVM.accent)
                                .position(x: from.position.x,
                                          y: from.position.y - 28)
                        }
                    }
                    .scaleEffect(canvasScale)
                    .offset(canvasOffset)
                }
                // Pan gesture (2 fingers or when not dragging atom)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { val in
                            if !bondMode {
                                canvasOffset = CGSize(
                                    width:  lastOffset.width  + val.translation.width,
                                    height: lastOffset.height + val.translation.height)
                            }
                        }
                        .onEnded { _ in lastOffset = canvasOffset }
                )
                // Pinch zoom
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in
                            canvasScale = max(0.4, min(4.0, lastScale * val))
                        }
                        .onEnded { _ in lastScale = canvasScale }
                )
                // Drop from periodic table
                .onDrop(of: [.plainText], isTargeted: nil) { providers, location in
                    providers.first?.loadObject(ofClass: NSString.self) { obj, _ in
                        guard let symbol = obj as? String else { return }
                        // Convert drop location accounting for pan/zoom
                        let adjusted = CGPoint(
                            x: (location.x - geo.size.width/2  - canvasOffset.width)  / canvasScale + geo.size.width/2,
                            y: (location.y - geo.size.height/2 - canvasOffset.height) / canvasScale + geo.size.height/2
                        )
                        Task { @MainActor in
                            addAtom(symbol: symbol, at: adjusted)
                            labVM.log("Dropped \(symbol) onto mol canvas")
                        }
                    }
                    return true
                }
            }
            .background(Color(red:0.01, green:0.04, blue:0.08))
            .clipShape(RoundedRectangle(cornerRadius: 0))
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(themeVM.accent.opacity(0.3), lineWidth: 0.5))
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .shadow(color: themeVM.accent.opacity(0.15), radius: 16)
    }

    private func canvasGridBackground(size: CGSize) -> some View {
        Canvas { ctx, sz in
            let spacing: CGFloat = 32
            let color = Color.cyan.opacity(0.05)
            for x in stride(from: 0.0, through: sz.width, by: spacing) {
                ctx.stroke(Path { p in p.move(to: CGPoint(x:x,y:0)); p.addLine(to: CGPoint(x:x,y:sz.height)) },
                           with: .color(color), lineWidth: 0.5)
            }
            for y in stride(from: 0.0, through: sz.height, by: spacing) {
                ctx.stroke(Path { p in p.move(to: CGPoint(x:0,y:y)); p.addLine(to: CGPoint(x:sz.width,y:y)) },
                           with: .color(color), lineWidth: 0.5)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func addAtom(symbol: String, at position: CGPoint) {
        let el = ElementStore.shared.elements.first { $0.elementSymbol == symbol }
        let color = el.map { Color($0.category.color) } ?? Color.cyan
        atoms.append(MolAtom(symbol: symbol, position: position,
                             atomicNumber: el?.protons ?? 0, color: color))
    }

    private func moveAtom(id: UUID, to position: CGPoint) {
        if let idx = atoms.firstIndex(where: { $0.id == id }) {
            atoms[idx].position = position
        }
    }

    private func handleAtomTap(_ atom: MolAtom) {
        if let fid = bondingFromId {
            if fid != atom.id {
                bonds.append(MolBond(fromId: fid, toId: atom.id))
                let fromSym = atoms.first(where: {$0.id == fid})?.symbol ?? "?"
                labVM.log("Bonded \(fromSym)–\(atom.symbol)")
            }
            bondingFromId = nil
        } else if bondMode {
            bondingFromId = atom.id
        } else {
            selectedAtomId = selectedAtomId == atom.id ? nil : atom.id
        }
    }
}

struct BondLine: View {
    let from: CGPoint
    let to:   CGPoint
    let order: Int
    var body: some View {
        Canvas { ctx, _ in
            let path = Path { p in p.move(to: from); p.addLine(to: to) }
            ctx.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: CGFloat(order))
        }
        .allowsHitTesting(false)
    }
}

struct AtomDot: View {
    let atom:         MolAtom
    let isSelected:   Bool
    let isBondTarget: Bool
    var body: some View {
        ZStack {
            Circle()
                .fill(atom.color.opacity(0.25))
                .frame(width: 38, height: 38)
                .overlay(Circle().stroke(
                    isSelected ? Color.yellow : isBondTarget ? Color.green : atom.color,
                    lineWidth: isSelected ? 2 : 1))
            Text(atom.symbol)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .shadow(color: atom.color.opacity(isSelected ? 0.6 : 0.2), radius: 6)
    }
}

private extension ArcElement.ElementCategory {
    var color: UIColor {
        switch self {
        case .alkaliMetal:     return UIColor(red:1.0,  green:0.4,  blue:0.4,  alpha:1)
        case .alkalineEarth:   return UIColor(red:1.0,  green:0.7,  blue:0.3,  alpha:1)
        case .transitionMetal: return UIColor(red:0.35, green:0.65, blue:1.0,  alpha:1)
        case .postTransition:  return UIColor(red:0.4,  green:0.85, blue:0.6,  alpha:1)
        case .metalloid:       return UIColor(red:0.65, green:0.85, blue:0.35, alpha:1)
        case .nonmetal:        return UIColor(red:0.25, green:0.85, blue:0.85, alpha:1)
        case .halogen:         return UIColor(red:0.85, green:0.55, blue:0.85, alpha:1)
        case .nobleGas:        return UIColor(red:0.55, green:0.35, blue:1.0,  alpha:1)
        case .lanthanide:      return UIColor(red:1.0,  green:0.45, blue:0.65, alpha:1)
        case .actinide:        return UIColor(red:0.75, green:0.25, blue:0.5,  alpha:1)
        case .superactinide:   return UIColor(red:0.5,  green:0.15, blue:0.75, alpha:1)
        case .unknown:         return UIColor(red:0.45, green:0.45, blue:0.45, alpha:1)
        }
    }
}
