
import Foundation
import Combine

/// Environment physics — mirrors web app's scenePhysicsState
public final class PhysicsState: ObservableObject, @unchecked Sendable {

    // Standard atmospheric defaults (from web app)
    @Published public var temperature:    Double = 72.0    // °F
    @Published public var gravity:        Double = 9.8     // m/s²
    @Published public var pressure:       Double = 14.7    // psi
    @Published public var velocity:       Double = 0.0     // m/s
    @Published public var viscosity:      Double = 1.0     // cP
    @Published public var magnetism:      Double = 0.0     // T
    @Published public var electricField:  Double = 0.0     // V/m

    // Nucleus thresholds (from web app arcEdge logic)
    @Published public var stableForce:    Double = 1.0
    @Published public var isNucleusActive: Bool  = false

    // Per-tab physics (Large Scale CFD)
    @Published public var tabs: [CFDTab] = (0..<5).map { CFDTab(id: $0) }
    @Published public var activeTabIndex: Int = 0

    public var activeTab: CFDTab {
        get { tabs[activeTabIndex] }
        set { tabs[activeTabIndex] = newValue }
    }

    /// Arc Edge influence: base × modified gravity
    public var arcEdgeInfluence: Double {
        let base = stableForce * 0.42
        return base * (gravity / 9.8)
    }

    /// Nucleus threshold exceeded → blast effect
    public var isThresholdExceeded: Bool {
        arcEdgeInfluence > stableForce * 1.618
    }

    public func reset() {
        temperature = 72.0; gravity = 9.8; pressure = 14.7
        velocity = 0.0; viscosity = 1.0; magnetism = 0.0
        electricField = 0.0; stableForce = 1.0; isNucleusActive = false
    }
}

public struct CFDTab: Identifiable {
    public var id: Int
    public var name: String { "Tab \(id + 1)" }
    public var temperature:  Double = 72.0
    public var gravity:      Double = 9.8
    public var pressure:     Double = 14.7
    public var velocity:     Double = 0.0
    public var viscosity:    Double = 1.0
    public var particleCount: Int   = 500
    public var isActive:     Bool   = false
    public var sigmaReadout: Double = 0.0
}
