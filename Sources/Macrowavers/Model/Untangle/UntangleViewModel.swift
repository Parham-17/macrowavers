import Foundation
import Observation
import simd

/// ViewModel del minigioco "sgroviglia il drago".
/// Espone alle View lo stato da mostrare e le azioni dell'utente; non conosce RealityKit né SwiftUI.
@MainActor
@Observable
final class UntangleViewModel {
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    // MARK: - Stato per le View

    var immersiveSpaceState = ImmersiveSpaceState.closed
    private(set) var crossingCount = 0
    private(set) var isSolved = false
    private(set) var mood = DragonMood.calm
    /// 0...1: il drago sta per dimenarsi.
    private(set) var restlessness: Float = 0
    /// 0...1: quanto è teso il corpo mentre l'utente tira.
    private(set) var strain: Float = 0
    private(set) var placement = PlayAreaPlacement.seated
    /// Movimento in corso durante un attacco d'ira (nil = nessuno).
    private(set) var action: DragonAction?
    /// Sgrovigliato, il drago ha preso il volo nella stanza.
    private(set) var isFlying = false

    // MARK: - Model

    @ObservationIgnored private(set) var simulation: TangleSimulation
    @ObservationIgnored let shape: TangleShape
    @ObservationIgnored private let behavior: DragonBehavior
    /// Nodi tenuti dall'utente (uno per mano).
    @ObservationIgnored private(set) var userGrabbedNodes: Set<Int> = []
    /// Ordine di presa: la testa guarda il primo nodo afferrato.
    @ObservationIgnored private var grabOrder: [Int] = []
    @ObservationIgnored private var untangledTime: Float = 0
    /// Il drago deve restare libero per un attimo, a corpo rilasciato, prima di dichiarare la vittoria.
    @ObservationIgnored private let solveDelay: Float = 0.6
    /// Punti degli incroci, aggiornati ogni frame (non osservati: li legge solo RealityKit).
    @ObservationIgnored private(set) var crossingPoints: [SIMD3<Float>] = []
    /// Avanzamento (0...1) di `action`, aggiornato ogni frame: lo legge solo RealityKit.
    var actionProgress: Float { behavior.actionProgress }
    /// Tempo di gioco, per le animazioni.
    @ObservationIgnored private(set) var time: Float = 0
    /// Volo libero dopo la vittoria (spazio della scena).
    @ObservationIgnored private var flight: DragonFlight?
    @ObservationIgnored private var freeTime: Float = 0
    /// Secondi di festa sulla piattaforma prima di decollare.
    @ObservationIgnored private let takeoffDelay: Float = 1.5
    /// Da spazio del drago (piattaforma) a spazio della scena, aggiornata ogni frame.
    @ObservationIgnored private var worldFromLocal = matrix_identity_float4x4

    init(shape: TangleShape = .trefoil,
         config: TangleConfig = TangleConfig(),
         difficulty: DifficultySettings = DifficultySettings()) {
        self.shape = shape
        simulation = TangleSimulation(config: config, positions: shape.positions(config: config))
        behavior = DragonBehavior(settings: difficulty)
        refreshCrossings()
    }

    var config: TangleConfig { simulation.config }
    /// Posizioni della simulazione (il puzzle), nello spazio del drago.
    var nodePositions: [SIMD3<Float>] { simulation.positions }
    /// Posizioni da disegnare, nello spazio del drago: la simulazione o, in volo, il volo.
    var displayPositions: [SIMD3<Float>] {
        guard let flight else { return simulation.positions }
        let localFromWorld = worldFromLocal.inverse
        return flight.positions.map { Self.transform($0, by: localFromWorld) }
    }
    var flightManeuver: DragonFlight.Maneuver? { flight?.maneuver }
    var flightProgress: Float { flight?.maneuverProgress ?? 0 }
    /// Velocità della testa in volo, nello spazio del drago.
    var flightVelocity: SIMD3<Float> {
        guard let flight else { return .zero }
        let localFromWorld = worldFromLocal.inverse
        let direction = localFromWorld * SIMD4(flight.velocity, 0)
        return SIMD3(direction.x, direction.y, direction.z)
    }
    /// Nodo trascinato dall'utente (non dal drago) che la testa guarda.
    var lookedAtNodeIndex: Int? { grabOrder.first }

    // MARK: - Azioni sul drago

    func reset() {
        simulation = TangleSimulation(config: config, positions: shape.positions(config: config))
        behavior.reset()
        userGrabbedNodes = []
        grabOrder = []
        isSolved = false
        untangledTime = 0
        restlessness = 0
        flight = nil
        isFlying = false
        freeTime = 0
        refreshCrossings()
        refreshMood()
    }

