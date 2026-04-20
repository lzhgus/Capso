import Foundation

/// An analytical closed-form damped harmonic oscillator for smooth animations.
///
/// The spring is characterised by three physical constants:
/// - **stiffness** (`k`) — restoring force per unit displacement
/// - **damping** (`c`) — resistive force proportional to velocity
/// - **mass** (`m`) — inertia of the simulated object
///
/// Given those constants the simulator derives:
/// - Natural frequency: `ω₀ = sqrt(k / m)`
/// - Damping ratio:     `ζ  = c / (2 * sqrt(k * m))`
///
/// And uses the appropriate analytical solution for each regime:
/// - `ζ < 1` → underdamped (oscillatory)
/// - `ζ ≈ 1` → critically damped (fastest non-oscillatory)
/// - `ζ > 1` → overdamped (slow exponential decay)
public struct SpringSimulator: Sendable {

    // MARK: - Result type

    public struct StepResult: Sendable {
        public var position: Double
        public var velocity: Double
    }

    // MARK: - Public properties

    public let stiffness: Double   // k
    public let damping: Double     // c
    public let mass: Double        // m

    public private(set) var currentPosition: Double
    public private(set) var currentVelocity: Double

    // MARK: - Init

    public init(stiffness: Double, damping: Double, mass: Double) {
        self.stiffness = stiffness
        self.damping   = damping
        self.mass      = mass
        self.currentPosition = 0.0
        self.currentVelocity = 0.0
    }

    // MARK: - Reset

    public mutating func reset(position: Double, velocity: Double = 0) {
        currentPosition = position
        currentVelocity = velocity
    }

    // MARK: - Step

    /// Advance the simulation by `dt` seconds toward `target`.
    ///
    /// Uses the exact analytical solution so large time steps remain stable.
    @discardableResult
    public mutating func step(toward target: Double, deltaTime dt: Double) -> StepResult {
        let position = currentPosition
        let velocity = currentVelocity
        let displacement = position - target

        // Early exit: already settled
        if abs(displacement) < 1e-10 && abs(velocity) < 1e-10 {
            currentPosition = target
            currentVelocity = 0.0
            return StepResult(position: target, velocity: 0.0)
        }

        let omega0 = (stiffness / mass).squareRoot()                    // natural frequency
        let zeta   = damping / (2.0 * (stiffness * mass).squareRoot())  // damping ratio

        let newPosition: Double
        let newVelocity: Double

        if abs(zeta - 1.0) < 1e-6 {
            // ─── Critically damped ─────────────────────────────────────────
            let e = exp(-omega0 * dt)
            let a = displacement
            let b = velocity + omega0 * displacement
            newPosition = target + e * (a + b * dt)
            // x(t)  = target + (a + b*t) * e^(-ω₀*t)
            // x'(t) = e^(-ω₀*t) * (b - ω₀*(a + b*t))
            newVelocity = e * (b - omega0 * (a + b * dt))

        } else if zeta < 1.0 {
            // ─── Underdamped (oscillatory) ─────────────────────────────────
            let omegaD = omega0 * (1.0 - zeta * zeta).squareRoot()     // damped natural frequency
            let e  = exp(-zeta * omega0 * dt)
            let a  = displacement
            let b  = (velocity + zeta * omega0 * displacement) / omegaD
            let cosT = cos(omegaD * dt)
            let sinT = sin(omegaD * dt)
            newPosition = target + e * (a * cosT + b * sinT)
            newVelocity = e * (velocity * cosT
                               - (velocity * zeta * omega0 + displacement * omega0 * omega0) / omegaD * sinT)

        } else {
            // ─── Overdamped ────────────────────────────────────────────────
            let sqrtTerm = (zeta * zeta - 1.0).squareRoot()
            let s1 = -omega0 * (zeta + sqrtTerm)
            let s2 = -omega0 * (zeta - sqrtTerm)
            let a  = (velocity - s2 * displacement) / (s1 - s2)
            let b  = displacement - a
            let e1 = exp(s1 * dt)
            let e2 = exp(s2 * dt)
            newPosition = target + a * e1 + b * e2
            newVelocity = a * s1 * e1 + b * s2 * e2
        }

        currentPosition = newPosition
        currentVelocity = newVelocity
        return StepResult(position: newPosition, velocity: newVelocity)
    }
}

// MARK: - Spring2D

/// Convenience wrapper applying independent spring simulations along X and Y.
public struct Spring2D: Sendable {
    private var springX: SpringSimulator
    private var springY: SpringSimulator

    public var x: Double { springX.currentPosition }
    public var y: Double { springY.currentPosition }

    public init(stiffness: Double, damping: Double, mass: Double) {
        springX = SpringSimulator(stiffness: stiffness, damping: damping, mass: mass)
        springY = SpringSimulator(stiffness: stiffness, damping: damping, mass: mass)
    }

    public mutating func reset(x: Double, y: Double) {
        springX.reset(position: x)
        springY.reset(position: y)
    }

    @discardableResult
    public mutating func step(
        towardX targetX: Double,
        y targetY: Double,
        deltaTime dt: Double
    ) -> (x: Double, y: Double) {
        let rx = springX.step(toward: targetX, deltaTime: dt)
        let ry = springY.step(toward: targetY, deltaTime: dt)
        return (rx.position, ry.position)
    }
}
