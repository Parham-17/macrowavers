import Foundation
import simd

/// Volo libero del drago dopo essere stato sgrovigliato.
/// Lavora nello spazio della scena immersiva (metri, origine ai piedi dell'utente, y in alto).
///
/// Il corpo usa il "follow the leader": la testa vola e lascia una scia, ogni vertebra si trova sulla scia
/// a distanza fissa dalla precedente. Così il corpo serpeggia esattamente lungo la traiettoria della testa,
/// come un drago orientale, senza bisogno di fisica.
final class DragonFlight {
    enum Maneuver: Equatable {
        /// Si stacca dalla piattaforma salendo con battiti forti.
        case takeoff
        /// Plana in cerchio attorno all'utente, salendo e scendendo.
        case cruise
        /// Picchiata: passa di lato all'utente, più in basso, e risale.
        case swoop
        /// Si ferma davanti all'utente, lo guarda e ruggisce con una fiammata verso l'alto.
        case hover
        /// Giro della morte verticale.
        case loop

        var duration: Float {
            switch self {
            case .takeoff: 2.2
            case .cruise: 6
            case .swoop: 3
            case .hover: 3.2
            case .loop: 3
            }
        }
    }

    struct Settings {
        var speed: Float = 0.75
        /// Quanto velocemente la testa cambia direzione (più alto = virate più strette).
        var steering: Float = 2.2
        /// Distanza orizzontale dall'utente entro cui vola.
        var orbitRadius: ClosedRange<Float> = 1.1...2.0
        /// Altezze di volo (m dal pavimento).
        var altitude: ClosedRange<Float> = 0.9...2.1
        /// Il drago non si avvicina mai più di così alla testa dell'utente (comfort).
        var personalSpace: Float = 0.7
    }

    let settings: Settings
    let segmentLength: Float
    private(set) var positions: [SIMD3<Float>]
    private(set) var velocity: SIMD3<Float>
    private(set) var maneuver = Maneuver.takeoff
    private(set) var maneuverProgress: Float = 0

    /// Scia della testa: dal punto più vecchio (indice 0) alla testa attuale (ultimo).
    private var trail: [SIMD3<Float>]
    private var elapsed: Float = 0
    private var orbitDirection: Float = 1
    private var orbitAngle: Float = 0
    private var maneuverOrigin = SIMD3<Float>.zero
    private var maneuverForward = SIMD3<Float>(0, 0, -1)
    private var random = SystemRandomNumberGenerator()

    /// `start`: posizioni attuali del corpo (indice 0 = testa) nello spazio della scena.
    init(start: [SIMD3<Float>], segmentLength: Float, settings: Settings = Settings()) {
        self.settings = settings
        self.segmentLength = segmentLength
        positions = start
        // La scia iniziale è il corpo stesso, dalla coda alla testa: al decollo il corpo si "srotola".
        trail = start.reversed()
        let forward = simd_normalize(start[0] - start[1])
        velocity = SIMD3(forward.x, 0.6, forward.z) * 0.3
        orbitDirection = Bool.random(using: &random) ? 1 : -1
        begin(.takeoff, viewer: start[0])
    }

    func update(deltaTime: Float, viewer: SIMD3<Float>) {
        let dt = min(deltaTime, 1.0 / 30.0)
        elapsed += dt
        maneuverProgress = min(elapsed / maneuver.duration, 1)
        if maneuverProgress >= 1 { begin(nextManeuver(), viewer: viewer) }

        steer(toward: target(viewer: viewer), viewer: viewer, dt: dt)

        let head = positions[0] + velocity * dt
        if simd_distance(head, trail.last!) > segmentLength * 0.1 { trail.append(head) }
        positions = bodyAlongTrail(head: head)
        trimTrail()
    }

    // MARK: - Manovre

    private func begin(_ next: Maneuver, viewer: SIMD3<Float>) {
        maneuver = next
        elapsed = 0
        maneuverProgress = 0
        maneuverOrigin = positions[0]
        var forward = velocity
        forward.y = 0
        maneuverForward = simd_length(forward) > 1e-4 ? simd_normalize(forward) : SIMD3(0, 0, -1)
        let offset = positions[0] - viewer
        orbitAngle = atan2(offset.z, offset.x)
        if next == .cruise && Float.random(in: 0...1, using: &random) < 0.3 { orbitDirection *= -1 }
    }

    /// "Vita propria": sceglie la prossima manovra a caso, con pesi, senza ripetere picchiate o ruggiti di fila.
    private func nextManeuver() -> Maneuver {
        let options: [(Maneuver, Float)] = switch maneuver {
        case .takeoff: [(.cruise, 1)]
        case .cruise: [(.swoop, 0.35), (.hover, 0.3), (.loop, 0.2), (.cruise, 0.15)]
        case .swoop, .hover, .loop: [(.cruise, 1)]
        }
        var roll = Float.random(in: 0..<options.reduce(0) { $0 + $1.1 }, using: &random)
        for (option, weight) in options {
            roll -= weight
            if roll < 0 { return option }
        }
        return .cruise
    }