    /// Si può chiamare più volte con nodi diversi: ogni mano tiene il proprio nodo.
    func grab(node index: Int) {
        guard !isSolved, !userGrabbedNodes.contains(index) else { return }
        // Se il drago si sta dimenando, l'utente ha la precedenza.
        behavior.interrupt(simulation)
        guard simulation.grab(index) else { return }
        userGrabbedNodes.insert(index)
        grabOrder.append(index)
    }

    /// `point` è nello spazio locale del drago (il piano su cui giace è y = 0, y > 0 è sopra).
    func drag(node index: Int, to point: SIMD3<Float>) {
        guard userGrabbedNodes.contains(index) else { return }
        simulation.drag(index, to: point)
    }

    func release(node index: Int) {
        guard userGrabbedNodes.remove(index) != nil else { return }
        simulation.release(index)
        grabOrder.removeAll { $0 == index }
    }

    // MARK: - Azioni sulla piattaforma

    func movePlayArea(to position: SIMD3<Float>) {
        var position = position
        position.y = min(max(position.y, PlayAreaPlacement.heightRange.lowerBound), PlayAreaPlacement.heightRange.upperBound)
        placement.position = position
    }

    func rotatePlayArea(yaw: Float) {
        placement.yaw = yaw
    }

    func setTilt(_ tilt: Float) {
        placement.tilt = min(max(tilt, PlayAreaPlacement.tiltRange.lowerBound), PlayAreaPlacement.tiltRange.upperBound)
    }

    func resetPlacement() {
        placement = .seated
    }

    // MARK: - Ciclo di gioco

    /// Chiamato ogni frame dal `DragonBodySystem`.
    /// - Parameters:
    ///   - viewer: occhi dell'utente nello spazio della scena (il drago in volo gli gira attorno).
    ///   - worldFromLocal: trasformazione dallo spazio del drago a quello della scena.
    func update(deltaTime: Float, viewer: SIMD3<Float>, worldFromLocal: float4x4) {
        time += deltaTime
        self.worldFromLocal = worldFromLocal

        if isSolved {
            updateFreedom(deltaTime: deltaTime, viewer: viewer)
            return
        }

        if !isSolved {
            behavior.update(deltaTime: deltaTime, crossings: crossingCount,
                            userIsGrabbing: !userGrabbedNodes.isEmpty, simulation: simulation)
        }
        simulation.step(deltaTime: deltaTime)
        refreshCrossings()

        let newStrain = max(0, min(1, (simulation.tension - 1) / (config.maxTension - 1)))
        if abs(newStrain - strain) > 0.05 || (newStrain == 0 && strain != 0) { strain = newStrain }
        if abs(behavior.restlessness - restlessness) > 0.02 || behavior.restlessness == 0 && restlessness != 0 {
            restlessness = behavior.restlessness
        }

        if !isSolved {
            if crossingCount == 0 && !simulation.hasGrabs {
                untangledTime += deltaTime
                if untangledTime >= solveDelay { isSolved = true }
            } else {
                untangledTime = 0
            }
        }
        refreshMood()
    }

    /// Dopo la vittoria: breve festa sulla piattaforma, poi decollo e volo libero nella stanza.
    private func updateFreedom(deltaTime: Float, viewer: SIMD3<Float>) {
        freeTime += deltaTime
        if let flight {
            flight.update(deltaTime: deltaTime, viewer: viewer)
            return
        }
        simulation.step(deltaTime: deltaTime)
        if freeTime >= takeoffDelay {
            let start = simulation.positions.map { Self.transform($0, by: worldFromLocal) }
            flight = DragonFlight(start: start, segmentLength: config.segmentLength)
            isFlying = true
        }
    }

    private static func transform(_ point: SIMD3<Float>, by matrix: float4x4) -> SIMD3<Float> {
        let result = matrix * SIMD4(point, 1)
        return SIMD3(result.x, result.y, result.z)
    }

    private func refreshMood() {
        let newMood: DragonMood = if isSolved {
            .free
        } else if behavior.isWriggling {
            .wriggling
        } else if !userGrabbedNodes.isEmpty {
            .annoyed
        } else if behavior.restlessness > 0 {
            .restless
        } else {
            .calm
        }
        if newMood != mood { mood = newMood }
        if behavior.currentAction != action { action = behavior.currentAction }
    }

    private func refreshCrossings() {
        let crossings = simulation.crossings()
        crossingPoints = crossings.map(\.position)
        // Assegna solo se cambia, per non invalidare le View a ogni frame.
        if crossings.count != crossingCount { crossingCount = crossings.count }
    }
}
