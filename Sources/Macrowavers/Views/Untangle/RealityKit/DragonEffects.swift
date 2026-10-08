import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Effetti del drago condivisi da tutti i rig: fumo dalle narici, fiammata, versi.
/// I suoni sono opzionali: se nel bundle ci sono `DragonGrowl`, `DragonRoar`, `DragonRumble`,
/// `DragonWhoosh` (wav/m4a/mp3) vengono riprodotti come audio spaziale dalla testa.
@MainActor
final class DragonEffects {
    private let smoke = Entity()
    private let fire = Entity()
    private weak var voiceSource: Entity?
    private var sounds: [String: AudioFileResource] = [:]
    private var lastAction: DragonAction?
    private var lastMood: DragonMood?
    private var lastManeuver: DragonFlight.Maneuver?
    private var smokeLevel = -1
    private var fireLevel = -1

    init() {
        smoke.name = "NostrilSmoke"
        smoke.components.set(Self.smokeEmitter())
        fire.name = "FireBreath"
        fire.components.set(Self.fireEmitter())
        for name in ["DragonGrowl", "DragonRoar", "DragonRumble", "DragonWhoosh"] {
            if let sound = Self.loadSound(name) { sounds[name] = sound }
        }
    }

    /// `nostrils` e `mouth` sono i punti da cui escono fumo e fuoco (figli della testa).
    func attach(nostrils: Entity, mouth: Entity, voice: Entity) {
        nostrils.addChild(smoke)
        mouth.addChild(fire)
        voiceSource = voice
        if !sounds.isEmpty {
            voice.components.set(SpatialAudioComponent(gain: -6))
        }
    }

    func update(pose: DragonPose, frame: DragonFrame) {
        // Aggiorna gli emettitori solo quando l'intensità cambia di un "gradino".
        let newSmoke = Int((pose.smoke * 10).rounded())
        if newSmoke != smokeLevel {
            smokeLevel = newSmoke
            smoke.components[ParticleEmitterComponent.self]?.mainEmitter.birthRate = Float(newSmoke) * 8
        }
        let newFire = Int((pose.fire * 10).rounded())
        if newFire != fireLevel {
            fireLevel = newFire
            fire.components[ParticleEmitterComponent.self]?.mainEmitter.birthRate = Float(newFire) * 60
        }

        playSounds(for: frame)
    }

    /// Versi legati ai cambi di movimento, manovra o stato d'animo.
    private func playSounds(for frame: DragonFrame) {
        if frame.action != lastAction {
            lastAction = frame.action
            if let name = Self.sound(for: frame.action) { play(name) }
        }
        let maneuver = frame.flight?.maneuver
        if maneuver != lastManeuver {
            lastManeuver = maneuver
            if let name = Self.sound(for: maneuver) { play(name) }
        }
        if frame.mood != lastMood {
            if frame.mood == .restless { play("DragonGrowl") }
            lastMood = frame.mood
        }
    }

    private static func sound(for action: DragonAction?) -> String? {
        switch action {
        case .rearUp: "DragonRoar"
        case .turn: "DragonRumble"
        case .tailLash, .coil: "DragonWhoosh"
        case nil: nil
        }
    }

    private static func sound(for maneuver: DragonFlight.Maneuver?) -> String? {
        switch maneuver {
        case .takeoff, .swoop: "DragonWhoosh"
        case .hover: "DragonRoar"
        default: nil
        }
    }

    private func play(_ name: String) {
        guard let sound = sounds[name], let voiceSource else { return }
        voiceSource.playAudio(sound)
    }

    private static func loadSound(_ name: String) -> AudioFileResource? {
        for ext in ["wav", "m4a", "mp3", "caf"] where Bundle.main.url(forResource: name, withExtension: ext) != nil {
            return try? AudioFileResource.load(named: "\(name).\(ext)")
        }
        return nil
    }

