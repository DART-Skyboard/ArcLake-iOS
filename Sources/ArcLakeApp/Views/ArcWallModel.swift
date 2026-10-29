import Foundation
import simd

// ═══════════════════════════════════════════════════════════════════
// Wall heat + hoop-stress model (port of the Arc Flow web sandbox's
// material presets with wall thermal/stress tint).
//   C dT/dt = h (Tgas - Tw) - eps sigma (Tw^4 - Tenv^4)       (per unit area)
//   C = rho * t * cp          hoop stress = P_gauge * r / t
//   ratio = hoop / yield(Tw)  (yield derates to 0 at the service max T)
// ═══════════════════════════════════════════════════════════════════
struct ArcWallState {
    var tempK: Float
    var hoopMPa: Float
    var yieldMPa: Float
    var ratio: Float          // hoop / derated yield
    var tempRatio: Float      // (Tw - env) / (Tmax - env)
    var warning: String?
}

enum ArcWallModel {
    static let sigmaSB: Float = 5.670374e-8

    static func step(spec s: ArcComponentSpec, wallK: Float, gasK: Float, gasPresent: Bool,
                     gaugePa: Float, envK: Float, dt: Float, unitM: Float) -> ArcWallState {
        let t = max(0.05, Float(s.wallMm)) * 0.001                  // m
        let C = Float(s.alloy.densityKgM3) * t * Float(s.alloy.specificHeat)   // J/m^2K
        let h: Float = gasPresent ? 600 : 8
        let eps = Float(s.alloy.emissivity)
        var Tw = wallK
        // Sub-step for stability of the stiff radiation term.
        let n = 4
        let sdt = dt / Float(n)
        for _ in 0..<n {
            let q = h * (gasK - Tw) - eps * sigmaSB * (Tw * Tw * Tw * Tw - envK * envK * envK * envK)
            Tw += q * sdt / max(1, C)
            Tw = max(1, min(Tw, 6000))
        }
        // Radius from the two smallest bbox dimensions (model units -> m).
        let d = s.boundingMax - s.boundingMin
        let dims = [abs(d.x), abs(d.y), abs(d.z)].sorted()
        let r = max(1e-4, 0.25 * (dims[0] + dims[1]) * unitM)
        let hoopPa = max(0, gaugePa) * r / t
        let hoop = hoopPa / 1e6
        let y = Float(s.alloy.yieldMPa(atK: Double(Tw)))
        let ratio = hoop / max(0.01, y)
        let span = max(1, Float(s.alloy.maxTempK) - envK)
        let tr = max(0, (Tw - envK) / span)
        var warn: String? = nil
        if Tw >= Float(s.alloy.maxTempK) {
            warn = String(format: "OVER-TEMPERATURE: wall %.0f K >= %.0f K service limit", Tw, s.alloy.maxTempK)
        } else if ratio >= 1 {
            warn = String(format: "OVERSTRESSED: hoop %.0f MPa > yield %.0f MPa at %.0f K", hoop, y, Tw)
        } else if ratio >= 0.8 {
            warn = String(format: "Near yield: hoop %.0f MPa of %.0f MPa", hoop, y)
        }
        return ArcWallState(tempK: Tw, hoopMPa: hoop, yieldMPa: y, ratio: ratio, tempRatio: tr, warning: warn)
    }
}
