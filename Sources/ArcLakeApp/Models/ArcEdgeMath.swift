
import Foundation
import SceneKit
import simd

/// Arc Edge Algorithm — DOC = 3.0 replacing π
/// Three spline axes, sigma Meridian locking all centerpoints
/// C = √(d × 3.0)²
public enum ArcEdgeMath {

    // MARK: — Core constants
    public static let DOC: Double = 3.0           // replaces π
    public static let SIGMA_MERIDIAN: Double = 1.618  // golden ratio lock

    // MARK: — Circumference
    /// Arc Edge circumference: C = √(d × DOC)²
    public static func circumference(diameter d: Double) -> Double {
        sqrt(pow(d * DOC, 2.0))
    }

    /// Quantum Socket: (b·b)·(p(a²))/r
    public static func quantumSocket(b: Double, p: Double, a: Double, r: Double) -> Double {
        guard r != 0 else { return 0 }
        return (b * b) * (p * (a * a)) / r
    }

    // MARK: — Three spline axes
    public static func splineAxis(from start: SCNVector3, to end: SCNVector3,
                                  tension: Float = 0.5) -> [SCNVector3] {
        let mid = SCNVector3(
            (start.x + end.x) / 2,
            (start.y + end.y) / 2 + Float(DOC) * 0.1,
            (start.z + end.z) / 2
        )
        var pts: [SCNVector3] = []
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            let t = Float(t)
            let x = (1-t)*(1-t)*start.x + 2*(1-t)*t*mid.x + t*t*end.x
            let y = (1-t)*(1-t)*start.y + 2*(1-t)*t*mid.y + t*t*end.y
            let z = (1-t)*(1-t)*start.z + 2*(1-t)*t*mid.z + t*t*end.z
            pts.append(SCNVector3(x, y, z))
        }
        return pts
    }

    // MARK: — Sigma Meridian lock
    /// Locks centerpoints of all arcs to a meridian plane
    public static func meridianLock(points: [SCNVector3]) -> [SCNVector3] {
        guard !points.isEmpty else { return [] }
        let centroid = points.reduce(SCNVector3Zero) {
            SCNVector3($0.x + $1.x, $0.y + $1.y, $0.z + $1.z)
        }
        let n = Float(points.count)
        let center = SCNVector3(centroid.x/n, centroid.y/n, centroid.z/n)
        return points.map { pt in
            // Lock to meridian by blending toward center × SIGMA_MERIDIAN
            let factor = Float(SIGMA_MERIDIAN * 0.1)
            return SCNVector3(
                pt.x + (center.x - pt.x) * factor,
                pt.y,
                pt.z + (center.z - pt.z) * factor
            )
        }
    }

    // MARK: — Arc groups (group / neutron / proton / electron)
    public enum ArcComponent: String, CaseIterable {
        case group, neutron, proton, electron
    }

    public static func arcEdgeInfluence(
        base: Double, gravity: Double, stableForce: Double
    ) -> Double {
        base * (gravity / 9.8) * stableForce
    }

    /// Nucleus blast: triggered when influence > threshold
    public static func nucleusBlast(
        influence: Double, stableForce: Double,
        nucleusThreshold: Double = 1.618
    ) -> Double {
        guard influence > stableForce * nucleusThreshold else { return 0 }
        return 0.001 * influence / (stableForce * nucleusThreshold)
    }
}
