import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

/// Fotografia di un frame di gioco passata al rig: tutto quello che serve per disegnare il drago.
struct DragonFrame {
    /// Posizioni della simulazione nello spazio del drago (indice 0 = testa).
    var positions: [SIMD3<Float>]
    var mood: DragonMood
    var action: DragonAction?
    var actionProgress: Float
    var restlessness: Float
    var strain: Float
    var time: Float
    /// Punto che la testa deve guardare quando è tirato (il nodo nella mano dell'utente).
    var lookTarget: SIMD3<Float>?
    /// Occhi dell'utente (il cavaliere) nello spazio del drago.
    var viewer: SIMD3<Float>
    /// Presente quando il drago, libero, vola nella stanza.
    var flight: FlightFrame?
}

struct FlightFrame {
    var maneuver: DragonFlight.Maneuver
    var progress: Float
    /// Velocità della testa nello spazio del drago.
    var velocity: SIMD3<Float>
}

/// La "pelle" del drago: come viene disegnato. Le collisioni e la fisica sono separate,
/// quindi si può sostituire il placeholder con l'asset vero senza toccare la logica di gioco.
@MainActor
protocol DragonRig: AnyObject {
    var entity: Entity { get }
    /// Riceve i collider (uno per nodo, indice = nodo). Un rig può agganciare la propria grafica
    /// ai collider: l'effetto hover di visionOS illumina i figli dell'entità guardata.
    func attach(to colliders: [Entity])
    func update(_ frame: DragonFrame, deltaTime: Float)
}

extension DragonRig {
    func attach(to colliders: [Entity]) {}
}

enum DragonRigLoader {
    /// Usa l'asset del design team se presente nel bundle, altrimenti il placeholder procedurale.
    @MainActor
    static func load(config: TangleConfig) async -> DragonRig {
        if let skeletal = await SkeletalDragonRig.load(config: config) {
            return skeletal
        }
        return ProceduralDragonRig(config: config)
    }
}

/// Posa "espressiva" del drago calcolata a ogni frame. Valida per qualsiasi rig.
struct DragonPose {
    var headOrientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    /// Di quanto si alza la testa sul collo (m) e quanti nodi partecipano.
    var neckLift: Float = 0.02
    var neckLength: Float = 5
    /// 0 = bocca chiusa, 1 = spalancata.
    var jawOpen: Float = 0
    /// 0 = ali chiuse lungo il corpo, 1 = spiegate.
    var wingFlare: Float = 0
    /// Angolo extra del battito d'ali (radianti).
    var wingFlap: Float = 0
    /// 0...1: fumo dalle narici.
    var smoke: Float = 0
    /// 0...1: fiammata dalla bocca.
    var fire: Float = 0
    /// Ampiezza dell'ondulazione laterale del corpo (m).
    var bodyWave: Float = 0
}

/// Animazioni "di vita" puramente visive: non toccano la simulazione, quindi il puzzle resta identico
/// anche se il drago si impenna, ondeggia o spiega le ali. Pensate come davanti a un drago vero:
/// tiene d'occhio il cavaliere, avvisa (fumo, ringhio) prima di attaccare, e i movimenti hanno peso.
struct DragonLifeAnimator {
    let config: TangleConfig
    private(set) var pose = DragonPose()

    init(config: TangleConfig) {
        self.config = config
    }

    /// Respiro: un'onda di gonfiore che scorre dalla testa alla coda.
    func breathScale(node index: Int, time: Float) -> Float {
        1 + 0.06 * sin(time * 2.2 - Float(index) * 0.25)
    }

    /// Chiusura delle palpebre (1 = aperte, 0 = chiuse): un battito ogni ~3,5 s.
    func eyeOpenness(time: Float) -> Float {
        let phase = time.truncatingRemainder(dividingBy: 3.5)
        return phase < 0.15 ? abs(phase - 0.075) / 0.075 : 1
    }

