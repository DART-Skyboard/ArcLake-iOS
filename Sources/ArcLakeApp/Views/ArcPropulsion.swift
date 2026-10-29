import Foundation
import simd

// ═══════════════════════════════════════════════════════════════════
// Rocket exhaust presets + nozzle physics (port of the Arc Flow web
// sandbox propulsion presets):
//   v_e = sqrt( 2 g/(g-1) R Tc (1 - (pe/pc)^((g-1)/g)) )
// Exit Mach from the area ratio (isentropic), plume regime from pe vs the
// ambient pressure: underexpanded barrel, overexpanded pinch, vacuum fan.
// ═══════════════════════════════════════════════════════════════════
public enum ArcPropulsion: String, CaseIterable, Identifiable {
    case bell = "Supersonic bell nozzle"
    case thruster = "Thruster"
    case seaLevel = "Sea-level engine"
    case vacuumAtSL = "Vacuum engine (sea level)"
    case vacuum = "Vacuum engine (in vacuum)"
    case legacy = "Legacy exhaust"
    public var id: String { rawValue }

    struct Params { var pc: Float; var Tc: Float; var gamma: Float; var molarMass: Float; var areaRatio: Float; var ambientPa: Float? }
    var params: Params {
        switch self {
        case .bell:       return Params(pc: 7.0e6, Tc: 3500, gamma: 1.20, molarMass: 22, areaRatio: 25, ambientPa: nil)
        case .thruster:   return Params(pc: 0.5e6, Tc: 1200, gamma: 1.30, molarMass: 18, areaRatio: 40, ambientPa: nil)
        case .seaLevel:   return Params(pc: 10.0e6, Tc: 3400, gamma: 1.20, molarMass: 21, areaRatio: 6, ambientPa: nil)
        case .vacuumAtSL: return Params(pc: 7.0e6, Tc: 3500, gamma: 1.20, molarMass: 22, areaRatio: 80, ambientPa: 101325)
        case .vacuum:     return Params(pc: 7.0e6, Tc: 3500, gamma: 1.20, molarMass: 22, areaRatio: 80, ambientPa: 100)
        case .legacy:     return Params(pc: 0, Tc: 0, gamma: 1.2, molarMass: 22, areaRatio: 1, ambientPa: nil)
        }
    }
}

struct ArcPlumeParams {
    enum Regime: String { case ideal = "ideally expanded", barrel = "underexpanded barrel",
                          pinch = "overexpanded pinch", fan = "vacuum fan" }
    var vExit: Float        // m/s
    var mach: Float
    var pe: Float           // Pa
    var Te: Float           // K
    var regime: Regime
    var halfAngle: Float    // rad (negative = pinch)
    var diamondSpacing: Float   // in exit diameters (0 = none)
    var vScaleRel: Float    // scene velocity scale relative to the base jet speed
    var summary: String
}

enum ArcNozzle {
    /// A/A* for a given Mach number.
    static func areaRatio(mach m: Float, gamma g: Float) -> Float {
        let t = (2 / (g + 1)) * (1 + (g - 1) / 2 * m * m)
        return (1 / m) * pow(t, (g + 1) / (2 * (g - 1)))
    }
    /// Supersonic exit Mach for an area ratio (bisection).
    static func exitMach(areaRatio e: Float, gamma g: Float) -> Float {
        var lo: Float = 1.0001, hi: Float = 15
        for _ in 0..<60 {
            let mid = 0.5 * (lo + hi)
            if areaRatio(mach: mid, gamma: g) < e { lo = mid } else { hi = mid }
        }
        return 0.5 * (lo + hi)
    }

    static func plume(_ preset: ArcPropulsion, ambientPa pa0: Float) -> ArcPlumeParams? {
        guard preset != .legacy else { return nil }
        let p = preset.params
        let pa = max(1, p.ambientPa ?? pa0)
        let g = p.gamma
        let R = 8314.46 / p.molarMass
        let me = exitMach(areaRatio: p.areaRatio, gamma: g)
        let tfac = 1 + (g - 1) / 2 * me * me
        let pe = p.pc * pow(tfac, -g / (g - 1))
        let Te = p.Tc / tfac
        let pr = pe / p.pc
        let ve = sqrt(max(0, 2 * g / (g - 1) * R * p.Tc * (1 - pow(pr, (g - 1) / g))))
        let ratio = pe / pa
        let regime: ArcPlumeParams.Regime
        var half: Float, diamonds: Float
        if pa < 2000 {
            regime = .fan; half = 0.70; diamonds = 0                     // free expansion fan
        } else if ratio > 1.08 {
            regime = .barrel; half = min(0.5, 0.06 + 0.12 * log(ratio)); diamonds = 1.0 + 0.4 * sqrt(max(0, me * me - 1)) * 0.25
        } else if ratio < 0.92 {
            regime = .pinch; half = -min(0.2, 0.04 + 0.06 * log(1 / max(0.05, ratio))); diamonds = 0.9
        } else {
            regime = .ideal; half = 0.05; diamonds = 0
        }
        let rel = min(1.4, max(0.35, ve / 3600 * 1.4))
        let sum = String(format: "Me %.2f · ve %.0f m/s · pe %.0f kPa · Te %.0f K · %@",
                         me, ve, pe / 1000, Te, regime.rawValue)
        return ArcPlumeParams(vExit: ve, mach: me, pe: pe, Te: Te, regime: regime, halfAngle: half,
                              diamondSpacing: diamonds, vScaleRel: rel, summary: sum)
    }
}
