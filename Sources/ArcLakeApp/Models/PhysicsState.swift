
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

    // Per-scene-tab environment physics (grows with scene tabs)
    // Index matches labVM.activeTabIndex — auto-synced by ArcCFDView
    @Published public var tabs: [CFDTab] = (0..<10).map { CFDTab(id: $0) }
    @Published public var activeTabIndex: Int = 0

    public var activeTab: CFDTab {
        get { tabs[safe: activeTabIndex] ?? CFDTab(id: activeTabIndex) }
        set {
            while tabs.count <= activeTabIndex { tabs.append(CFDTab(id: tabs.count)) }
            tabs[activeTabIndex] = newValue
        }
    }

    /// Convenience accessors for the active tab
    public var temperature: Double {
        get { activeTab.temperature } set { activeTab.temperature = newValue }
    }
    public var gravity: Double {
        get { activeTab.gravity } set { activeTab.gravity = newValue }
    }
    public var pressure: Double {
        get { activeTab.pressure } set { activeTab.pressure = newValue }
    }
    public var viscosity: Double {
        get { activeTab.viscosity } set { activeTab.viscosity = newValue }
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
    // Standard atmosphere defaults
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

    // BTU / thermal environment (from radicaldeepscale.com/btu.html)
    public var ambientTempK: Double  { (temperature - 32) * 5/9 + 273.15 }
    public var pressurePa:   Double  { pressure * 6894.76 }

    // Preset environments
    static func earthSea()    -> CFDTab { var t=CFDTab(id:0); return t }
    static func mars()        -> CFDTab {
        var t=CFDTab(id:0); t.temperature = -80; t.pressure = 0.087
        t.gravity = 3.72; t.viscosity = 0.01; return t }
    static func venus()       -> CFDTab {
        var t=CFDTab(id:0); t.temperature = 867; t.pressure = 1334
        t.gravity = 8.87; t.viscosity = 28.5; return t }
    static func lowEarthOrbit() -> CFDTab {
        var t=CFDTab(id:0); t.temperature = -450; t.pressure = 0
        t.gravity = 0; t.viscosity = 0; return t }
}

// Safe subscript for arrays
extension Array {
    subscript(safe i: Index) -> Element? { i>=0 && i<count ? self[i] : nil }
}

