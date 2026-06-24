import Foundation
import Combine

/// Environment physics — mirrors web app's scenePhysicsState
public final class PhysicsState: ObservableObject, @unchecked Sendable {

    // Global defaults (used by atoms/mol canvas, Arc Edge math)
    @Published public var temperature:    Double = 72.0    // °F
    @Published public var gravity:        Double = 9.8     // m/s²
    @Published public var pressure:       Double = 14.7    // psi
    @Published public var velocity:       Double = 0.0     // m/s
    @Published public var viscosity:      Double = 1.0     // cP
    @Published public var magnetism:      Double = 0.0     // T
    @Published public var electricField:  Double = 0.0     // V/m
    @Published public var stableForce:    Double = 1.0
    @Published public var isNucleusActive: Bool  = false

    // Per-scene-tab environment physics
    @Published public var tabs: [CFDTab] = (0..<10).map { CFDTab(id: $0) }
    @Published public var activeTabIndex: Int = 0

    public var activeTab: CFDTab {
        get { activeTabIndex < tabs.count ? tabs[activeTabIndex] : CFDTab(id: activeTabIndex) }
        set {
            while tabs.count <= activeTabIndex { tabs.append(CFDTab(id: tabs.count)) }
            tabs[activeTabIndex] = newValue
            // Sync global properties with active tab for legacy code
            temperature = newValue.temperature
            gravity     = newValue.gravity
            pressure    = newValue.pressure
            viscosity   = newValue.viscosity
            velocity    = newValue.velocity
        }
    }

    public var arcEdgeInfluence: Double { stableForce * 0.42 * (gravity / 9.8) }
    public var isThresholdExceeded: Bool { arcEdgeInfluence > stableForce * 1.618 }

    public func reset() {
        temperature = 72.0; gravity = 9.8; pressure = 14.7
        velocity = 0.0; viscosity = 1.0; magnetism = 0.0
        electricField = 0.0; stableForce = 1.0; isNucleusActive = false
        if activeTabIndex < tabs.count { tabs[activeTabIndex] = CFDTab(id: activeTabIndex) }
    }
}

public struct CFDTab: Identifiable {
    public var id: Int
    public var name: String { "Tab \(id + 1)" }
    public var temperature:  Double = 72.0    // °F
    public var gravity:      Double = 9.8     // m/s²
    public var pressure:     Double = 14.7    // psi (sea level)
    public var velocity:     Double = 0.0     // m/s wind
    public var viscosity:    Double = 1.0     // cP
    public var humidity:     Double = 50.0    // %
    public var altitude:     Double = 0.0     // m ASL
    public var particleCount: Int   = 500
    public var isActive:     Bool   = false
    public var sigmaReadout: Double = 0.0

    // BTU derived values (radicaldeepscale.com/btu.html)
    public var ambientTempK: Double { (temperature - 32) * 5/9 + 273.15 }
    public var pressurePa:   Double { pressure * 6894.76 }
}
