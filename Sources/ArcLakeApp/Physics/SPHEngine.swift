
import Foundation
import SceneKit
import simd

/// SPH-inspired fluid dynamics engine — matches ArcLake web CFD
/// Real mathematical computation, never preset animation
public final class SPHEngine: @unchecked Sendable {

    // MARK: — Particle
    public struct Particle {
        public var position: SIMD3<Float>
        public var velocity: SIMD3<Float>
        public var density:  Float = 1.0
        public var pressure: Float = 0.0
        public var mass:     Float = 1.0
        public var element:  Int   = 1       // atomic number
        public var color:    UIColor = .cyan
        public var id:       UUID = UUID()
    }

    // MARK: — State
    private(set) var particles: [Particle] = []
    private var physicsState: PhysicsState

    // SPH constants
    private let h: Float         = 0.3    // smoothing length
    private let restDensity: Float = 1000.0
    private let gasConstant: Float = 2000.0
    private let viscosityCoef: Float = 250.0
    private let timeStep: Float   = 0.016

    // Fibonacci sphere for nucleus packing
    private var fibonacciPoints: [SIMD3<Float>] = []

    public init(physicsState: PhysicsState) {
        self.physicsState = physicsState
        generateFibonacciSphere(n: 500)
    }

    // MARK: — Fibonacci sphere nucleus packing
    private func generateFibonacciSphere(n: Int) {
        fibonacciPoints = (0..<n).map { i in
            let theta = Float.pi * (3.0 - sqrt(5.0)) * Float(i)
            let y = 1.0 - (Float(i) / Float(n - 1)) * 2.0
            let radius = sqrt(1.0 - y * y)
            return SIMD3<Float>(cos(theta) * radius, y, sin(theta) * radius)
        }
    }

    // MARK: — Initialize particles for element
    public func initializeForElement(_ element: ArcElement, count: Int = 500) {
        let n = min(count, fibonacciPoints.count)
        particles = fibonacciPoints.prefix(n).map { pt in
            Particle(
                position: pt * 2.0,
                velocity: SIMD3<Float>(0, 0, 0),
                mass: Float(element.atomicMass) * 0.001,
                element: element.protons,
                color: element.category.color
            )
        }
    }

    // MARK: — Physics tick
    public func tick() {
        guard !particles.isEmpty else { return }
        computeDensityPressure()
        computeForces()
        integrate()
    }

    private func computeDensityPressure() {
        for i in 0..<particles.count {
            var density: Float = 0
            for j in 0..<particles.count {
                let r = simd_distance(particles[i].position, particles[j].position)
                if r < h {
                    density += particles[j].mass * poly6Kernel(r: r, h: h)
                }
            }
            particles[i].density = max(density, 0.001)
            particles[i].pressure = gasConstant * (particles[i].density - restDensity)
        }
    }

    private func computeForces() {
        let g = SIMD3<Float>(0, -Float(physicsState.gravity), 0)
        for i in 0..<particles.count {
            var force = SIMD3<Float>(0, 0, 0)
            for j in 0..<particles.count where i != j {
                let diff = particles[i].position - particles[j].position
                let r = simd_length(diff)
                guard r > 0.001 && r < h else { continue }
                let dir = diff / r
                // Pressure force
                let pForce = -particles[j].mass *
                    (particles[i].pressure + particles[j].pressure) /
                    (2.0 * particles[j].density) *
                    spikyGradient(r: r, h: h)
                force += pForce * dir
                // Viscosity force
                let vForce = viscosityCoef * particles[j].mass *
                    (particles[j].velocity - particles[i].velocity) /
                    particles[j].density *
                    viscosityLaplacian(r: r, h: h)
                force += vForce
            }
            // Gravity + environment
            force += g * particles[i].mass
            particles[i].velocity += force / particles[i].density * timeStep
        }
    }

    private func integrate() {
        let bounds: Float = 3.0
        for i in 0..<particles.count {
            particles[i].position += particles[i].velocity * timeStep
            // Boundary bounce
            for axis in 0..<3 {
                if particles[i].position[axis] < -bounds {
                    particles[i].position[axis] = -bounds
                    particles[i].velocity[axis] *= -0.7
                }
                if particles[i].position[axis] > bounds {
                    particles[i].position[axis] = bounds
                    particles[i].velocity[axis] *= -0.7
                }
            }
        }
    }

    // MARK: — SPH kernels
    private func poly6Kernel(r: Float, h: Float) -> Float {
        guard r <= h else { return 0 }
        let q = h * h - r * r
        return (315.0 / (64.0 * Float.pi * pow(h, 9.0))) * pow(q, 3.0)
    }

    private func spikyGradient(r: Float, h: Float) -> Float {
        guard r > 0 && r <= h else { return 0 }
        return -(45.0 / (Float.pi * pow(h, 6.0))) * pow(h - r, 2.0)
    }

    private func viscosityLaplacian(r: Float, h: Float) -> Float {
        guard r <= h else { return 0 }
        return (45.0 / (Float.pi * pow(h, 6.0))) * (h - r)
    }
}
