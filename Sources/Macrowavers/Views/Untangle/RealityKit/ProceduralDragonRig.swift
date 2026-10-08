import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Drago placeholder fatto di primitive generate da codice: una sfera per nodo, testa con mascella
/// mobile, occhi luminosi, corna, ali, fumo e fiammata. Serve finché l'asset del design team non è pronto.
@MainActor
final class ProceduralDragonRig: DragonRig {
    let entity = Entity()

    private let radius: Float
    private var animator: DragonLifeAnimator
    private var segments: [Entity] = []
    private let head: Entity
    private let jaw: Entity
    private var eyes: [ModelEntity] = []
    private let wings: ProceduralWings
    private let effects = DragonEffects()
    private var showsSolved = false
    private var eyesAngry = false
    /// Collider a cui sono agganciati i segmenti (per l'hover); vuoto = segmenti figli di `entity`.
    private var colliders: [Entity] = []

    private static let bodyColor = PlatformColor(red: 0.20, green: 0.55, blue: 0.35, alpha: 1)
    private static let solvedColor = PlatformColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1)
    private static let eyeCalm = PlatformColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
    private static let eyeAngry = PlatformColor(red: 1, green: 0.25, blue: 0.1, alpha: 1)

    init(config: TangleConfig) {
        radius = config.radius
        animator = DragonLifeAnimator(config: config)
        entity.name = "ProceduralDragon"

        let parts = Self.makeHead(radius: radius)
        head = parts.head
        jaw = parts.jaw
        eyes = parts.eyes
        entity.addChild(head)
        effects.attach(nostrils: parts.nostrils, mouth: parts.mouth, voice: head)

        for index in 1..<config.nodeCount {
            // Il corpo si assottiglia verso la coda.
            let taper = 1 - 0.45 * Float(index) / Float(config.nodeCount - 1)
            let segment = ModelEntity(mesh: .generateSphere(radius: radius * taper),
                                      materials: [Self.material(Self.bodyColor)])
            segment.components.set(GroundingShadowComponent(castsShadow: true))
            entity.addChild(segment)
            segments.append(segment)
        }

        wings = ProceduralWings(radius: radius, shoulderIndex: 5)
        entity.addChild(wings.entity)
    }

    /// Ogni segmento diventa figlio del proprio collider: guardandolo, si illumina proprio quel tratto.
    func attach(to colliders: [Entity]) {
        guard colliders.count == segments.count + 1 else { return }
        self.colliders = colliders
        for (offset, segment) in segments.enumerated() {
            colliders[offset + 1].addChild(segment)
        }
    }

    func update(_ frame: DragonFrame, deltaTime: Float) {
        animator.update(frame, deltaTime: deltaTime)
        let pose = animator.pose
        let positions = animator.visualPositions(frame)

        head.position = positions[0]
        head.orientation = pose.headOrientation
        // Mascella: ruota verso il basso attorno alla cerniera.
        jaw.orientation = simd_quatf(angle: pose.jawOpen * 0.7, axis: SIMD3(1, 0, 0))

        for (offset, segment) in segments.enumerated() {
            let index = offset + 1
            // Se agganciato al collider, la posizione è relativa a lui (che può essere già nella mano).
            segment.position = colliders.isEmpty ? positions[index] : positions[index] - colliders[index].position
            segment.scale = SIMD3(repeating: animator.breathScale(node: index, time: frame.time))
        }

        let shoulder = wings.shoulderIndex
        wings.update(position: positions[shoulder],
                     forward: positions[shoulder - 1] - positions[shoulder + 1],
                     pose: pose, radius: radius)

        // Durante l'ira niente battito di ciglia: occhi spalancati e rossi.
        let angry = frame.mood == .wriggling || frame.mood == .restless
        let openness = angry ? 1 : max(animator.eyeOpenness(time: frame.time), 0.1)
        for eye in eyes { eye.scale = SIMD3(1, openness, 1) }
        if angry != eyesAngry {
            eyesAngry = angry
            let material = UnlitMaterial(color: angry ? Self.eyeAngry : Self.eyeCalm)
            for eye in eyes { eye.model?.materials = [material] }
        }

        effects.update(pose: pose, frame: frame)

        let isSolved = frame.mood == .free
        if isSolved != showsSolved {
            showsSolved = isSolved
            let material = Self.material(isSolved ? Self.solvedColor : Self.bodyColor)
            for node in segments + [head, jaw.children.first].compactMap({ $0 }) {
                node.components[ModelComponent.self]?.materials = [material]
            }
        }
    }

    private static func material(_ color: PlatformColor) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: 0.6, isMetallic: false)
    }

    private struct HeadParts {
        let head: Entity
        let jaw: Entity
        let eyes: [ModelEntity]
        let nostrils: Entity
        let mouth: Entity
    }

    private static func makeHead(radius: Float) -> HeadParts {
        let material = Self.material(bodyColor)
        let head = ModelEntity(mesh: .generateSphere(radius: radius * 1.5), materials: [material])
        head.components.set(GroundingShadowComponent(castsShadow: true))

        // Mascella superiore (muso).
        let snout = ModelEntity(mesh: .generateBox(size: SIMD3(radius * 1.6, radius * 0.7, radius * 2.4),
                                                   cornerRadius: radius * 0.3),
                                materials: [material])
        snout.position = SIMD3(0, radius * 0.05, radius * 1.5)
        head.addChild(snout)

        // Interno della bocca, visibile quando si apre.
        let mouthInside = ModelEntity(mesh: .generateBox(size: SIMD3(radius * 1.3, radius * 0.15, radius * 2.0)),
                                      materials: [SimpleMaterial(color: PlatformColor(red: 0.5, green: 0.08, blue: 0.08, alpha: 1),
                                                                 isMetallic: false)])
        mouthInside.position = SIMD3(0, -radius * 0.32, radius * 1.4)
        head.addChild(mouthInside)

        // Mascella inferiore: cerniera dietro, la parte mobile in avanti.
        let jaw = Entity()
        jaw.position = SIMD3(0, -radius * 0.35, radius * 0.3)
        let lowerJaw = ModelEntity(mesh: .generateBox(size: SIMD3(radius * 1.4, radius * 0.35, radius * 2.2),
                                                      cornerRadius: radius * 0.15),
                                   materials: [material])
        lowerJaw.position = SIMD3(0, -radius * 0.15, radius * 1.1)
        jaw.addChild(lowerJaw)
        head.addChild(jaw)

        // Punti da cui escono fumo (narici) e fuoco (bocca).
        let nostrils = Entity()
        nostrils.position = SIMD3(0, radius * 0.45, radius * 2.7)
        head.addChild(nostrils)
        let mouth = Entity()
        mouth.position = SIMD3(0, -radius * 0.35, radius * 2.6)
        head.addChild(mouth)

        var eyes: [ModelEntity] = []
        for side: Float in [-1, 1] {
            let eye = ModelEntity(mesh: .generateSphere(radius: radius * 0.32),
                                  materials: [UnlitMaterial(color: eyeCalm)])
            eye.position = SIMD3(side * radius * 0.85, radius * 0.7, radius * 0.75)
            head.addChild(eye)
            eyes.append(eye)

            let horn = ModelEntity(mesh: .generateCone(height: radius * 1.8, radius: radius * 0.3),
                                   materials: [SimpleMaterial(color: .white, isMetallic: false)])
            horn.position = SIMD3(side * radius * 0.7, radius * 1.4, -radius * 0.6)
            horn.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3(1, 0, 0))
            head.addChild(horn)
        }
        return HeadParts(head: head, jaw: jaw, eyes: eyes, nostrils: nostrils, mouth: mouth)
    }
}
