import Foundation
import SceneKit

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
    public var meltingPoint: Double?
    public var boilingPoint: Double?
    public var density: Double?
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

        public var color: UIColor {
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

    public enum StandardState: String, Codable, Sendable {
        case solid, liquid, gas, unknown
    }

    public var neutronFirstMass: Double {
        Double(neutrons)*1.008665 + Double(protons)*1.007276 + Double(electrons)*0.000549
    }
    public var arcEdgeCircumference: Double { sqrt(pow(atomicMass*0.1*3.0, 2.0)) }
}

// Standard periodic table grid [period][group] → atomic number (0 = empty spacer)
public let periodicTableLayout: [(z: Int, period: Int, group: Int)] = [
    (1,1,1),(2,1,18),
    (3,2,1),(4,2,2),(5,2,13),(6,2,14),(7,2,15),(8,2,16),(9,2,17),(10,2,18),
    (11,3,1),(12,3,2),(13,3,13),(14,3,14),(15,3,15),(16,3,16),(17,3,17),(18,3,18),
    (19,4,1),(20,4,2),(21,4,3),(22,4,4),(23,4,5),(24,4,6),(25,4,7),(26,4,8),
    (27,4,9),(28,4,10),(29,4,11),(30,4,12),(31,4,13),(32,4,14),(33,4,15),(34,4,16),(35,4,17),(36,4,18),
    (37,5,1),(38,5,2),(39,5,3),(40,5,4),(41,5,5),(42,5,6),(43,5,7),(44,5,8),
    (45,5,9),(46,5,10),(47,5,11),(48,5,12),(49,5,13),(50,5,14),(51,5,15),(52,5,16),(53,5,17),(54,5,18),
    (55,6,1),(56,6,2),(57,6,3),(72,6,4),(73,6,5),(74,6,6),(75,6,7),(76,6,8),
    (77,6,9),(78,6,10),(79,6,11),(80,6,12),(81,6,13),(82,6,14),(83,6,15),(84,6,16),(85,6,17),(86,6,18),
    (87,7,1),(88,7,2),(89,7,3),(104,7,4),(105,7,5),(106,7,6),(107,7,7),(108,7,8),
    (109,7,9),(110,7,10),(111,7,11),(112,7,12),(113,7,13),(114,7,14),(115,7,15),(116,7,16),(117,7,17),(118,7,18),
    (58,8,4),(59,8,5),(60,8,6),(61,8,7),(62,8,8),(63,8,9),(64,8,10),
    (65,8,11),(66,8,12),(67,8,13),(68,8,14),(69,8,15),(70,8,16),(71,8,17),
    (90,9,4),(91,9,5),(92,9,6),(93,9,7),(94,9,8),(95,9,9),(96,9,10),
    (97,9,11),(98,9,12),(99,9,13),(100,9,14),(101,9,15),(102,9,16),(103,9,17),
    (119,10,1),(120,10,2),(121,10,3),(122,10,4),(123,10,5),(124,10,6),
    (125,10,7),(126,10,8),(127,10,9)
]

public final class ElementStore {
    public static let shared = ElementStore()
    public private(set) var elements: [ArcElement] = []

    private static let superactinideNames: [Int: (name: String, symbol: String)] = [
        119:("Ununennium","Uue"), 120:("Unbinilium","Ubn"), 121:("Unbiunium","Ubu"),
        122:("Unbibium","Ubb"),   123:("Unbitrium","Ubt"),  124:("Unbiquadium","Ubq"),
        125:("Unbipentium","Ubp"),126:("Unbihexium","Ubh"), 127:("Unbiseptium","Ubs")
    ]

    private init() { load() }

    // Raw JSON row — uses Any for fields that are String in header row, Int elsewhere
    private struct RawRow: Decodable {
        let elementName: String
        let neutrons:    JSONInt
        let protons:     JSONInt
        let electrons:   JSONInt
        let orbits:      Int
        let electronOrbits: [Int]
    }

