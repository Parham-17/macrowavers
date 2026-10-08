import simd

/// Parametri della simulazione del corpo del drago.
/// Tutte le misure sono in metri (unità di RealityKit).
struct TangleConfig {
    /// Numero di nodi (vertebre) del corpo. Con un modello riggato deve coincidere con il numero di joint della spina dorsale.
    var nodeCount = 48
    /// Distanza a riposo tra due nodi consecutivi.
    var segmentLength: Float = 0.05
    /// Raggio del corpo usato per le collisioni con se stesso.
    var radius: Float = 0.03
    /// Iterazioni del solver per sotto-passo: più sono, più il corpo è "rigido".
    var solverIterations = 10
    /// Sotto-passi per frame: evitano che un segmento ne attraversi un altro.
    var substeps = 4
    /// 1 = nessun attrito, 0 = si ferma subito.
    var damping: Float = 0.9
    /// Attrito tra tratti del corpo che si toccano (0...1).
    var selfFriction: Float = 0.3
    /// Attrito con il terreno: senza, il groviglio tende a sciogliersi da solo scivolando.
    var groundFriction: Float = 0.6
    /// La testa resta ferma (il drago "tiene" la testa a terra). Senza un punto fisso,
    /// tirare la coda trascina via tutto il corpo e il nodo si scioglie da solo.
    var anchorHead = true
    /// Forza che tira il corpo verso il piano y = 0 (il drago "giace" a terra).
    var flattenStrength: Float = 0.04
    /// Rigidità alla piegatura (0...1): impedisce pieghe a gomito troppo strette.
    var bendStiffness: Float = 0.25
    /// Altezza a cui il drago solleva la coda quando si dimena: passa SOPRA il proprio corpo.
    var grabLift: Float = 0.08
    /// Allungamento oltre il quale i nodi afferrati smettono di seguire le mani (1.05 = +5%).
    var maxTension: Float = 1.04
    /// Massimo spostamento di un nodo afferrato per sotto-passo (anti-tunneling).
    var maxGrabSpeed: Float = 0.015
}

/// Corpo del drago simulato come una corda di nodi (Position Based Dynamics / Verlet).
/// Nessuna dipendenza da RealityKit: si può testare da sola e riusare con qualsiasi renderer.
final class TangleSimulation {
    let config: TangleConfig
    private(set) var positions: [SIMD3<Float>]
    private var previous: [SIMD3<Float>]
    /// Nodi afferrati (anche più di uno: una mano ciascuno) e punto in cui portarli.
    private var grabTargets: [Int: SIMD3<Float>] = [:]

    init(config: TangleConfig = TangleConfig(), positions: [SIMD3<Float>]) {
        precondition(positions.count == config.nodeCount, "positions.count must equal config.nodeCount")
        self.config = config
        self.positions = positions
        self.previous = positions
    }

    // MARK: - Interazione

    var grabbedIndices: Dictionary<Int, SIMD3<Float>>.Keys { grabTargets.keys }
    var hasGrabs: Bool { !grabTargets.isEmpty }

    func isGrabbed(_ index: Int) -> Bool { grabTargets[index] != nil }

    /// Restituisce `false` se il nodo non si può afferrare (la testa ancorata).
    @discardableResult
    func grab(_ index: Int) -> Bool {
        guard positions.indices.contains(index), !(config.anchorHead && index == 0) else { return false }
        grabTargets[index] = positions[index]
        return true
    }

    /// `point` in 3D: l'altezza decide se il tratto passa sopra o sotto gli altri.
    /// Non scende sotto il piano.
    func drag(_ index: Int, to point: SIMD3<Float>) {
        guard grabTargets[index] != nil else { return }
        grabTargets[index] = SIMD3(point.x, max(point.y, config.radius), point.z)
    }

    func release(_ index: Int) {
        grabTargets[index] = nil
    }

    func releaseAll() {
        grabTargets.removeAll()
    }

