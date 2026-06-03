
import SwiftUI

public struct PeriodicTableView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var searchText = ""
    @State private var selectedCategory: ArcElement.ElementCategory? = nil

    // Standard PT grid: 18 columns × 10 periods (+ lanthanide/actinide rows)
    // Each cell is (period, group) — 0 means empty spacer
    private static let COLS = 18
    // Build a 10×18 grid — row 0 = period 1 ... row 9 = period 10
    // Lanthanides in row 7 (period 8), Actinides in row 8 (period 9)
    private static let gridMap: [[Int]] = {
        // map [period][group] → atomicNumber
        var m = Array(repeating: Array(repeating: 0, count: 19), count: 11)
        for entry in periodicTableLayout {
            if entry.period <= 10 && entry.group <= 18 {
                m[entry.period][entry.group] = entry.z
            }
        }
        // Return rows 1-10, cols 1-18
        return (1...10).map { p in (1...18).map { g in m[p][g] } }
    }()

    private var elementMap: [Int: ArcElement] {
        Dictionary(uniqueKeysWithValues: ElementStore.shared.elements.map { ($0.id, $0) })
    }

    private func matchesFilter(_ el: ArcElement) -> Bool {
        let matchSearch = searchText.isEmpty ||
            el.elementName.localizedCaseInsensitiveContains(searchText) ||
            el.elementSymbol.localizedCaseInsensitiveContains(searchText) ||
            "\(el.protons)".contains(searchText)
        let matchCat = selectedCategory == nil || el.category == selectedCategory
        return matchSearch && matchCat
    }

    

    public var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ── Header — always visible, close button always reachable ──
                HStack {
                    Image(systemName: "tablecells")
                        .foregroundColor(themeVM.accent)
                    HStack {
                    Text("Periodic Table")
                    Spacer()
                    // Mode toggle
                    Button {
                        labVM.periodicTableMode = labVM.periodicTableMode == .addToScene ? .addToCanvas : .addToScene
                    } label: {
                        Label(labVM.periodicTableMode == .addToScene ? "→ 3D Scene" : "→ Canvas",
                              systemImage: labVM.periodicTableMode == .addToScene ? "cube" : "scribble")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(labVM.periodicTableMode == .addToCanvas ? .purple : themeVM.accent)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((labVM.periodicTableMode == .addToCanvas ? Color.purple : themeVM.accent).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }.frame(maxWidth: .infinity)
                Text("ignored_placeholder_never_rendered")
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundColor(themeVM.accent)
                    Spacer()
                    Button {
                        withAnimation(.spring()) {
                            labVM.isPeriodicTableVisible = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 44, height: 44)  // large tap target
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.9))

                // ── Search ──
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(themeVM.accent.opacity(0.6))
                        .font(.caption)
                    TextField("Search element, symbol, Z...", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .font(.system(.caption, design: .monospaced))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.4))
                                .font(.caption)
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

                // ── Category filter ──
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        categoryChip(nil, label: "All")
                        ForEach(ArcElement.ElementCategory.allCases, id: \.self) { cat in
                            categoryChip(cat, label: shortName(cat))
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.vertical, 3)

                // ── Periodic table grid — scrollable ──
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    let cellSize: CGFloat = 44
                    let spacing: CGFloat = 2

                    VStack(spacing: spacing) {
                        ForEach(0..<Self.gridMap.count, id: \.self) { rowIdx in
                            // Add separator row before lanthanides (row 7) and actinides (row 8)
                            if rowIdx == 7 {
                                Divider()
                                    .background(themeVM.accent.opacity(0.2))
                                    .padding(.vertical, 2)
                            }
                            HStack(spacing: spacing) {
                                ForEach(0..<Self.COLS, id: \.self) { colIdx in
                                    let z = Self.gridMap[rowIdx][colIdx]
                                    if z == 0 {
                                        // Empty spacer cell
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(width: cellSize, height: cellSize)
                                    } else if let el = elementMap[z] {
                                        let dimmed = !matchesFilter(el) &&
                                            (!searchText.isEmpty || selectedCategory != nil)
                                        PTCell(element: el, size: cellSize, dimmed: dimmed)
                                            .onTapGesture {
                                                labVM.addElement(el)
                                                labVM.log("Added \(el.elementSymbol) from periodic table")
                                            }
                                            .onDrag {
                                                NSItemProvider(object: el.elementSymbol as NSString)
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: .infinity)

                // ── Legend ──
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ArcElement.ElementCategory.allCases, id: \.self) { cat in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color(cat.color))
                                    .frame(width: 8, height: 8)
                                Text(shortName(cat))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5))
            }
            .background(Color(red:0.04, green:0.06, blue:0.1).opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeVM.accent.opacity(0.3), lineWidth: 0.5)
            )
            // ── CRITICAL: constrain to safe screen bounds ──
            .frame(
                width: min(geo.size.width, UIScreen.main.bounds.width) - 8,
                height: min(geo.size.height, UIScreen.main.bounds.height) - 16
            )
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .shadow(color: themeVM.accent.opacity(0.15), radius: 16)
        }
        .ignoresSafeArea(.keyboard)
    }

    private func categoryChip(_ category: ArcElement.ElementCategory?,
                               label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = (selectedCategory == category) ? nil : category
            }
        } label: {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(selectedCategory == category ? .black : .white.opacity(0.6))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    selectedCategory == category ?
                        (category != nil ? Color(category!.color) : themeVM.accent) :
                        Color.white.opacity(0.08)
                )
                .clipShape(Capsule())
        }
    }

    private func shortName(_ cat: ArcElement.ElementCategory) -> String {
        switch cat {
        case .alkaliMetal:     return "Alkali"
        case .alkalineEarth:   return "Alkaline"
        case .transitionMetal: return "Transition"
        case .postTransition:  return "Post-Trans"
        case .metalloid:       return "Metalloid"
        case .nonmetal:        return "Nonmetal"
        case .halogen:         return "Halogen"
        case .nobleGas:        return "Noble Gas"
        case .lanthanide:      return "Lanthanide"
        case .actinide:        return "Actinide"
        case .superactinide:   return "Superact."
        case .unknown:         return "Unknown"
        }
    }
}

// MARK: — Single PT cell
struct PTCell: View {
    let element: ArcElement
    let size: CGFloat
    let dimmed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(element.category.color).opacity(dimmed ? 0.07 : 0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(element.category.color).opacity(dimmed ? 0.2 : 0.6),
                                lineWidth: 0.5)
                )

            VStack(spacing: 0) {
                Text("\(element.protons)")
                    .font(.system(size: size * 0.16, design: .monospaced))
                    .foregroundColor(.white.opacity(dimmed ? 0.2 : 0.5))
                Text(element.elementSymbol)
                    .font(.system(size: size * 0.28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(dimmed ? 0.3 : 1.0))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(element.elementName.prefix(4))
                    .font(.system(size: size * 0.14, design: .monospaced))
                    .foregroundColor(.white.opacity(dimmed ? 0.15 : 0.55))
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
    }
}
