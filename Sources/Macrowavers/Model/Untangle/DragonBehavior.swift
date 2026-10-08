import Foundation
import simd

/// Stato d'animo del drago: guida sia la difficoltà sia le animazioni.
enum DragonMood: Equatable {
    /// Tranquillo, respira e tiene d'occhio il cavaliere.
    case calm
    /// L'utente lo sta tirando.
    case annoyed
    /// Nessun progresso da troppo tempo: sta per scatenarsi.
    case restless
    /// Attacco d'ira: esegue una sequenza di `DragonAction`.
    case wriggling
    /// Libero!
    case free
}

/// Movimenti del repertorio del drago durante un attacco d'ira.
enum DragonAction: Equatable {
    /// Si impenna sul collo, spalanca le ali e ruggisce verso il cavaliere. Intimidisce, non tocca il groviglio.
    case rearUp
    /// Si gira su se stesso (radianti, segno = verso). Rotazione rigida: il groviglio non cambia.
    case turn(angle: Float)
    /// Colpo di coda: la coda frusta sopra il corpo e crea nuovi incroci.
    case tailLash
    /// Si attorciglia: un tratto centrale del corpo si ripiega sopra il resto.
    case coil

    var duration: Float {
        switch self {
        case .rearUp: 1.6
        case .turn(let angle): 0.9 + abs(angle) / .pi * 1.2
        case .tailLash: 1.5
        case .coil: 1.7
        }
    }

    /// Le azioni che cambiano il groviglio prendono un nodo del corpo.
    var tanglesBody: Bool {
        switch self {
        case .tailLash, .coil: true
        case .rearUp, .turn: false
        }
    }
}

struct DifficultySettings {
    /// Secondi senza progressi prima del primo attacco d'ira (avviso compreso).
    var firstWriggleDelay: Float = 8
    /// Ogni attacco accorcia l'attesa di questi secondi...
    var delayReductionPerWriggle: Float = 1
    /// ...fino a questo minimo.
    var minimumWriggleDelay: Float = 5
    /// Per quanti secondi prima il drago "avvisa" (agitazione crescente).
    var warningDuration: Float = 2
    /// Tentativi extra (colpo di coda / attorcigliamento) se l'attacco non ha aggiunto incroci.
    var maxExtraTangles = 8
    /// Attesa dopo l'ultimo movimento prima di contare gli incroci (il corpo si assesta).
    var settleTime: Float = 0.35
    /// Raggio entro cui il drago resta sulla piattaforma.
    var platformRadius: Float = 0.3
}

/// Comportamento autonomo del drago. Se l'utente non fa progressi, il drago ha un attacco d'ira:
/// una coreografia di movimenti realistici (si impenna, si gira, frusta la coda, si attorciglia)
/// che diventa più lunga e cattiva a ogni attacco.
/// Usa la stessa fisica dell'utente, quindi il nuovo groviglio è sempre risolvibile.
final class DragonBehavior {
    let settings: DifficultySettings
    /// Attacchi d'ira completati: fa salire la difficoltà.
    private(set) var fitCount = 0
    /// 0...1: quanto manca al prossimo attacco (1 = sta per farlo).
    private(set) var restlessness: Float = 0
    /// Azione in corso e suo avanzamento (0...1), per le animazioni.
    private(set) var currentAction: DragonAction?
    private(set) var actionProgress: Float = 0

    var isWriggling: Bool { currentAction != nil || settleRemaining != nil }

    private var queue: [DragonAction] = []
    /// Incroci all'inizio dell'attacco: alla fine devono essere di più.
    private var crossingsAtFitStart = 0
    private var latestCrossings = 0
    private var extraTangles = 0
    /// Countdown di assestamento prima del controllo finale (nil = non in controllo).
    private var settleRemaining: Float?
    private var actionElapsed: Float = 0
    private var timeWithoutProgress: Float = 0
    private var bestCrossings = Int.max
    // Stato dell'azione in corso.
    private var grabbedNode: Int?
    private var from = SIMD3<Float>.zero
    private var to = SIMD3<Float>.zero
    private var pivot = SIMD3<Float>.zero
    private var appliedTurn: Float = 0
    private var random = SystemRandomNumberGenerator()