    /// Ruota rigidamente tutto il corpo attorno a un asse verticale (il drago si gira su se stesso).
    /// Una rotazione rigida non cambia gli incroci: è un movimento spettacolare ma "onesto" per il puzzle.
    func rotateBody(by angle: Float, around center: SIMD3<Float>) {
        let cosine = cos(angle), sine = sin(angle)
        func rotate(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let offset = point - center
            return SIMD3(center.x + offset.x * cosine - offset.z * sine, point.y, center.z + offset.x * sine + offset.z * cosine)
        }
        positions = positions.map(rotate)
        previous = previous.map(rotate)
        grabTargets = grabTargets.mapValues(rotate)
    }

    var centroid: SIMD3<Float> {
        positions.reduce(SIMD3<Float>.zero, +) / Float(positions.count)
    }

    // MARK: - Simulazione

    /// Avanza la simulazione a passo fisso (60 Hz), indipendente dal frame rate.
    func step(deltaTime: Float) {
        accumulator = min(accumulator + deltaTime, 0.1)
        while accumulator >= Self.tick {
            accumulator -= Self.tick
            for _ in 0..<config.substeps {
                integrate()
                moveGrabbedNodes()
                for _ in 0..<config.solverIterations {
                    solveDistances()
                    solveBending()
                    solveSelfCollisions()
                }
                measureTension()
            }
        }
    }

    private static let tick: Float = 1.0 / 60.0
    private var accumulator: Float = 0

    private func integrate() {
        for i in positions.indices where inverseMass(i) > 0 {
            var velocity = (positions[i] - previous[i]) * config.damping
            if positions[i].y < config.radius * 1.5 {
                velocity.x *= config.groundFriction
                velocity.z *= config.groundFriction
            }
            previous[i] = positions[i]
            positions[i] += velocity
            // Molla morbida verso il piano: il corpo si "adagia" ma le collisioni mantengono sopra/sotto.
            positions[i].y -= positions[i].y * config.flattenStrength
        }
    }

    /// Allungamento massimo del corpo (1 = a riposo). Quando il corpo è teso i vincoli non si possono
    /// soddisfare tutti e un tratto finirebbe per attraversarne un altro: in quel caso il nodo afferrato
    /// smette di avanzare. Utile anche come feedback (il drago "soffre" se tirato troppo).
    private(set) var tension: Float = 1

    private func measureTension() {
        var maxRatio: Float = 1
        for i in 0..<(positions.count - 1) {
            maxRatio = max(maxRatio, simd_length(positions[i + 1] - positions[i]) / config.segmentLength)
        }
        tension = maxRatio
    }

    private func moveGrabbedNodes() {
        for (node, target) in grabTargets {
            previous[node] = positions[node]
            if tension > config.maxTension {
                // Troppo teso (es. due mani che tirano in direzioni opposte):
                // il nodo cede un po' verso i vicini invece di strappare il corpo.
                let before = positions[max(node - 1, 0)]
                let after = positions[min(node + 1, positions.count - 1)]
                positions[node] += ((before + after) / 2 - positions[node]) * 0.05
                continue
            }
            let delta = target - positions[node]
            let distance = simd_length(delta)
            positions[node] += distance > config.maxGrabSpeed ? delta / distance * config.maxGrabSpeed : delta
        }
    }

    /// Peso inverso: i nodi afferrati hanno massa infinita (non vengono spostati dai vincoli).
    private func inverseMass(_ i: Int) -> Float {
        if grabTargets[i] != nil || (config.anchorHead && i == 0) { return 0 }
        return 1
    }

    private func satisfy(_ i: Int, _ j: Int, restLength: Float, stiffness: Float = 1, onlyIfShorter: Bool = false) {
        let wi = inverseMass(i), wj = inverseMass(j)
        guard wi + wj > 0 else { return }
        let delta = positions[j] - positions[i]
        let distance = simd_length(delta)
        guard distance > 1e-6 else { return }
        if onlyIfShorter && distance >= restLength { return }
        let correction = delta * ((distance - restLength) / (distance * (wi + wj))) * stiffness
        positions[i] += correction * wi
        positions[j] -= correction * wj
    }

