
import Foundation
import SceneKit

/// ArcLake element model — mirrors elements.json structure
public struct ArcElement: Identifiable, Codable, Sendable {
    public var id: Int
    public var elementName: String
    public var elementSymbol: String
    public var neutrons: Int
    public var protons: Int
    public var electrons: Int
    public var orbits: Int
    public var electronOrbits: [Int]
    public var atomicMass: Double
    public var category: ElementCategory
    public var standardState: StandardState
    public var meltingPoint: Double?  // Kelvin
    public var boilingPoint: Double?  // Kelvin
    public var density: Double?       // g/cm³
    public var electronegativity: Double?

    public enum ElementCategory: String, Codable, CaseIterable, Sendable {
        case alkaliMetal      = "Alkali Metal"
        case alkalineEarth    = "Alkaline Earth Metal"
        case transitionMetal  = "Transition Metal"
        case postTransition   = "Post-Transition Metal"
        case metalloid        = "Metalloid"
        case nonmetal         = "Nonmetal"
        case halogen          = "Halogen"
        case nobleGas         = "Noble Gas"
        case lanthanide       = "Lanthanide"
        case actinide         = "Actinide"
        case superactinide    = "Superactinide"
        case unknown          = "Unknown"

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

    public enum StandardState: String, Codable, Sendable {
        case solid, liquid, gas, unknown
    }

    /// Neutron-first mass: n⁰ → p⁺ → electrons
    public var neutronFirstMass: Double {
        Double(neutrons) * 1.008665 + Double(protons) * 1.007276 + Double(electrons) * 0.000549
    }

    /// Arc Edge circumference: C = √(d × DOC)² where DOC = 3.0
    public var arcEdgeCircumference: Double {
        let diameter = atomicMass * 0.1  // scaled diameter in pm
        return pow(diameter * 3.0, 2.0).squareRoot()
    }
}

/// JSON decoder — loads from bundle or remote
public final class ElementStore {
    public static let shared = ElementStore()
    public private(set) var elements: [ArcElement] = []

    private init() {
        load()
    }

    private func load() {
        // Try bundle first, fall back to hardcoded minimal set
        if let url = Bundle.main.url(forResource: "elements", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ArcElementRaw].self, from: data) {
            elements = decoded.enumerated().compactMap { idx, raw in
                guard idx > 0 else { return nil }  // skip header row
                return ArcElement(
                    id: idx,
                    elementName: raw.elementName.trimmingCharacters(in: .whitespaces),
                    elementSymbol: symbolFor(atomicNumber: idx),
                    neutrons: raw.neutrons,
                    protons: raw.protons,
                    electrons: raw.electrons,
                    orbits: raw.orbits,
                    electronOrbits: raw.electronOrbits,
                    atomicMass: massFor(atomicNumber: idx),
                    category: categoryFor(atomicNumber: idx),
                    standardState: stateFor(atomicNumber: idx),
                    meltingPoint: nil,
                    boilingPoint: nil,
                    density: nil,
                    electronegativity: nil
                )
            }
        } else {
            elements = ArcElement.builtinElements
        }
    }

    // Raw JSON shape
    private struct ArcElementRaw: Codable {
        let elementName: String
        let neutrons: Int
        let protons: Int
        let electrons: Int
        let orbits: Int
        let electronOrbits: [Int]
    }
}

// MARK: — Symbol lookup table (Z → symbol)
private func symbolFor(atomicNumber z: Int) -> String {
    let symbols = ["","H","He","Li","Be","B","C","N","O","F","Ne",
        "Na","Mg","Al","Si","P","S","Cl","Ar","K","Ca",
        "Sc","Ti","V","Cr","Mn","Fe","Co","Ni","Cu","Zn",
        "Ga","Ge","As","Se","Br","Kr","Rb","Sr","Y","Zr",
        "Nb","Mo","Tc","Ru","Rh","Pd","Ag","Cd","In","Sn",
        "Sb","Te","I","Xe","Cs","Ba","La","Ce","Pr","Nd",
        "Pm","Sm","Eu","Gd","Tb","Dy","Ho","Er","Tm","Yb",
        "Lu","Hf","Ta","W","Re","Os","Ir","Pt","Au","Hg",
        "Tl","Pb","Bi","Po","At","Rn","Fr","Ra","Ac","Th",
        "Pa","U","Np","Pu","Am","Cm","Bk","Cf","Es","Fm",
        "Md","No","Lr","Rf","Db","Sg","Bh","Hs","Mt","Ds",
        "Rg","Cn","Nh","Fl","Mc","Lv","Ts","Og",
        "Ue","Ubn","Ubu","Ubb","Ubt","Ubq","Ubp","Ubh","Ubs","Ubn2"]
    return z < symbols.count ? symbols[z] : "E\(z)"
}

private func massFor(atomicNumber z: Int) -> Double {
    let masses: [Int: Double] = [
        1:1.008,2:4.003,3:6.941,4:9.012,5:10.811,6:12.011,7:14.007,8:15.999,9:18.998,10:20.180,
        11:22.990,12:24.305,13:26.982,14:28.086,15:30.974,16:32.065,17:35.453,18:39.948,
        19:39.098,20:40.078,26:55.845,29:63.546,47:107.868,79:196.967,92:238.029
    ]
    return masses[z] ?? Double(z) * 2.0
}

private func categoryFor(atomicNumber z: Int) -> ArcElement.ElementCategory {
    switch z {
    case 1: return .nonmetal
    case 2,10,18,36,54,86,118: return .nobleGas
    case 3,11,19,37,55,87: return .alkaliMetal
    case 4,12,20,38,56,88: return .alkalineEarth
    case 5,14,32,33,51,52,85: return .metalloid
    case 6,7,8,15,16,34: return .nonmetal
    case 9,17,35,53: return .halogen
    case 57...71: return .lanthanide
    case 89...103: return .actinide
    case 119...128: return .superactinide
    case 21...30,39...48,72...80: return .transitionMetal
    default: return .unknown
    }
}

private func stateFor(atomicNumber z: Int) -> ArcElement.StandardState {
    let gases  = Set([1,2,7,8,9,10,17,18,35,36,53,54,85,86,118])
    let liquids = Set([35,80])
    if liquids.contains(z) { return .liquid }
    if gases.contains(z)   { return .gas }
    if z > 103             { return .unknown }
    return .solid
}

// MARK: — Builtin minimal element set (fallback)
extension ArcElement {
    static var builtinElements: [ArcElement] {
        (1...118).map { z in
            ArcElement(id: z, elementName: symbolFor(atomicNumber: z),
                      elementSymbol: symbolFor(atomicNumber: z),
                      neutrons: z, protons: z, electrons: z,
                      orbits: max(1, (z - 1) / 18 + 1),
                      electronOrbits: [z],
                      atomicMass: massFor(atomicNumber: z),
                      category: categoryFor(atomicNumber: z),
                      standardState: stateFor(atomicNumber: z),
                      meltingPoint: nil, boilingPoint: nil,
                      density: nil, electronegativity: nil)
        }
    }
}
