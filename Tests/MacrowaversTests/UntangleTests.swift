import simd
import Testing
@testable import Macrowavers

struct TangleSimulationTests {
    @Test func initialShapesHaveExpectedCrossings() {
        let config = TangleConfig()
        let trefoil = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let figureEight = TangleSimulation(config: config, positions: TangleShape.figureEight.positions(config: config))

        #expect(trefoil.crossings().count == 3)
        #expect(figureEight.crossings().count == 4)
    }

    @Test func untouchedDragonStaysTangled() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        for _ in 0..<300 { simulation.step(deltaTime: 1.0 / 60.0) }

        #expect(simulation.crossings().count == 3)
    }

    @Test func rigidTurnKeepsCrossingsAndShape() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.figureEight.positions(config: config))
        let before = simulation.crossings().count
        let firstSegment = simd_distance(simulation.positions[0], simulation.positions[1])

        simulation.rotateBody(by: .pi * 0.7, around: simulation.centroid)

        #expect(simulation.crossings().count == before)
        #expect(abs(simd_distance(simulation.positions[0], simulation.positions[1]) - firstSegment) < 1e-5)
    }

    @Test func anchoredHeadCannotBeGrabbed() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))

        #expect(!simulation.grab(0))
        #expect(simulation.grab(config.nodeCount - 1))
        #expect(simulation.isGrabbed(config.nodeCount - 1))
    }

    @Test func twoHandsCanHoldTwoNodes() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        simulation.grab(20)
        simulation.grab(config.nodeCount - 1)
        let restingHeight = simulation.positions[20].y
        let lifted = simulation.positions[20] + SIMD3(0, 0.1, 0)
        for _ in 0..<120 {
            simulation.drag(20, to: lifted)
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        // Si alza finché il limite di tensione lo permette, mentre l'altra mano tiene la coda.
        #expect(simulation.positions[20].y > restingHeight + 0.01)
        #expect(simulation.isGrabbed(config.nodeCount - 1))
    }
}

struct DragonBehaviorTests {
    @Test func fitStartsWithATurnAfterTheDelay() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let behavior = DragonBehavior()
        var elapsed: Float = 0
        while behavior.currentAction == nil && elapsed < 20 {
            behavior.update(deltaTime: 1.0 / 60.0, crossings: simulation.crossings().count,
                            userIsGrabbing: false, simulation: simulation)
            simulation.step(deltaTime: 1.0 / 60.0)
            elapsed += 1.0 / 60.0
        }

        guard case .turn = behavior.currentAction else {
            Issue.record("The first move should be a turn, got \(String(describing: behavior.currentAction))")
            return
        }
        #expect(abs(elapsed - DifficultySettings().firstWriggleDelay) < 0.1)
    }

    @Test func dragonWaitsWhileTheUserHoldsIt() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let behavior = DragonBehavior()
        for _ in 0..<(60 * 20) {
            behavior.update(deltaTime: 1.0 / 60.0, crossings: 3, userIsGrabbing: true, simulation: simulation)
        }

        #expect(!behavior.isWriggling)
        #expect(behavior.restlessness == 1)
    }
}

struct DragonFlightTests {
    @Test func flightRespectsThePlayersPersonalSpace() {
        let config = TangleConfig()
        let start = TangleShape.trefoil.positions(config: config).map { $0 + SIMD3<Float>(0, 0.75, -0.6) }
        let viewer = SIMD3<Float>(0, 1.15, 0)
        let flight = DragonFlight(start: start, segmentLength: config.segmentLength)
        var closest = Float.infinity
        for _ in 0..<(60 * 40) {
            flight.update(deltaTime: 1.0 / 60.0, viewer: viewer)
            #expect(flight.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            closest = min(closest, simd_distance(flight.positions[0], viewer))
        }

        #expect(closest > flight.settings.personalSpace * 0.9)
        #expect(flight.positions.count == config.nodeCount)
    }
}

@MainActor
struct UntangleViewModelTests {
    @Test func platformPlacementIsClamped() {
        let viewModel = UntangleViewModel()
        viewModel.setTilt(10)
        viewModel.movePlayArea(to: SIMD3(0, 5, -1))

        #expect(viewModel.placement.tilt == PlayAreaPlacement.tiltRange.upperBound)
        #expect(viewModel.placement.position.y == PlayAreaPlacement.heightRange.upperBound)
    }

    @Test func resetRestoresTheTangledDragon() {
        let viewModel = UntangleViewModel(shape: .trefoil)
        viewModel.grab(node: viewModel.config.nodeCount - 1)
        viewModel.reset()

        #expect(viewModel.crossingCount == 3)
        #expect(viewModel.userGrabbedNodes.isEmpty)
        #expect(!viewModel.isSolved && !viewModel.isFlying)
    }
}
