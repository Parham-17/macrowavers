import RealityKit
import Observation

// MARK: - Componentes

enum FruitKind {
    case apple
    case pomegranate
}

/// Marca a entidade "suporte" de cada fruta, para descobrir em qual fruta o jogador tocou.
struct FruitTag: Component {
    let kind: FruitKind
}

/// Marca as sementes da romã.
struct SeedComponent: Component {}

/// Faz uma entidade flutuar suavemente em torno de uma posição "home".
struct FloatComponent: Component {
    var home: SIMD3<Float>
    var amplitude: Float = 0.006
    var speed: Float = 1.2
    var phase: Float = 0
    var time: Float = 0
    var paused = false
}

/// Roda a cada frame e aplica a flutuação em todas as entidades com FloatComponent.
struct FloatSystem: System {
    static let query = EntityQuery(where: .has(FloatComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var f = entity.components[FloatComponent.self] else { continue }
            f.time += dt
            let offset = f.paused ? 0 : sin(f.time * f.speed + f.phase) * f.amplitude
            entity.position = f.home + [0, offset, 0]
            entity.components[FloatComponent.self] = f
        }
    }
}

// MARK: - Mundo das frutas

@MainActor
@Observable
final class FruitWorld {
    let root = Entity()
    let apple = AppleController()
    let pomegranate = PomegranateController()

    private(set) var selected: FruitKind?

    @ObservationIgnored private let appleHolder = Entity()
    @ObservationIgnored private let pomHolder = Entity()

    // Posições no volume (origem no centro; +z aponta para o jogador).
    @ObservationIgnored private let appleShelf = Transform(scale: .init(repeating: 0.55), translation: [-0.22, -0.02, -0.18])
    @ObservationIgnored private let pomShelf = Transform(scale: .init(repeating: 0.75), translation: [0.22, 0.0, -0.18])
    @ObservationIgnored private let stage = Transform(scale: .one, translation: [0, -0.08, 0.05])

    init() {
        // Maçã: holder → bob (flutua) → apple.root, centralizada na origem do holder.
        let appleBob = Entity()
        appleBob.components.set(FloatComponent(home: .zero, amplitude: 0.01, speed: 0.9))
        apple.root.position = [0, -apple.shape.height / 2, 0]
        appleBob.addChild(apple.root)
        appleHolder.addChild(appleBob)
        appleHolder.components.set(FruitTag(kind: .apple))
        appleHolder.transform = appleShelf
        root.addChild(appleHolder)

        // Romã: holder → bob → pomegranate.root
        let pomBob = Entity()
        pomBob.components.set(FloatComponent(home: .zero, amplitude: 0.01, speed: 1.1, phase: 1.5))
        pomBob.addChild(pomegranate.root)
        pomHolder.addChild(pomBob)
        pomHolder.components.set(FruitTag(kind: .pomegranate))
        pomHolder.transform = pomShelf
        root.addChild(pomHolder)

        setShelfTargetable(true)
    }

    // MARK: Seleção

    func handleTap(on entity: Entity) {
        switch selected {
        case .some(.apple):
            apple.tryCollect(entity)
        case .some(.pomegranate):
            break
        case .none:
            if let kind = fruitKind(of: entity) { select(kind) }
        }
    }

    func select(_ kind: FruitKind) {
        selected = kind
        setShelfTargetable(false)

        let (chosen, other, otherShelf) = kind == .apple
            ? (appleHolder, pomHolder, pomShelf)
            : (pomHolder, appleHolder, appleShelf)

        chosen.move(to: stage, relativeTo: root, duration: 0.7, timingFunction: .easeInOut)

        // A outra fruta recua para o fundo e diminui.
        var away = otherShelf
        away.translation = [otherShelf.translation.x * 1.4, 0.18, -0.3]
        away.scale = .init(repeating: 0.3)
        other.move(to: away, relativeTo: root, duration: 0.7, timingFunction: .easeInOut)
    }

    func back() {
        apple.reset()
        pomegranate.reset()
        appleHolder.move(to: appleShelf, relativeTo: root, duration: 0.7, timingFunction: .easeInOut)
        pomHolder.move(to: pomShelf, relativeTo: root, duration: 0.7, timingFunction: .easeInOut)
        selected = nil
        setShelfTargetable(true)
    }

    /// Sobe pela hierarquia até achar a FruitTag.
    func fruitKind(of entity: Entity) -> FruitKind? {
        var current: Entity? = entity
        while let e = current {
            if let tag = e.components[FruitTag.self] { return tag.kind }
            current = e.parent
        }
        return nil
    }

    /// Na prateleira, cada fruta inteira é um alvo de toque. Selecionada, o alvo sai
    /// para não bloquear o cabinho, as minhocas e as sementes.
    private func setShelfTargetable(_ on: Bool) {
        if on {
            appleHolder.components.set(CollisionComponent(shapes: [.generateBox(width: 0.28, height: 0.3, depth: 0.28)]))
            appleHolder.components.set(InputTargetComponent())
            appleHolder.components.set(HoverEffectComponent())
            pomHolder.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.1)]))
            pomHolder.components.set(InputTargetComponent())
            pomHolder.components.set(HoverEffectComponent())
        } else {
            for holder in [appleHolder, pomHolder] {
                holder.components.remove(CollisionComponent.self)
                holder.components.remove(InputTargetComponent.self)
                holder.components.remove(HoverEffectComponent.self)
            }
        }
    }
}