    /// Punto verso cui vola la testa, secondo la manovra.
    private func target(viewer: SIMD3<Float>) -> SIMD3<Float> {
        let progress = maneuverProgress
        let midRadius = (settings.orbitRadius.lowerBound + settings.orbitRadius.upperBound) / 2
        let midAltitude = (settings.altitude.lowerBound + settings.altitude.upperBound) / 2

        switch maneuver {
        case .takeoff:
            // Sale quasi in verticale, poi si allontana un po'.
            return maneuverOrigin + SIMD3(0, 0.9, 0) + maneuverForward * (0.6 * progress)
        case .cruise:
            // Cerchio attorno all'utente, raggio e quota che respirano.
            orbitAngle += orbitDirection * 0.012
            let radius = midRadius + 0.3 * sin(elapsed * 0.7)
            let height = midAltitude + 0.45 * sin(elapsed * 0.9)
            return SIMD3(viewer.x + radius * cos(orbitAngle + orbitDirection * 0.6), height,
                         viewer.z + radius * sin(orbitAngle + orbitDirection * 0.6))
        case .swoop:
            // Prima scende di lato all'utente, poi risale dall'altra parte.
            let toViewer = SIMD3(viewer.x - maneuverOrigin.x, 0, viewer.z - maneuverOrigin.z)
            let across = simd_length(toViewer) > 1e-4 ? simd_normalize(toViewer) : maneuverForward
            let side = SIMD3(-across.z, 0, across.x) * orbitDirection
            let low = SIMD3(viewer.x, settings.altitude.lowerBound, viewer.z) + side * (settings.personalSpace + 0.5)
            let far = low + across * 1.4 + SIMD3(0, 0.8, 0)
            return progress < 0.5 ? low : far
        case .hover:
            // Davanti all'utente, all'altezza dei suoi occhi, con un leggero ondeggiare.
            let toDragon = SIMD3(maneuverOrigin.x - viewer.x, 0, maneuverOrigin.z - viewer.z)
            let direction = simd_length(toDragon) > 1e-4 ? simd_normalize(toDragon) : SIMD3(0, 0, -1)
            let spot = viewer + direction * (settings.personalSpace + 0.6)
            return SIMD3(spot.x, viewer.y, spot.z) + SIMD3(0.15 * sin(elapsed * 2), 0.1 * sin(elapsed * 3), 0)
        case .loop:
            // Cerchio verticale nel piano (avanti, su).
            let angle = progress * 2 * .pi
            let radius: Float = 0.45
            let center = maneuverOrigin + maneuverForward * 0.6 + SIMD3(0, radius, 0)
            return center + maneuverForward * (radius * sin(angle) + 0.5) - SIMD3(0, radius * cos(angle), 0)
        }
    }

    private func steer(toward target: SIMD3<Float>, viewer: SIMD3<Float>, dt: Float) {
        let head = positions[0]
        var desired = target - head
        let distance = simd_length(desired)
        // In sospensione rallenta fino quasi a fermarsi.
        let speed = maneuver == .hover ? min(settings.speed, distance * 1.5) + 0.08 : settings.speed
        desired = distance > 1e-4 ? desired / distance * speed : .zero

        // Spazio personale: spinta via dalla testa dell'utente.
        let fromViewer = head - viewer
        let viewerDistance = simd_length(fromViewer)
        if viewerDistance < settings.personalSpace + 0.2, viewerDistance > 1e-4 {
            desired += fromViewer / viewerDistance * settings.speed * 2
        }
        // Resta tra pavimento e soffitto.
        if head.y < settings.altitude.lowerBound - 0.1 { desired.y += settings.speed }
        if head.y > settings.altitude.upperBound + 0.2 { desired.y -= settings.speed }
        // Non si allontana troppo (pareti della stanza).
        let horizontal = SIMD3(fromViewer.x, 0, fromViewer.z)
        if simd_length(horizontal) > settings.orbitRadius.upperBound + 0.4 {
            desired -= simd_normalize(horizontal) * settings.speed
        }

        velocity += (desired - velocity) * min(1, dt * settings.steering)
    }

    // MARK: - Corpo lungo la scia

    private func bodyAlongTrail(head: SIMD3<Float>) -> [SIMD3<Float>] {
        var result = [head]
        result.reserveCapacity(positions.count)
        var index = trail.count - 1
        var cursor = head
        var needed = segmentLength
        while result.count < positions.count {
            guard index > 0 else {
                // Scia finita: prolunga nella direzione dell'ultimo tratto.
                let last = result.count > 1 ? result[result.count - 1] - result[result.count - 2] : SIMD3(0, 0, segmentLength)
                result.append(result[result.count - 1] + simd_normalize(last) * segmentLength)
                continue
            }
            let previous = trail[index - 1]
            let step = simd_distance(cursor, previous)
            if step >= needed {
                cursor += (previous - cursor) * (needed / step)
                result.append(cursor)
                needed = segmentLength
            } else {
                needed -= step
                cursor = previous
                index -= 1
            }
        }
        return result
    }

    /// Tiene solo la scia che serve al corpo (più un margine).
    private func trimTrail() {
        let bodyLength = segmentLength * Float(positions.count + 4)
        var length: Float = 0
        var index = trail.count - 1
        while index > 0 && length < bodyLength {
            length += simd_distance(trail[index], trail[index - 1])
            index -= 1
        }
        if index > 0 { trail.removeFirst(index) }
    }
}
