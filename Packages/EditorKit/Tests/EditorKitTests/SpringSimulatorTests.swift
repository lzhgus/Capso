import Testing
@testable import EditorKit

@Suite("SpringSimulator")
struct SpringSimulatorTests {

    // MARK: - SpringSimulator tests

    @Test("Spring at rest stays at target")
    func springAtRestStaysAtTarget() {
        var spring = SpringSimulator(stiffness: 100, damping: 10, mass: 1)
        spring.reset(position: 5.0)
        let result = spring.step(toward: 5.0, deltaTime: 1.0 / 60.0)
        #expect(abs(result.position - 5.0) < 1e-9)
        #expect(abs(result.velocity) < 1e-9)
    }

    @Test("Spring moves toward target")
    func springMovesTowardTarget() {
        var spring = SpringSimulator(stiffness: 100, damping: 10, mass: 1)
        spring.reset(position: 0.0)
        let result = spring.step(toward: 1.0, deltaTime: 0.1)
        // Should have moved from 0 toward 1 — position in (0, 1)
        #expect(result.position > 0.0)
        #expect(result.position < 1.0)
    }

    @Test("Spring converges to target after many steps")
    func springConvergesAfterManySteps() {
        var spring = SpringSimulator(stiffness: 100, damping: 20, mass: 1)
        spring.reset(position: 0.0)
        for _ in 0..<100 {
            spring.step(toward: 1.0, deltaTime: 1.0 / 60.0)
        }
        #expect(abs(spring.currentPosition - 1.0) < 0.01)
    }

    @Test("Stiff spring reaches target faster")
    func stiffSpringReachesTargetFaster() {
        var stiff = SpringSimulator(stiffness: 400, damping: 30, mass: 1)
        var soft  = SpringSimulator(stiffness: 50,  damping: 10, mass: 2)
        stiff.reset(position: 0.0)
        soft.reset(position: 0.0)
        for _ in 0..<12 {
            stiff.step(toward: 1.0, deltaTime: 1.0 / 60.0)
            soft.step(toward: 1.0,  deltaTime: 1.0 / 60.0)
        }
        // The stiffer spring should be closer to 1.0 (higher position)
        #expect(stiff.currentPosition > soft.currentPosition)
    }

    @Test("Underdamped spring overshoots")
    func underdampedSpringOvershoots() {
        // ζ = 5 / (2 * sqrt(200 * 1)) ≈ 0.177 → clearly underdamped
        var spring = SpringSimulator(stiffness: 200, damping: 5, mass: 1)
        spring.reset(position: 0.0)
        var maxPosition = 0.0
        for _ in 0..<200 {
            let result = spring.step(toward: 1.0, deltaTime: 1.0 / 60.0)
            if result.position > maxPosition {
                maxPosition = result.position
            }
        }
        // Underdamped spring must overshoot the target of 1.0
        #expect(maxPosition > 1.0)
    }

    @Test("Spring 2D converges both dimensions")
    func spring2DConvergesBothDimensions() {
        var spring = Spring2D(stiffness: 100, damping: 20, mass: 1)
        spring.reset(x: 0.0, y: 0.0)
        for _ in 0..<100 {
            spring.step(towardX: 1.0, y: 0.5, deltaTime: 1.0 / 60.0)
        }
        #expect(abs(spring.x - 1.0) < 0.01)
        #expect(abs(spring.y - 0.5) < 0.01)
    }

    @Test("Spring reset clears state")
    func springResetClearsState() {
        var spring = SpringSimulator(stiffness: 100, damping: 10, mass: 1)
        spring.reset(position: 0.0)
        // Simulate toward 1.0 to build up velocity
        for _ in 0..<10 {
            spring.step(toward: 1.0, deltaTime: 1.0 / 60.0)
        }
        // Now reset to 3.0 and immediately step toward 3.0
        spring.reset(position: 3.0, velocity: 0.0)
        let result = spring.step(toward: 3.0, deltaTime: 1.0 / 60.0)
        // Should snap to ≈3.0 (at rest at target)
        #expect(abs(result.position - 3.0) < 1e-9)
        #expect(abs(result.velocity) < 1e-9)
    }
}