    private func solveDistances() {
        for i in 0..<(positions.count - 1) {
            satisfy(i, i + 1, restLength: config.segmentLength)
        }
    }

    private func solveBending() {
        // Tiene i nodi i e i+2 a distanza minima: angolo di piegatura massimo ~ 110°.
        let minimum = config.segmentLength * 1.15
        for i in 0..<(positions.count - 2) {
            satisfy(i, i + 2, restLength: minimum, stiffness: config.bendStiffness, onlyIfShorter: true)
        }
    }

    private func solveSelfCollisions() {
        let minDistance = config.radius * 2
        let count = positions.count
        for i in 0..<count {
            for j in (i + 3)..<max(i + 3, count) {
                let delta = positions[j] - positions[i]
                let distanceSquared = simd_length_squared(delta)
                guard distanceSquared < minDistance * minDistance else { continue }
                satisfy(i, j, restLength: minDistance, onlyIfShorter: true)
                applyFriction(i, j, normal: delta / max(sqrt(distanceSquared), 1e-6))
            }
        }
    }

    /// Attrito tra due tratti del corpo a contatto: senza, un nodo stretto scivola via da solo
    /// quando si tira un'estremità e il puzzle si risolve "per caso".
    private func applyFriction(_ i: Int, _ j: Int, normal: SIMD3<Float>) {
        let wi = inverseMass(i), wj = inverseMass(j)
        guard wi + wj > 0, config.selfFriction > 0 else { return }
        let relative = (positions[i] - previous[i]) - (positions[j] - previous[j])
        let tangential = relative - normal * simd_dot(relative, normal)
        let correction = tangential * (config.selfFriction / (wi + wj))
        positions[i] -= correction * wi
        positions[j] += correction * wj
    }

    // MARK: - Groviglio

    /// Incroci del corpo visto dall'alto (proiezione sul piano XZ).
    /// Il drago è libero quando non ci sono più incroci.
    func crossings() -> [Crossing] {
        var result: [Crossing] = []
        let count = positions.count
        for i in 0..<(count - 1) {
            for j in (i + 2)..<max(i + 2, count - 1) {
                let a0 = positions[i], a1 = positions[i + 1]
                let b0 = positions[j], b1 = positions[j + 1]
                guard let (alongA, alongB) = segmentIntersection(
                    SIMD2(a0.x, a0.z), SIMD2(a1.x, a1.z),
                    SIMD2(b0.x, b0.z), SIMD2(b1.x, b1.z)
                ) else { continue }
                let pointA = a0 + (a1 - a0) * alongA
                let pointB = b0 + (b1 - b0) * alongB
                result.append(Crossing(segmentA: i, segmentB: j, aIsOver: pointA.y > pointB.y,
                                       position: (pointA + pointB) / 2))
            }
        }
        return result
    }

    private func segmentIntersection(_ startA: SIMD2<Float>, _ endA: SIMD2<Float>,
                                     _ startB: SIMD2<Float>, _ endB: SIMD2<Float>) -> (Float, Float)? {
        let directionA = endA - startA, directionB = endB - startB
        let denominator = directionA.x * directionB.y - directionA.y * directionB.x
        guard abs(denominator) > 1e-9 else { return nil }
        let offset = startB - startA
        let alongA = (offset.x * directionB.y - offset.y * directionB.x) / denominator
        let alongB = (offset.x * directionA.y - offset.y * directionA.x) / denominator
        guard (0...1).contains(alongA), (0...1).contains(alongB) else { return nil }
        return (alongA, alongB)
    }
}

struct Crossing {
    /// Il segmento `segmentA` va dal nodo `segmentA` al nodo `segmentA + 1`.
    let segmentA: Int
    let segmentB: Int
    let aIsOver: Bool
    /// Punto dell'incrocio (a metà altezza tra i due tratti).
    let position: SIMD3<Float>
}
