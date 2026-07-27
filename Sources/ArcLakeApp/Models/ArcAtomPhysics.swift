import Foundation

// MARK: — Six-input atom physics (mass / volume / weight / density / temperature / velocity)
// Defaults are REAL physics, not placeholders: derived from the element's own
// atomicMass and density (when known), plus an Earth-standard baseline
// (9.80665 m/s² gravity, 288 K ambient — matching the tempK convention
// already used elsewhere in this codebase, e.g. EquationNode's own
// tempK: Double = 288 default). Thermal velocity comes from real kinetic
// theory (v = sqrt(3kT/m)), not an arbitrary number. Every value here is
// user-adjustable afterward — these are physically-grounded starting
// points, not fixed truths, matching "they each come with their own
// default physics based on earth atmospheric environment."
public struct ArcAtomPhysics: Codable, Equatable {
    public var massU: Double           // atomic mass units
    public var volumeAngstrom3: Double // ų
    public var weightN: Double         // newtons, under current environment gravity
    public var densityKgM3: Double
    public var temperatureK: Double
    public var velocityMS: Double      // thermal velocity, m/s

    public static let earthGravityMS2 = 9.80665
    public static let earthPressurePa = 101325.0   // = 14.696 psi
    public static let earthAmbientK   = 288.0

    private static let boltzmann = 1.380649e-23
    private static let amuToKg   = 1.66053906660e-27

    public init(element: ArcElement,
                gravityMS2: Double = ArcAtomPhysics.earthGravityMS2,
                temperatureK: Double = ArcAtomPhysics.earthAmbientK) {
        massU = element.atomicMass
        let massKg = massU * Self.amuToKg

        // Volume: use the element's own real density when known (mass /
        // density); otherwise fall back to a nucleon-count radius estimate
        // in the same style physicsPosition() already uses for atomicRadius,
        // so the fallback is at least self-consistent with existing code.
        if let d = element.density, d > 0 {
            densityKgM3 = d * 1000  // element.density is g/cm³ → kg/m³
            let volumeM3 = densityKgM3 > 0 ? massKg / densityKgM3 : 0
            volumeAngstrom3 = volumeM3 * 1e30
        } else {
            let radiusEstimateAngstrom = 0.5 + Double(element.neutrons + element.protons) * 0.01
            volumeAngstrom3 = (4.0/3.0) * .pi * pow(radiusEstimateAngstrom, 3)
            let volumeM3 = volumeAngstrom3 * 1e-30
            densityKgM3 = volumeM3 > 0 ? massKg / volumeM3 : 0
        }

        weightN = massKg * gravityMS2
        self.temperatureK = temperatureK
        velocityMS = massKg > 0 ? (3 * Self.boltzmann * temperatureK / massKg).squareRoot() : 0
    }
}
