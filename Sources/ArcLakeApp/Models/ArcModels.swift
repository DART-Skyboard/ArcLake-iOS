
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