    init(settings: DifficultySettings = DifficultySettings()) {
        self.settings = settings
    }

    var currentDelay: Float {
        max(settings.minimumWriggleDelay,
            settings.firstWriggleDelay - Float(fitCount) * settings.delayReductionPerWriggle)
    }

    func reset() {
        fitCount = 0
        restlessness = 0
        timeWithoutProgress = 0
        bestCrossings = .max
        queue = []
        currentAction = nil
        grabbedNode = nil
        settleRemaining = nil
        extraTangles = 0
    }

    /// L'utente afferra il drago durante l'attacco: il drago si ferma e lascia la presa.
    func interrupt(_ simulation: TangleSimulation) {
        guard isWriggling else { return }
        if let grabbedNode { simulation.release(grabbedNode) }
        queue = []
        settleRemaining = nil
        finishFit()
    }

    func update(deltaTime: Float, crossings: Int, userIsGrabbing: Bool, simulation: TangleSimulation) {
        latestCrossings = crossings
        if currentAction != nil {
            continueAction(deltaTime: deltaTime, simulation: simulation)
            return
        }
        if let remaining = settleRemaining {
            settleRemaining = remaining - deltaTime
            if remaining - deltaTime <= 0 { checkFitResult(simulation) }
            return
        }

        // Progresso = nuovo record di incroci più basso.
        if crossings < bestCrossings {
            bestCrossings = crossings
            timeWithoutProgress = 0
        } else {
            timeWithoutProgress += deltaTime
        }

        let warningStart = currentDelay - settings.warningDuration
        restlessness = max(0, min(1, (timeWithoutProgress - warningStart) / settings.warningDuration))

        // Non strappa il drago dalle mani dell'utente: aspetta che lasci la presa.
        if timeWithoutProgress >= currentDelay && !userIsGrabbing {
            queue = choreography()
            crossingsAtFitStart = crossings
            extraTangles = 0
            restlessness = 0
            startNextAction(simulation)
        }
    }

    /// L'attacco deve lasciare il drago più aggrovigliato di prima: se non è così, riprova.
    private func checkFitResult(_ simulation: TangleSimulation) {
        settleRemaining = nil
        if latestCrossings > crossingsAtFitStart || extraTangles >= settings.maxExtraTangles {
            finishFit()
            return
        }
        extraTangles += 1
        // Alterna i due movimenti, così il tentativo successivo parte da un tratto diverso.
        queue = [extraTangles.isMultiple(of: 2) ? .coil : .tailLash]
        startNextAction(simulation)
    }

    // MARK: - Coreografia

    /// Sequenza dell'attacco: più attacchi ha già fatto, più è lunga.
    /// Comincia sempre girandosi su se stesso (reazione immediata), poi intimidisce e aggroviglia.
    private func choreography() -> [DragonAction] {
        let direction: Float = Bool.random(using: &random) ? 1 : -1
        let turn = DragonAction.turn(angle: direction * Float.random(in: (.pi * 0.5)...(.pi * 0.9), using: &random))
        switch fitCount {
        case 0:
            return [turn, .tailLash]
        case 1:
            return [turn, .rearUp, .tailLash]
        default:
            let tangle: [DragonAction] = Bool.random(using: &random) ? [.tailLash, .coil] : [.coil, .tailLash]
            return [turn, .rearUp] + tangle + [.turn(angle: -direction * .pi * 0.4)]
        }
    }

