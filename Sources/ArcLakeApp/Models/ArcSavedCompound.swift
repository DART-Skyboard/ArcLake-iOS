import Foundation
import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// ArcSavedCompound — a named, persisted compound designed by the user
// in the element/molecule editor (ArcLabViewModel.selectedElements).
//
// Task #39: there was previously no persistence for designed compounds
// at all — selectedElements was purely live canvas state, lost whenever
// the canvas was cleared or the app relaunched. This gives the user a
// durable library of named compounds ("Kerosene Mix", "My Oxidizer",
// etc.) they can build once in the Mol Canvas / Periodic Table flow and
// reuse forever afterward, including as a fill choice for any CFD
// container (see ArcComponentConfigView's propellant picker, task #40).
//
// Kept intentionally simple per the task brief: UserDefaults-backed
// JSON array, no CoreData. ArcElement is already Codable/Sendable
// (see Models/Element.swift) so this just wraps a name + element array
// + a couple of derived display fields.
// ═══════════════════════════════════════════════════════════════════

public struct ArcSavedCompound: Identifiable, Codable, Equatable {
    // Manual == instead of synthesized: ArcElement (Models/Element.swift)
    // doesn't conform to Equatable, so Swift can't auto-derive this and
    // the build fails (caught after CI broke on builds 398-400 — a
    // prior pass declared this type Equatable without checking that its
    // stored ArcElement array could actually satisfy it). Identity by id
    // is correct for this type's actual uses (List selection/diffing in
    // ArcCompoundLibraryView) — full deep element-array equality was
    // never needed.
    public static func == (lhs: ArcSavedCompound, rhs: ArcSavedCompound) -> Bool {
        lhs.id == rhs.id
    }

    public var id: UUID = UUID()
    public var name: String
    /// Full element set as designed on the canvas — same granularity as
    /// ArcLabViewModel.selectedElements (one entry per atom instance,
    /// duplicates included), so a formula/weight/color can always be
    /// re-derived exactly as the user built it.
    public var elements: [ArcElement]
    public var dateCreated: Date = Date()

    /// Element symbols only — what ArcFluidEngine/fillComponentCavity
    /// actually consume (colorFor(syms[...]), reactionHeat keyword
    /// checks, etc.)
    public var elementSymbols: [String] { elements.map { $0.elementSymbol } }

    /// Simple condensed formula, e.g. ["H","H","O"] -> "H2O". Counts
    /// symbols in the order first-seen on the canvas (not alphabetized —
    /// this mirrors how a user would read back what they built, not a
    /// strict Hill-system formula).
    public var displayFormula: String {
        guard !elements.isEmpty else { return "—" }
        var order: [String] = []
        var counts: [String: Int] = [:]
        for el in elements {
            let s = el.elementSymbol
            if counts[s] == nil { order.append(s) }
            counts[s, default: 0] += 1
        }
        return order.map { sym -> String in
            let n = counts[sym] ?? 1
            return n > 1 ? "\(sym)\(n)" : sym
        }.joined()
    }

    /// Estimated molar mass (sum of atomic masses, g/mol) — the only
    /// thing derivable purely from the element set without real bond/
    /// phase chemistry. Used as a rough density proxy when no better
    /// number exists.
    public var estimatedMolarMass: Double {
        elements.reduce(0) { $0 + $1.atomicMass }
    }

    /// Estimated liquid density (kg/m³). There's no rigorous way to get
    /// real liquid density from atomic composition alone, so this is a
    /// simple heuristic: scale a generic organic-liquid baseline by the
    /// average atomic mass per atom, clamped to a physically-plausible
    /// liquid-density band. It's clearly labeled "estimated" everywhere
    /// it's surfaced in the UI — good enough to seed a CFD fill's flow
    /// velocity (ArcCombustionFlow.flowVelocity) without claiming lab
    /// accuracy.
    public var estimatedDensityKgM3: Double {
        guard !elements.isEmpty else { return 800 }
        let avgMass = estimatedMolarMass / Double(elements.count)
        let estimate = 400 + avgMass * 45
        return min(4000, max(300, estimate))
    }

    /// Representative color for list rows / fill UI — the first
    /// element's CPK-ish color if available, else a neutral default.
    public var displayColor: Color {
        guard let first = elements.first else { return .gray }
        return ArcSavedCompound.cpkColor(for: first.elementSymbol)
    }

    // Small standalone CPK swatch (keeps this model free of a dependency
    // on ArcFluidEngine's @MainActor colorFor(_:)).
    private static let cpk: [String: (Double,Double,Double)] = [
        "H":(1,1,1),"He":(0.85,1,1),"Li":(0.8,0.5,1),"Be":(0.76,1,0),
        "B":(1,0.71,0.71),"C":(0.56,0.56,0.56),"N":(0.19,0.31,0.97),
        "O":(1,0.05,0.05),"F":(0.56,0.82,0.31),"Ne":(0.7,0.89,0.96),
        "Na":(0.67,0.36,0.95),"Mg":(0.54,1,0),"Al":(0.75,0.65,0.65),
        "Si":(0.94,0.78,0.63),"P":(1,0.5,0),"S":(1,1,0.19),
        "Cl":(0.12,0.94,0.12),"K":(0.56,0.25,0.83),"Ca":(0.24,1,0),
        "Fe":(0.88,0.4,0.2),"Cu":(0.78,0.5,0.2),"Au":(1,0.82,0.14),
        "Ag":(0.75,0.75,0.75),"Pb":(0.34,0.35,0.38),"U":(0.04,0.56,0.56)
    ]
    static func cpkColor(for symbol: String) -> Color {
        if let c = cpk[symbol] { return Color(red: c.0, green: c.1, blue: c.2) }
        return .mint
    }
}

// MARK: — Persisted library (UserDefaults JSON, per the task brief —
// deliberately not CoreData)
@MainActor
public final class ArcCompoundLibrary: ObservableObject {
    public static let shared = ArcCompoundLibrary()

    @Published public private(set) var compounds: [ArcSavedCompound] = []

    private let defaultsKey = "ArcSavedCompounds.v1"

    private init() {
        load()
    }

    public func save(name: String, elements: [ArcElement]) -> ArcSavedCompound {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let compound = ArcSavedCompound(
            name: trimmed.isEmpty ? "Unnamed Compound" : trimmed,
            elements: elements)
        compounds.append(compound)
        persist()
        return compound
    }

    public func delete(_ compound: ArcSavedCompound) {
        compounds.removeAll { $0.id == compound.id }
        persist()
    }

    public func delete(at offsets: IndexSet) {
        compounds.remove(atOffsets: offsets)
        persist()
    }

    public func rename(_ compound: ArcSavedCompound, to newName: String) {
        guard let idx = compounds.firstIndex(where: { $0.id == compound.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        compounds[idx].name = trimmed
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(compounds)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            print("[ArcCompoundLibrary] ⚠ failed to persist: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            compounds = try JSONDecoder().decode([ArcSavedCompound].self, from: data)
        } catch {
            print("[ArcCompoundLibrary] ⚠ failed to load saved compounds: \(error)")
            compounds = []
        }
    }
}