    /// Sbuffi di fumo grigio che salgono e si allargano.
    private static func smokeEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .point
        emitter.emissionDirection = SIMD3(0, 0.4, 1)
        emitter.speed = 0.05
        emitter.speedVariation = 0.02
        emitter.mainEmitter.birthRate = 0
        emitter.mainEmitter.lifeSpan = 1.4
        emitter.mainEmitter.size = 0.008
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 5
        emitter.mainEmitter.spreadingAngle = 0.4
        emitter.mainEmitter.acceleration = SIMD3(0, 0.04, 0)
        emitter.mainEmitter.dampingFactor = 1.5
        emitter.mainEmitter.opacityCurve = .linearFadeOut
        emitter.mainEmitter.color = .evolving(start: .single(.init(white: 0.75, alpha: 0.5)),
                                              end: .single(.init(white: 0.35, alpha: 0)))
        return emitter
    }

    /// Getto di fuoco breve, giallo → rosso.
    private static func fireEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .point
        emitter.emissionDirection = SIMD3(0, 0, 1)
        emitter.speed = 0.6
        emitter.speedVariation = 0.15
        emitter.mainEmitter.birthRate = 0
        emitter.mainEmitter.lifeSpan = 0.35
        emitter.mainEmitter.size = 0.012
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 3
        emitter.mainEmitter.spreadingAngle = 0.25
        emitter.mainEmitter.opacityCurve = .quickFadeInOut
        emitter.mainEmitter.color = .evolving(start: .single(.init(red: 1, green: 0.85, blue: 0.3, alpha: 1)),
                                              end: .single(.init(red: 0.9, green: 0.15, blue: 0.05, alpha: 0)))
        return emitter
    }
}

/// Ali del drago placeholder: una membrana per lato agganciata alle "spalle".
/// Chiuse lungo il corpo, si spiegano quando il drago si impenna o è libero.
@MainActor
final class ProceduralWings {
    let entity = Entity()
    private var pivots: [(side: Float, pivot: Entity)] = []
    /// Nodo del corpo a cui sono attaccate le ali.
    let shoulderIndex: Int

    init(radius: Float, shoulderIndex: Int) {
        self.shoulderIndex = shoulderIndex
        entity.name = "Wings"
        var membrane = PhysicallyBasedMaterial()
        membrane.baseColor = .init(tint: PlatformColor(red: 0.35, green: 0.25, blue: 0.2, alpha: 1))
        membrane.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        let boneMaterial = SimpleMaterial(color: PlatformColor(red: 0.15, green: 0.35, blue: 0.22, alpha: 1),
                                          roughness: 0.6, isMetallic: false)

        for side: Float in [-1, 1] {
            let pivot = Entity()
            let wingSpan = radius * 5
            let skin = ModelEntity(mesh: .generateBox(width: wingSpan, height: 0.002, depth: radius * 3,
                                                      cornerRadius: 0.001),
                                   materials: [membrane])
            skin.position = SIMD3(side * wingSpan / 2, 0, -radius * 0.8)
            // Osso anteriore dell'ala.
            let bone = ModelEntity(mesh: .generateBox(width: wingSpan, height: radius * 0.25, depth: radius * 0.25,
                                                      cornerRadius: radius * 0.1),
                                   materials: [boneMaterial])
            bone.position = SIMD3(side * wingSpan / 2, 0, radius * 0.6)
            pivot.addChild(skin)
            pivot.addChild(bone)
            entity.addChild(pivot)
            pivots.append((side, pivot))
        }
    }

    /// `position` e `forward` della spalla (spazio del drago). In volo `forward` è inclinato: le ali seguono.
    func update(position: SIMD3<Float>, forward: SIMD3<Float>, pose: DragonPose, radius: Float) {
        let body = simd_length(forward) > 1e-5
            ? DragonLifeAnimator.orientation(looking: simd_normalize(forward))
            : simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        entity.position = position + SIMD3(0, radius * 0.9, 0)
        entity.orientation = body

        let flare = pose.wingFlare
        // Chiuse: piegate all'indietro e adagiate. Spiegate: aperte e alzate.
        let sweep = 1.2 - 0.9 * flare
        let lift = -0.15 + 1.0 * flare + pose.wingFlap
        for (side, pivot) in pivots {
            pivot.orientation = simd_quatf(angle: side * sweep, axis: SIMD3(0, 1, 0))
                * simd_quatf(angle: side * lift, axis: SIMD3(0, 0, 1))
        }
    }
}
