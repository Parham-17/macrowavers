import RealityKit
import UIKit
import Observation

@MainActor
@Observable
final class PomegranateController {
    let root = Entity()

    private(set) var opening: Float = 0
    private(set) var burst = false

    @ObservationIgnored let radius: Float = 0.08
    @ObservationIgnored private let seedCount = 40
    @ObservationIgnored private let body = Entity()
    @ObservationIgnored private let rightHalf: ModelEntity
    @ObservationIgnored private let leftHalf: ModelEntity
    @ObservationIgnored private var seeds: [Entity] = []
    @ObservationIgnored private var burstGeneration = 0
    @ObservationIgnored private let seedMaterial: PhysicallyBasedMaterial

    init() {
        let skin = Self.material(r: 0.62, g: 0.08, b: 0.16, roughness: 0.55)
        let inner = Self.material(r: 0.98, g: 0.88, b: 0.78, roughness: 0.8)
        seedMaterial = Self.material(r: 0.78, g: 0.04, b: 0.16, roughness: 0.12)

        let mesh = try! Self.makeHalfMesh(radius: radius)
        rightHalf = ModelEntity(mesh: mesh, materials: [skin, inner])
        leftHalf = ModelEntity(mesh: mesh, materials: [skin, inner])
        leftHalf.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])   // espelha a metade

        rightHalf.addChild(Self.makeCrown(material: skin, topY: radius * 0.9))

        body.addChild(rightHalf)
        body.addChild(leftHalf)
        // Alvo do gesto de duas mãos.
        body.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius * 1.1)]))
        body.components.set(InputTargetComponent())
        root.addChild(body)

        spawnSeeds()
    }

    // MARK: Abertura

    /// 0 = fechada, 1 = aberta. As metades se afastam e giram como um livro,
    /// mostrando a face cortada para o jogador.
    func setOpening(_ value: Float) {
        opening = min(max(value, 0), 1)
        let angle = opening * 0.4 * .pi
        let distance = opening * 0.12

        rightHalf.position = [distance, 0, 0]
        rightHalf.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        leftHalf.position = [-distance, 0, 0]
        leftHalf.orientation = simd_quatf(angle: .pi - angle, axis: [0, 1, 0])

        if opening >= 0.95 && !burst {
            burstSeeds()
        }
    }

    func reset() {
        burstGeneration += 1
        burst = false
        seeds.forEach { $0.removeFromParent() }
        spawnSeeds()
        setOpening(0)
    }

    // MARK: Sementes

    private func spawnSeeds() {
        seeds = []
        for _ in 0..<seedCount {
            let seed = Entity()
            let model = ModelEntity(mesh: .generateSphere(radius: 0.008), materials: [seedMaterial])
            model.scale = [0.9, 1.3, 0.9]          // formato de gota
            seed.addChild(model)

            // Começa empacotada dentro da fruta.
            let p = Self.randomInUnitSphere()
            seed.position = [p.x * 0.055, p.y * 0.05, p.z * 0.055]
            seed.orientation = simd_quatf(angle: .random(in: 0...(2 * .pi)),
                                          axis: normalize(Self.randomInUnitSphere() + [0, 0.01, 0]))
            seed.components.set(SeedComponent())
            // Área de toque maior que a semente, para facilitar pegar.
            seed.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.016)]))

            root.addChild(seed)
            seeds.append(seed)
        }
    }

    private func burstSeeds() {
        burst = true
        burstGeneration += 1
        let generation = burstGeneration

        for (i, seed) in seeds.enumerated() {
            var target = seed.transform
            target.translation = cloudPoint()
            seed.move(to: target, relativeTo: root,
                      duration: 0.8 + Double(i % 5) * 0.08,
                      timingFunction: .easeOut)
        }

        // Quando a explosão termina, as sementes passam a flutuar e aceitar toque.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.3))
            guard let self, self.burstGeneration == generation else { return }
            for seed in self.seeds {
                seed.components.set(FloatComponent(home: seed.position,
                                                   amplitude: 0.004,
                                                   speed: .random(in: 0.8...1.6),
                                                   phase: .random(in: 0...(2 * .pi))))
                seed.components.set(InputTargetComponent())
                seed.components.set(HoverEffectComponent())
            }
        }
    }

    /// Ponto aleatório dentro de uma "nuvem" na frente da fruta.
    private func cloudPoint() -> SIMD3<Float> {
        let p = Self.randomInUnitSphere()
        return [p.x * 0.14, 0.04 + p.y * 0.08, 0.2 + p.z * 0.06]
    }

    /// Semente que já saiu da fruta e pode ser arrastada.
    func isFreeSeed(_ entity: Entity) -> Bool {
        entity.components.has(SeedComponent.self) && entity.components.has(FloatComponent.self)
    }

    func home(of seed: Entity) -> SIMD3<Float> {
        seed.components[FloatComponent.self]?.home ?? seed.position
    }

    func moveSeed(_ seed: Entity, to position: SIMD3<Float>) {
        guard var f = seed.components[FloatComponent.self] else { return }
        f.home = position
        f.paused = true          // não balança enquanto está na mão
        seed.components.set(f)
    }

    func endSeedDrag(_ seed: Entity) {
        guard var f = seed.components[FloatComponent.self] else { return }
        f.paused = false
        seed.components.set(f)
    }

    // MARK: Geometria

    /// Meia esfera (lado x ≥ 0) levemente achatada + a face cortada no plano x = 0.
    private static func makeHalfMesh(radius r: Float) throws -> MeshResource {
        let squash: Float = 0.9
        let nPhi = 24, nTheta = 24

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for i in 0...nPhi {
            let phi = Float.pi * Float(i) / Float(nPhi)
            for j in 0...nTheta {
                let theta = -Float.pi / 2 + Float.pi * Float(j) / Float(nTheta)
                let n = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                positions.append([r * n.x, r * squash * n.y, r * n.z])
                normals.append(normalize(SIMD3<Float>(n.x, n.y / squash, n.z)))
            }
        }
        let cols = nTheta + 1
        for i in 0..<nPhi {
            for j in 0..<nTheta {
                let a = UInt32(i * cols + j), b = a + 1
                let c = a + UInt32(cols), d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }

        var skin = MeshDescriptor(name: "skin")
        skin.positions = MeshBuffers.Positions(positions)
        skin.normals = MeshBuffers.Normals(normals)
        skin.primitives = .triangles(indices)
        skin.materials = .allFaces(0)

        // Face cortada: um disco (elipse) no plano x = 0.
        let segments = 48
        var capPositions: [SIMD3<Float>] = [[0, 0, 0]]
        var capNormals: [SIMD3<Float>] = [[-1, 0, 0]]
        var capIndices: [UInt32] = []
        for k in 0...segments {
            let a = 2 * Float.pi * Float(k) / Float(segments)
            capPositions.append([0, r * squash * cos(a), r * sin(a)])
            capNormals.append([-1, 0, 0])
        }
        for k in 1...segments {
            capIndices += [0, UInt32(k), UInt32(k + 1)]
        }

        var cap = MeshDescriptor(name: "cap")
        cap.positions = MeshBuffers.Positions(capPositions)
        cap.normals = MeshBuffers.Normals(capNormals)
        cap.primitives = .triangles(capIndices)
        cap.materials = .allFaces(1)

        return try MeshResource.generate(from: [skin, cap])
    }

    /// A "coroa" característica no topo da romã.
    private static func makeCrown(material: PhysicallyBasedMaterial, topY: Float) -> Entity {
        let crown = Entity()
        let base = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.016), materials: [material])
        base.position = [0, 0.01, 0]
        crown.addChild(base)

        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi
            let tip = ModelEntity(mesh: .generateBox(width: 0.008, height: 0.018, depth: 0.004), materials: [material])
            tip.position = [0.013 * cos(a), 0.026, 0.013 * sin(a)]
            // Inclina cada ponta para fora.
            tip.orientation = simd_quatf(angle: 0.5, axis: [sin(a), 0, -cos(a)])
            crown.addChild(tip)
        }
        crown.position = [0, topY - 0.004, 0]
        return crown
    }

    private static func material(r: CGFloat, g: CGFloat, b: CGFloat, roughness: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: r, green: g, blue: b, alpha: 1))
        m.roughness = .init(floatLiteral: roughness)
        m.faceCulling = .none
        return m
    }

    private static func randomInUnitSphere() -> SIMD3<Float> {
        while true {
            let p = SIMD3<Float>(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1))
            if length(p) <= 1 { return p }
        }
    }
}
