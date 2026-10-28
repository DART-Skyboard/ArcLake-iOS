import Foundation
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcGeometricClassifier — task #41: generic container-vs-pipe
// detection from pure geometry, so ANY imported GLB (not just the one
// bundled Combustion_flow.glb, whose mesh names are hand-mapped in
// ArcCombustionFlow.componentRoles) gets a sensible auto-classification
// of which sub-meshes are sealed containers/tanks vs. pipes/channels
// connecting them.
//
// Approach (per the task brief):
//   1. Per sub-mesh bounding box → aspect-ratio heuristic. A long,
//      thin shape (longest dimension notably larger than the other
//      two) is a PIPE/CHANNEL. A more cuboid/spherical/compact shape
//      with meaningful enclosed volume is a CONTAINER/TANK.
//   2. For each pipe, find the nearest container to each of its two
//      long-axis extremities (the end regions) — that becomes the
//      inferred connection at that end, informing flow direction
//      container A -> pipe -> container B.
//
// This is deliberately a simple, explainable heuristic (not a full
// mesh-adjacency/graph solve) — it only needs to be "right enough" to
// drive sensible defaults (which tanks a channel feeds, what role badge
// to show) for arbitrary mechanical geometry; a user can always
// override the inferred role in ArcComponentConfigView.
//
// Scanned component roles that WERE found in the hardcoded
// Combustion_flow.glb dictionary (ArcCombustionFlow.componentRoles)
// bypass this entirely — see scanComponentSpecs, which only calls this
// classifier for components with no dictionary entry. That keeps the
// one bundled demo asset's existing hand-tuned behavior unchanged while
// making every OTHER imported model go through real classification.
// ═══════════════════════════════════════════════════════════════════

public enum ArcGeometricClassifier {

    public enum Kind: String, Codable {
        case container   // sealed tank/chamber — compact, large enclosed volume
        case pipe        // long thin channel/duct connecting containers
        case unknown      // degenerate geometry (near-zero volume) — can't classify
    }

    /// Minimal shape info needed to classify one sub-mesh, in world space.
    public struct ShapeInfo {
        public var nodeName: String
        public var boundingMin: SIMD3<Float>
        public var boundingMax: SIMD3<Float>
        public init(nodeName: String, boundingMin: SIMD3<Float>, boundingMax: SIMD3<Float>) {
            self.nodeName = nodeName; self.boundingMin = boundingMin; self.boundingMax = boundingMax
        }
        var size: SIMD3<Float> { boundingMax - boundingMin }
        var center: SIMD3<Float> { (boundingMin + boundingMax) * 0.5 }
        var volume: Float { abs(size.x * size.y * size.z) }
        /// Longest axis index (0=x,1=y,2=z) and its extent.
        var longestAxis: (index: Int, extent: Float) {
            let s = [size.x, size.y, size.z]
            var bi = 0; for i in 1..<3 where s[i] > s[bi] { bi = i }
            return (bi, s[bi])
        }
        /// The two smaller cross-section dimensions (everything but the
        /// longest axis).
        var crossSectionDims: (Float, Float) {
            let s = [size.x, size.y, size.z]
            let (li, _) = longestAxis
            let others = (0..<3).filter { $0 != li }.map { s[$0] }
            return (others[0], others[1])
        }
    }

    public struct ClassificationResult {
        public var kind: Kind
        /// For a pipe: the world-space position of each of its two
        /// long-axis extremities (end caps), used to find nearby
        /// containers. Empty for a container.
        public var pipeEnds: [SIMD3<Float>] = []
    }

    /// A long thin shape whose longest dimension is at least this many
    /// times its (average) cross-section dimension classifies as a pipe.
    /// Chosen per the task brief's "length > 3-4x the smaller
    /// cross-section dimensions" guidance — 3.2 sits in that band,
    /// slightly permissive so genuinely pipe-like geometry (nozzles,
    /// ducts) that isn't perfectly uniform still classifies correctly.
    public static let pipeAspectRatioThreshold: Float = 3.2

    /// Below this volume (world-space units³) a shape is too degenerate
    /// to classify meaningfully either way — treated as unknown rather
    /// than guessed, so callers can fall back to a safe default instead
    /// of acting on noise.
    public static let minMeaningfulVolume: Float = 1e-5

    public static func classify(_ shape: ShapeInfo) -> ClassificationResult {
        guard shape.volume > minMeaningfulVolume else {
            return ClassificationResult(kind: .unknown)
        }
        let (longIdx, longExtent) = shape.longestAxis
        let (c0, c1) = shape.crossSectionDims
        let avgCross = max(1e-6, (c0 + c1) * 0.5)
        let aspect = longExtent / avgCross

        if aspect >= pipeAspectRatioThreshold {
            // Pipe: its two extremities, along the long axis, offset
            // slightly inward from the absolute bbox corner (the very
            // tip of a pipe is often flush against — or even slightly
            // overlapping — its container, so sampling a touch inward
            // gives a more representative "this is the pipe's end
            // region" point for nearest-container search).
            var dir = SIMD3<Float>.zero
            switch longIdx { case 0: dir = SIMD3(1,0,0); case 1: dir = SIMD3(0,1,0); default: dir = SIMD3(0,0,1) }
            let center = shape.center
            let halfLen = longExtent * 0.5
            let inset = min(halfLen * 0.3, avgCross)
            let endA = center + dir * (halfLen - inset)
            let endB = center - dir * (halfLen - inset)
            return ClassificationResult(kind: .pipe, pipeEnds: [endA, endB])
        } else {
            return ClassificationResult(kind: .container)
        }
    }

    /// For a pipe's two end points, find the nearest CONTAINER (by
    /// closest point on/near its bounding box, not just center distance,
    /// so a large tank whose center is far away but whose wall is right
    /// at the pipe's tip is still picked correctly) among `containers`.
    /// Returns container node names, same order as `pipeEnds`, nearest
    /// match per end — nil at an index if no container is within
    /// `maxSearchDistance` of that end.
    public static func nearestContainers(toEnds pipeEnds: [SIMD3<Float>],
                                          containers: [ShapeInfo],
                                          maxSearchDistance: Float) -> [String?] {
        guard !containers.isEmpty else { return pipeEnds.map { _ in nil } }
        return pipeEnds.map { end in
            var bestName: String? = nil
            var bestDist = Float.infinity
            for c in containers {
                let d = distanceToAABB(point: end, boxMin: c.boundingMin, boxMax: c.boundingMax)
                if d < bestDist { bestDist = d; bestName = c.nodeName }
            }
            return bestDist <= maxSearchDistance ? bestName : nil
        }
    }

    /// Distance from a point to the nearest surface/corner of an
    /// axis-aligned box (0 if the point is inside/on it).
    private static func distanceToAABB(point p: SIMD3<Float>, boxMin: SIMD3<Float>, boxMax: SIMD3<Float>) -> Float {
        let dx = max(boxMin.x - p.x, 0, p.x - boxMax.x)
        let dy = max(boxMin.y - p.y, 0, p.y - boxMax.y)
        let dz = max(boxMin.z - p.z, 0, p.z - boxMax.z)
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
}