    /// Posizioni da disegnare: simulazione + collo sollevato + ondulazione + tremore.
    func visualPositions(_ frame: DragonFrame) -> [SIMD3<Float>] {
        let positions = frame.positions
        let trembleAmount: Float = switch frame.mood {
        case .restless: 0.006 * frame.restlessness
        case .annoyed: 0.004 * frame.strain
        default: 0
        }
        return positions.indices.map { index in
            var position = positions[index]
            // Il collo si alza gradualmente verso la testa.
            let neckWeight = max(0, 1 - Float(index) / pose.neckLength)
            position.y += pose.neckLift * neckWeight * neckWeight
            // Ondulazione laterale che scorre lungo il corpo (serpeggiare).
            if pose.bodyWave > 0 {
                let previous = positions[max(index - 1, 0)]
                let next = positions[min(index + 1, positions.count - 1)]
                var tangent = previous - next
                tangent.y = 0
                if simd_length(tangent) > 1e-5 {
                    let side = simd_normalize(SIMD3(-tangent.z, 0, tangent.x))
                    position += side * pose.bodyWave * sin(frame.time * 9 - Float(index) * 0.45)
                }
            }
            if trembleAmount > 0 {
                let seed = Float(index) * 12.9898
                position += SIMD3(sin(frame.time * 41 + seed), 0, cos(frame.time * 37 + seed)) * trembleAmount
            }
            return position
        }
    }

    mutating func update(_ frame: DragonFrame, deltaTime: Float) {
        let positions = frame.positions
        guard positions.count > 2 else { return }
        let time = frame.time
        var target = DragonPose()
        target.neckLift = 0.02 + 0.005 * sin(time * 2.2)

        let headBase = positions[0]
        let bodyForward = simd_normalize(headBase - positions[1])
        var look = bodyForward
        var yawOffset: Float = 0
        var pitchOffset: Float = 0
        var responsiveness: Float = 5

        // Posizione attuale (disegnata) della testa: da qui parte lo sguardo.
        let head = headBase + SIMD3(0, pose.neckLift, 0)
        let toward = { (point: SIMD3<Float>) -> SIMD3<Float> in
            let direction = point - head
            return simd_length(direction) > 0.01 ? simd_normalize(direction) : bodyForward
        }

        switch frame.mood {
        case .calm:
            // Si guarda intorno, ma ogni tanto fissa il cavaliere.
            if time.truncatingRemainder(dividingBy: 9) < 3.5 {
                look = toward(frame.viewer)
            } else {
                yawOffset = 0.4 * sin(time * 0.6)
                pitchOffset = 0.1 * sin(time * 0.9)
            }
        case .annoyed:
            if let hand = frame.lookTarget { look = toward(hand) }
            target.neckLift = 0.05
            target.jawOpen = 0.5 * frame.strain
            yawOffset = 0.08 * sin(time * 25) * frame.strain
            responsiveness = 9
        case .restless:
            // Avviso: fissa il cavaliere, scuote la testa, fumo dalle narici, bocca che ringhia.
            look = toward(frame.viewer)
            yawOffset = 0.3 * sin(time * (6 + 8 * frame.restlessness)) * frame.restlessness
            target.neckLift = 0.04 + 0.05 * frame.restlessness
            target.smoke = 0.3 + 0.7 * frame.restlessness
            target.jawOpen = 0.25 * frame.restlessness
            target.wingFlare = 0.3 * frame.restlessness
        case .wriggling:
            responsiveness = 8
            animateAction(frame, target: &target, look: &look, pitch: &pitchOffset, toward: toward)
        case .free:
            if let flight = frame.flight {
                responsiveness = 6
                animateFlight(flight, frame: frame, target: &target, look: &look, toward: toward)
            } else {
                // Gratitudine: testa alta verso il cavaliere, ali spiegate che battono piano.
                look = toward(frame.viewer)
                target.neckLift = 0.12 + 0.02 * sin(time * 4)
                target.neckLength = 8
                target.wingFlare = 1
                target.wingFlap = 0.3 * sin(time * 4)
            }
        }

        target.headOrientation = Self.orientation(looking: look) * simd_quatf(angle: yawOffset, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: pitchOffset, axis: SIMD3(1, 0, 0))

        blend(toward: target, amount: 1 - exp(-deltaTime * responsiveness))
    }

    /// Interpolazione morbida verso la posa bersaglio: il drago ha peso, niente scatti.
    private mutating func blend(toward target: DragonPose, amount blend: Float) {
        pose.headOrientation = simd_slerp(pose.headOrientation, target.headOrientation, blend)
        pose.neckLift += (target.neckLift - pose.neckLift) * blend
        pose.neckLength += (target.neckLength - pose.neckLength) * blend
        pose.jawOpen += (target.jawOpen - pose.jawOpen) * min(blend * 2, 1)
        pose.wingFlare += (target.wingFlare - pose.wingFlare) * blend
        pose.wingFlap = target.wingFlap
        pose.smoke += (target.smoke - pose.smoke) * blend
        pose.fire = target.fire
        pose.bodyWave += (target.bodyWave - pose.bodyWave) * blend
    }