    // Decodes both Int and String (ignores strings, returns 0)
    private struct JSONInt: Decodable {
        let value: Int
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { value = i }
            else { value = 0 }  // header row strings → 0
        }
    }

    private func load() {
        guard let url   = Bundle.main.url(forResource:"elements", withExtension:"json"),
              let data  = try? Data(contentsOf: url),
              let rows  = try? JSONDecoder().decode([RawRow].self, from: data)
        else { elements = ArcElement.builtinElements; return }

        // Index 0 is the header row (neutrons="Nuetrons" etc.) — skip it
        // Index 1 = Hydrogen (Z=1), index 2 = Helium (Z=2) ...
        elements = rows.enumerated().compactMap { idx, row in
            guard idx > 0 else { return nil }   // skip header
            guard row.protons.value > 0 else { return nil } // skip any other bad rows
            let z = idx
            let name   = ElementStore.superactinideNames[z]?.name   ?? row.elementName.trimmingCharacters(in:.whitespaces)
            let symbol = ElementStore.superactinideNames[z]?.symbol ?? symbolFor(z:z)
            return ArcElement(
                id: z, elementName: name, elementSymbol: symbol,
                neutrons: row.neutrons.value, protons: row.protons.value,
                electrons: row.electrons.value, orbits: row.orbits,
                electronOrbits: row.electronOrbits,
                atomicMass: massFor(z:z), category: categoryFor(z:z),
                standardState: stateFor(z:z),
                meltingPoint:nil, boilingPoint:nil, density:nil, electronegativity:nil)
        }
        print("[ElementStore] Loaded \(elements.count) elements (H=\(elements.first?.elementSymbol ?? "?"))")
    }
}

private func symbolFor(z: Int) -> String {
    let s = ["","H","He","Li","Be","B","C","N","O","F","Ne",
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
             "Uue","Ubn","Ubu","Ubb","Ubt","Ubq","Ubp","Ubh","Ubs"]
    return z < s.count ? s[z] : "E\(z)"
}

private func massFor(z: Int) -> Double {
    let m:[Int:Double]=[1:1.008,2:4.003,3:6.941,4:9.012,5:10.811,6:12.011,7:14.007,
        8:15.999,9:18.998,10:20.180,11:22.990,12:24.305,13:26.982,14:28.086,15:30.974,
        16:32.065,17:35.453,18:39.948,19:39.098,20:40.078,26:55.845,29:63.546,
        47:107.868,79:196.967,92:238.029]
    return m[z] ?? Double(z)*2.0
}

private func categoryFor(z: Int) -> ArcElement.ElementCategory {
    switch z {
    case 1:             return .nonmetal
    case 2,10,18,36,54,86,118: return .nobleGas
    case 3,11,19,37,55,87:     return .alkaliMetal
    case 4,12,20,38,56,88:     return .alkalineEarth
    case 5,14,32,33,51,52,85:  return .metalloid
    case 6,7,8,15,16,34:       return .nonmetal
    case 9,17,35,53,117:       return .halogen
    case 57...71:               return .lanthanide
    case 89...103:              return .actinide
    case 119...127:             return .superactinide
    case 21...30,39...48,72...80,104...112: return .transitionMetal
    default:            return .unknown
    }
}

private func stateFor(z: Int) -> ArcElement.StandardState {
    let gases:   Set<Int> = [1,2,7,8,9,10,17,18,36,54,86,118]
    let liquids: Set<Int> = [35,80]
    if liquids.contains(z) { return .liquid }
    if gases.contains(z)   { return .gas }
    if z > 103             { return .unknown }
    return .solid
}

extension ArcElement {
    static var builtinElements: [ArcElement] {
        (1...127).map { z in
            ArcElement(id:z,elementName:symbolFor(z:z),elementSymbol:symbolFor(z:z),
                      neutrons:z,protons:z,electrons:z,orbits:max(1,(z-1)/18+1),
                      electronOrbits:[z],atomicMass:massFor(z:z),category:categoryFor(z:z),
                      standardState:stateFor(z:z),meltingPoint:nil,boilingPoint:nil,
                      density:nil,electronegativity:nil)
        }
    }
}
