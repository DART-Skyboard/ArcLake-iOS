
import SwiftUI

// MARK: — Periodic Table Mode
public enum PeriodicTableMode { case addToScene, addToCanvas }

// MARK: — Mol Canvas Atom Node
public struct MolAtomNode: Identifiable {
    public let id: UUID
    public var symbol: String
    public var atomicNumber: Int
    public var color: UIColor
    public var position: CGPoint
    public var label: String

    public init(symbol: String, z: Int, color: UIColor, at pos: CGPoint) {
        id = UUID(); self.symbol = symbol; atomicNumber = z
        self.color = color; position = pos; label = symbol
    }
}

// MARK: — Mol Bond
public struct MolBond: Identifiable {
    public let id: UUID
    public var fromId: UUID
    public var toId: UUID
    public var order: Int      // 1=single 2=double 3=triple
    public var isDelta: Bool   // Δ algebra connection

    public init(from: UUID, to: UUID, order: Int = 1, isDelta: Bool = false) {
        id = UUID(); fromId = from; toId = to
        self.order = order; self.isDelta = isDelta
    }
}

// MARK: — Delta Algebra Connection
public struct DeltaConnection: Identifiable {
    public let id: UUID
    public var fromAtomId: UUID
    public var toAtomId: UUID
    public var fromShell: Int
    public var toShell: Int
    public var operator_: String
    public var label: String

    public init(from: UUID, to: UUID, fromShell: Int = 0, toShell: Int = 0, op: String = "+") {
        id = UUID(); fromAtomId = from; toAtomId = to
        self.fromShell = fromShell; self.toShell = toShell
        operator_ = op; label = "Δ(\(fromShell)→\(toShell))"
    }
}

// MARK: — Scene Tab Data
public struct SceneTabData: Identifiable {
    public let id: UUID
    public var name: String
    public var atomIds: [Int]
    public var isCFDMode: Bool

    public init(name: String) {
        id = UUID(); self.name = name; atomIds = []; isCFDMode = false
    }
}

// MARK: — Log Entry
public struct LogEntry: Identifiable {
    public let id = UUID()
    public let message: String
    public let timestamp = Date()
    public var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: timestamp)
    }
}

// MARK: — Alloy Component
public struct AlloyComponent: Identifiable {
    public var id = UUID()
    public var element: ArcElement
    public var percentage: Double
    public var castingOrder: Int
}

// MARK: — Equation Node Graph (Algebra Menu / Node Editor / Molecule Canvas)
// Built for the Algebra Menu redesign. IMPORTANT design decision: sockets do
// NOT own copies of their values. A socket points at a real MolAtomNode /
// MolBond / DeltaConnection by id, and its displayed value is always looked
// up fresh from those arrays (see ArcLabViewModel.socketDisplayValue). This
// means the Algebra Menu, Node Editor, and Molecule Canvas can never drift
// out of sync with each other — there's nothing to sync, because there's
// only ever one copy of the actual data. Editing a bond order on the canvas
// updates the same value an equation node's Bond socket reads; editing a
// socket in the Node Editor writes back to that same molBonds entry.

public enum EquationSocketKind: String, Codable, CaseIterable {
    case elementSelection   // Element Selection/Search List
    case elementComponent   // Element Component List (+/-)
    case orbitShell         // Orbit Shell Selector (+/-)
    case physicsAttribute   // which of the 6 physics values (mass/volume/weight/density/temperature/velocity)
    case physicsValue       // the numeric value assigned to the sibling physicsAttribute socket, unit-aware
    case mathOperator       // Math Operator Selection List (+/-), includes N/A for terminal daisy-chain nodes
    case bond                // Incoming/Outgoing Bond Sockets (+/-)
    case delta               // Incoming/Outgoing Delta sockets for Orbit Shells (+/-)

    public var displayName: String {
        switch self {
        case .elementSelection: return "Element"
        case .elementComponent: return "Component"
        case .orbitShell:       return "Orbit Shell"
        case .physicsAttribute: return "Physics Attr"
        case .physicsValue:     return "Value"
        case .mathOperator:     return "Operator"
        case .bond:              return "Bond"
        case .delta:             return "Δ Delta"
        }
    }
    public var color: UIColor {
        switch self {
        case .elementSelection: return .systemCyan
        case .elementComponent: return .systemTeal
        case .orbitShell:       return .systemPurple
        case .physicsAttribute: return .systemYellow
        case .physicsValue:     return .systemIndigo
        case .mathOperator:     return .systemOrange
        case .bond:              return .systemGreen
        case .delta:             return .systemPink
        }
    }
}