    /// Posa per ogni movimento dell'attacco d'ira.
    private func animateAction(_ frame: DragonFrame, target: inout DragonPose, look: inout SIMD3<Float>,
                               pitch: inout Float, toward: (SIMD3<Float>) -> SIMD3<Float>) {
        let progress = frame.actionProgress
        let time = frame.time
        switch frame.action {
        case .rearUp:
            // Si alza, fissa il cavaliere, ruggisce verso l'alto con una fiammata, poi ricade.
            let rise = smoothstep(0, 0.3, progress) * (1 - smoothstep(0.8, 1, progress))
            let roar = smoothstep(0.35, 0.45, progress) * (1 - smoothstep(0.7, 0.8, progress))
            target.neckLift = 0.22 * rise
            target.neckLength = 12
            look = toward(frame.viewer)
            pitch = -0.5 * roar
            target.jawOpen = roar
            target.fire = roar
            target.smoke = roar
            target.wingFlare = rise
            target.wingFlap = 0.35 * sin(time * 10) * rise
        case .turn(let angle):
            // La testa guida la rotazione, il corpo serpeggia dietro.
            look = rotate(toward(frame.positions[0] + (frame.positions[0] - frame.positions[1])), by: angle > 0 ? 0.8 : -0.8)
            target.neckLift = 0.07
            target.wingFlare = 0.35
            target.bodyWave = 0.012
        case .tailLash:
            if let tail = frame.positions.last { look = toward(tail) }
            target.neckLift = 0.06
            target.jawOpen = 0.4 * sin(progress * .pi)
            target.wingFlare = 0.5
            target.bodyWave = 0.008
        case .coil:
            look = toward(frame.positions.reduce(SIMD3<Float>.zero, +) / Float(frame.positions.count))
            target.neckLift = 0.05
            target.wingFlare = 0.3
            target.bodyWave = 0.006
        case nil:
            break
        }
    }

    /// Posa in volo: la testa segue la traiettoria (o guarda l'utente quando si ferma davanti a lui),
    /// le ali battono forte per salire, planano in discesa, si chiudono in picchiata.
    private func animateFlight(_ flight: FlightFrame, frame: DragonFrame, target: inout DragonPose,
                               look: inout SIMD3<Float>, toward: (SIMD3<Float>) -> SIMD3<Float>) {
        let time = frame.time
        let progress = flight.progress
        let speed = simd_length(flight.velocity)
        if speed > 0.05 { look = flight.velocity / speed }
        // In volo il corpo è già in 3D: niente collo sollevato né ondulazione extra.
        target.neckLift = 0
        target.neckLength = 1
        target.wingFlare = 1
        let climb = speed > 0.05 ? flight.velocity.y / speed : 0

        switch flight.maneuver {
        case .takeoff:
            target.wingFlap = 0.75 * sin(time * 10)
            target.jawOpen = 0.6 * sin(min(progress * 3, 1) * .pi)
        case .cruise:
            // Batte quando sale, plana quando scende.
            let effort = max(0.15, min(1, 0.4 + climb * 1.5))
            target.wingFlap = 0.5 * effort * sin(time * 6)
        case .swoop:
            // Ali raccolte in picchiata, si riaprono risalendo.
            target.wingFlare = progress < 0.5 ? 0.35 : 1
            target.wingFlap = progress < 0.5 ? 0 : 0.6 * sin(time * 9)
        case .hover:
            // Sospeso davanti al cavaliere: lo guarda e ruggisce con una fiammata verso l'alto.
            look = toward(frame.viewer)
            let roar = smoothstep(0.35, 0.45, progress) * (1 - smoothstep(0.75, 0.85, progress))
            target.wingFlap = 0.6 * sin(time * 8)
            target.jawOpen = roar
            target.fire = roar
            target.smoke = roar * 0.5
            // Ruggisce alzando il muso, per non soffiare il fuoco addosso all'utente.
            look = simd_normalize(look + SIMD3(0, 1.2 * roar, 0))
        case .loop:
            target.wingFlap = 0.4 * sin(time * 7)
        }
    }

    /// Orientamento con il muso (+Z) lungo `direction`, senza rollio.
    static func orientation(looking direction: SIMD3<Float>) -> simd_quatf {
        let yaw = atan2(direction.x, direction.z)
        let pitch = -asin(max(-1, min(1, direction.y)))
        return simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
    }

    private func rotate(_ direction: SIMD3<Float>, by angle: Float) -> SIMD3<Float> {
        simd_quatf(angle: angle, axis: SIMD3(0, 1, 0)).act(direction)
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let amount = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return amount * amount * (3 - 2 * amount)
    }
}
