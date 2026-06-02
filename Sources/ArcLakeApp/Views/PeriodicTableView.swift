
import SwiftUI

public struct PeriodicTableView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var searchText = ""
    @State private var selectedCategory: ArcElement.ElementCategory? = nil

    // Standard periodic table grid positions [symbol: (row, col)]
    private static let gridPositions: [String: (Int, Int)] = {
        var pos: [String: (Int, Int)] = [:]
        // Period 1
        pos["H"]  = (1,1);  pos["He"] = (1,18)
        // Period 2
        pos["Li"] = (2,1);  pos["Be"] = (2,2)
        pos["B"]  = (2,13); pos["C"]  = (2,14); pos["N"]  = (2,15)
        pos["O"]  = (2,16); pos["F"]  = (2,17); pos["Ne"] = (2,18)
        // Period 3
        pos["Na"] = (3,1);  pos["Mg"] = (3,2)
        pos["Al"] = (3,13); pos["Si"] = (3,14); pos["P"]  = (3,15)
        pos["S"]  = (3,16); pos["Cl"] = (3,17); pos["Ar"] = (3,18)
        // Period 4
        pos["K"]  = (4,1);  pos["Ca"] = (4,2)
        pos["Sc"] = (4,3);  pos["Ti"] = (4,4);  pos["V"]  = (4,5)
        pos["Cr"] = (4,6);  pos["Mn"] = (4,7);  pos["Fe"] = (4,8)
        pos["Co"] = (4,9);  pos["Ni"] = (4,10); pos["Cu"] = (4,11)
        pos["Zn"] = (4,12); pos["Ga"] = (4,13); pos["Ge"] = (4,14)
        pos["As"] = (4,15); pos["Se"] = (4,16); pos["Br"] = (4,17); pos["Kr"] = (4,18)
        // Period 5
        pos["Rb"] = (5,1);  pos["Sr"] = (5,2)
        pos["Y"]  = (5,3);  pos["Zr"] = (5,4);  pos["Nb"] = (5,5)
        pos["Mo"] = (5,6);  pos["Tc"] = (5,7);  pos["Ru"] = (5,8)
        pos["Rh"] = (5,9);  pos["Pd"] = (5,10); pos["Ag"] = (5,11)
        pos["Cd"] = (5,12); pos["In"] = (5,13); pos["Sn"] = (5,14)
        pos["Sb"] = (5,15); pos["Te"] = (5,16); pos["I"]  = (5,17); pos["Xe"] = (5,18)
        // Period 6
        pos["Cs"] = (6,1);  pos["Ba"] = (6,2);  pos["La"] = (8,3)
        pos["Hf"] = (6,4);  pos["Ta"] = (6,5);  pos["W"]  = (6,6)
        pos["Re"] = (6,7);  pos["Os"] = (6,8);  pos["Ir"] = (6,9)
        pos["Pt"] = (6,10); pos["Au"] = (6,11); pos["Hg"] = (6,12)
        pos["Tl"] = (6,13); pos["Pb"] = (6,14); pos["Bi"] = (6,15)
        pos["Po"] = (6,16); pos["At"] = (6,17); pos["Rn"] = (6,18)
        // Period 7
        pos["Fr"] = (7,1);  pos["Ra"] = (7,2)
        pos["Rf"] = (7,4);  pos["Db"] = (7,5);  pos["Sg"] = (7,6)
        pos["Bh"] = (7,7);  pos["Hs"] = (7,8);  pos["Mt"] = (7,9)
        pos["Ds"] = (7,10); pos["Rg"] = (7,11); pos["Cn"] = (7,12)
        pos["Nh"] = (7,13); pos["Fl"] = (7,14); pos["Mc"] = (7,15)
        pos["Lv"] = (7,16); pos["Ts"] = (7,17); pos["Og"] = (7,18)
        return pos
    }()

    private var filteredElements: [ArcElement] {
        ElementStore.shared.elements.filter { el in
            let matchSearch = searchText.isEmpty ||
                el.elementName.localizedCaseInsensitiveContains(searchText) ||
                el.elementSymbol.localizedCaseInsensitiveContains(searchText) ||
                String(el.protons).contains(searchText)
            let matchCategory = selectedCategory == nil || el.category == selectedCategory
            return matchSearch && matchCategory
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Periodic Table")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(themeVM.accent)
                Spacer()
                Button {
                    withAnimation { labVM.isPeriodicTableVisible = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.8))

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(themeVM.accent.opacity(0.6))
                TextField("Search element, symbol, Z...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .font(.system(.caption, design: .monospaced))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(nil, label: "All")
                    ForEach(ArcElement.ElementCategory.allCases, id: \.self) { cat in
                        categoryChip(cat, label: cat.rawValue.components(separatedBy: " ").first ?? cat.rawValue)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 4)

            // Toggle: grid vs list
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 3), count: 9),
                          spacing: 3) {
                    ForEach(filteredElements) { element in
                        ElementCard(element: element)
                            .onTapGesture {
                                labVM.addElement(element)
                                labVM.log("Selected \(element.elementSymbol) from periodic table")
                            }
                    }
                }
                .padding(8)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeVM.accent.opacity(0.3), lineWidth: 0.5)
        )
        .padding()
        .frame(maxHeight: UIScreen.main.bounds.height * 0.75)
        .shadow(color: themeVM.accent.opacity(0.2), radius: 20)
    }

    private func categoryChip(_ category: ArcElement.ElementCategory?, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
            }
        } label: {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(selectedCategory == category ? .black : .white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selectedCategory == category ?
                    (category.map { Color(category!.color) } ?? themeVM.accent) :
                    Color.white.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}

// MARK: — Element Card with drag support
struct ElementCard: View {
    let element: ArcElement
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var isDragging = false

    var catColor: Color { Color(element.category.color) }

    var body: some View {
        VStack(spacing: 1) {
            Text(String(element.protons))
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Text(element.elementSymbol)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text(element.elementName.prefix(6))
                .font(.system(size: 6, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(width: 50, height: 58)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(catColor.opacity(isDragging ? 0.5 : 0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(catColor.opacity(0.6), lineWidth: 0.5)
                )
        )
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .shadow(color: catColor.opacity(isDragging ? 0.5 : 0), radius: 8)
        // Drag provider — drag to 3D scene or mol canvas
        .onDrag {
            isDragging = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isDragging = false
            }
            let provider = NSItemProvider(object: element.elementSymbol as NSString)
            return provider
        }
        .animation(.spring(response: 0.2), value: isDragging)
    }
}

private extension ArcElement.ElementCategory {
    var color: UIColor {
        switch self {
        case .alkaliMetal:     return UIColor(red: 1.0,  green: 0.4,  blue: 0.4,  alpha: 1)
        case .alkalineEarth:   return UIColor(red: 1.0,  green: 0.7,  blue: 0.3,  alpha: 1)
        case .transitionMetal: return UIColor(red: 0.4,  green: 0.7,  blue: 1.0,  alpha: 1)
        case .postTransition:  return UIColor(red: 0.4,  green: 0.9,  blue: 0.6,  alpha: 1)
        case .metalloid:       return UIColor(red: 0.7,  green: 0.9,  blue: 0.4,  alpha: 1)
        case .nonmetal:        return UIColor(red: 0.3,  green: 0.9,  blue: 0.9,  alpha: 1)
        case .halogen:         return UIColor(red: 0.9,  green: 0.6,  blue: 0.9,  alpha: 1)
        case .nobleGas:        return UIColor(red: 0.6,  green: 0.4,  blue: 1.0,  alpha: 1)
        case .lanthanide:      return UIColor(red: 1.0,  green: 0.5,  blue: 0.7,  alpha: 1)
        case .actinide:        return UIColor(red: 0.8,  green: 0.3,  blue: 0.5,  alpha: 1)
        case .superactinide:   return UIColor(red: 0.5,  green: 0.2,  blue: 0.8,  alpha: 1)
        case .unknown:         return UIColor(red: 0.5,  green: 0.5,  blue: 0.5,  alpha: 1)
        }
    }
}