public enum EquationSocketDirection: String, Codable { case incoming, outgoing }

public struct EquationSocket: Identifiable, Codable {
    public let id: UUID
    public var kind: EquationSocketKind
    public var direction: EquationSocketDirection
    public var label: String

    // Live pointers into the real data — see the design note above. At most
    // one of these is meaningful per socket kind (elementSelection uses
    // linkedAtomId, bond uses linkedBondId, orbitShell/mathOperator/delta use
    // linkedDeltaId — a DeltaConnection already carries fromShell/toShell/op).
    public var linkedAtomId: UUID? = nil
    public var linkedBondId: UUID? = nil
    public var linkedDeltaId: UUID? = nil

    // Fallback only for a socket that hasn't been wired to real canvas data
    // yet — never a second source of truth once linked.
    public var localValue: String = ""
    // Numeric fallback, used specifically by .physicsValue sockets (the
    // number a person types in for whichever physics attribute the sibling
    // .physicsAttribute socket on the same node is set to).
    public var doubleValue: Double = 0

    public init(kind: EquationSocketKind, direction: EquationSocketDirection, label: String? = nil) {
        id = UUID(); self.kind = kind; self.direction = direction
        self.label = label ?? kind.displayName
    }
}

// Order-of-operations role. Neutron nodes are the origin every algebra
// propagation is measured from; a Proton-role node must resolve Radian state
// (Gas/Liquid/Solid — via proportionality/congruency of an angle or degree)
// before any Algebra-role node downstream of it evaluates. See
// ArcLabViewModel.evaluationOrder().
public enum EquationNodeRole: String, Codable, CaseIterable {
    case neutron, proton, algebra, group

    public var displayName: String {
        switch self {
        case .neutron: return "Neutron (origin)"
        case .proton:  return "Proton (resolves state)"
        case .algebra: return "Algebra"
        case .group:   return "Parentheses Group"
        }
    }

    // Short label for tight spaces (e.g. a 4-way segmented control on a
    // phone-width screen) — the full displayName wraps/truncates badly there.
    public var shortLabel: String {
        switch self {
        case .neutron: return "n⁰"
        case .proton:  return "p⁺"
        case .algebra: return "Algebra"
        case .group:   return "Group"
        }
    }
}

public struct EquationNode: Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var position: CGPoint
    public var role: EquationNodeRole

    public var incomingSockets: [EquationSocket] = []
    public var outgoingSockets: [EquationSocket] = []

    // Which atom in the Molecule Canvas this node represents — nil for a
    // free-floating equation node not tied to a placed atom yet.
    public var boundAtomId: UUID? = nil

    // Which SCENE element (by symbol — scene elements are a set, not
    // individually-placed instances with their own id, unlike Molecule
    // Canvas atoms) this node is about. This is the primary binding for
    // the "one node pertains to one element" workflow — molecule-canvas
    // atom binding (above) is a separate, additional path specifically for
    // bond/delta sync with the canvas.
    public var boundElementSymbol: String? = nil

    // "Most Outer Parentheses Math Operator Group Nest" — nodes can nest
    // inside a .group-role parent for explicit operator precedence.
    public var parentGroupId: UUID? = nil

    public init(title: String, position: CGPoint, role: EquationNodeRole = .algebra) {
        id = UUID(); self.title = title; self.position = position; self.role = role
    }
}

public struct EquationConnection: Identifiable, Codable {
    public let id: UUID
    public var fromNodeId: UUID
    public var fromSocketId: UUID
    public var toNodeId: UUID
    public var toSocketId: UUID
    public var isDelta: Bool

    public init(fromNodeId: UUID, fromSocketId: UUID, toNodeId: UUID, toSocketId: UUID, isDelta: Bool = false) {
        id = UUID()
        self.fromNodeId = fromNodeId; self.fromSocketId = fromSocketId
        self.toNodeId = toNodeId; self.toSocketId = toSocketId
        self.isDelta = isDelta
    }
}