    private func startNextAction(_ simulation: TangleSimulation) {
        guard !queue.isEmpty else {
            // Fine coreografia: lascia assestare il corpo, poi controlla che ci siano più incroci.
            currentAction = nil
            actionProgress = 0
            settleRemaining = settings.settleTime
            return
        }
        let action = queue.removeFirst()
        currentAction = action
        actionElapsed = 0
        actionProgress = 0
        grabbedNode = nil

        switch action {
        case .rearUp:
            break
        case .turn:
            pivot = simulation.centroid
            appliedTurn = 0
        case .tailLash:
            beginCrossing(node: simulation.positions.count - 1, simulation: simulation)
        case .coil:
            // Un tratto tra metà corpo e coda, diverso a ogni tentativo.
            let count = Float(simulation.positions.count)
            beginCrossing(node: Int(count * Float.random(in: 0.55...0.8, using: &random)), simulation: simulation)
        }
        // Se non riesce ad afferrare il nodo, passa oltre.
        if action.tanglesBody && grabbedNode == nil { startNextAction(simulation) }
    }

    /// Prepara un tratto del corpo a scavalcare un altro tratto preciso e ad atterrare subito oltre:
    /// così il tratto trascinato ci passa sopra e nasce un incrocio nuovo.
    private func beginCrossing(node: Int, simulation: TangleSimulation) {
        let positions = simulation.positions
        let start = positions[node]
        let flatStart = SIMD2(start.x, start.z)
        let reach: ClosedRange<Float> = 0.06...0.28
        let beyond = simulation.config.radius * 3

        // Tratti lontani lungo il corpo ma raggiungibili, con il punto d'arrivo sulla piattaforma.
        var candidates: [SIMD2<Float>] = []
        for segment in 0..<(positions.count - 1) where abs(segment - node) > 6 {
            let middle = (positions[segment] + positions[segment + 1]) / 2
            let flatMiddle = SIMD2(middle.x, middle.z)
            let distance = simd_length(flatMiddle - flatStart)
            guard reach.contains(distance) else { continue }
            let landing = flatMiddle + (flatMiddle - flatStart) / distance * beyond
            if simd_length(landing) <= settings.platformRadius { candidates.append(landing) }
        }

        var target: SIMD2<Float>
        if let landing = candidates.randomElement(using: &random) {
            target = landing
        } else {
            // Nessun tratto adatto: passa "dall'altra parte" rispetto al centro del corpo.
            let center = simulation.centroid
            target = SIMD2(2 * center.x - start.x, 2 * center.z - start.z)
            if simd_length(target) > settings.platformRadius {
                target = simd_normalize(target) * settings.platformRadius
            }
        }
        guard simulation.grab(node) else { return }
        grabbedNode = node
        from = start
        to = SIMD3(target.x, simulation.config.grabLift, target.y)
    }

    private func continueAction(deltaTime: Float, simulation: TangleSimulation) {
        guard let action = currentAction else { return }
        actionElapsed += deltaTime
        let progress = min(actionElapsed / action.duration, 1)
        actionProgress = progress
        let eased = progress * progress * (3 - 2 * progress)

        switch action {
        case .rearUp:
            break
        case .turn(let angle):
            // Rotazione progressiva: parte lento, accelera, frena (come un corpo pesante).
            let target = angle * eased
            simulation.rotateBody(by: target - appliedTurn, around: pivot)
            appliedTurn = target
        case .tailLash, .coil:
            guard let node = grabbedNode else { break }
            // Arco con un'ondulazione laterale: sembra un colpo di frusta.
            let side = SIMD3(-(to.z - from.z), 0, to.x - from.x)
            var point = simd_mix(from, to, SIMD3(repeating: eased)) + side * (0.25 * sin(progress * .pi * 2))
            point.y = simulation.config.grabLift
            simulation.drag(node, to: point)
        }

        if progress >= 1 {
            if let grabbedNode { simulation.release(grabbedNode) }
            grabbedNode = nil
            startNextAction(simulation)
        }
    }

    private func finishFit() {
        currentAction = nil
        actionProgress = 0
        grabbedNode = nil
        fitCount += 1
        timeWithoutProgress = 0
        // Il nuovo groviglio diventa il riferimento: sciogliere quanto ha appena fatto è progresso.
        bestCrossings = .max
    }
}
