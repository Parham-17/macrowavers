import RealityKit
import Metal
import SwiftUI

// MARK: - Structs compartilhadas com o shader (layout precisa bater com o .metal)

struct VertexParams {
    var theta: Float
    var s: Float
    var v: Float
    var kind: UInt32
}

struct AppleVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

struct AppleUniforms {
    var opening: Float
    var height: Float
    var maxRadius: Float
    var turns: Float
    var gapPerTurn: Float
    var vertexCount: UInt32
}

// MARK: - Forma da maçã (mesma matemática do shader, usada para posicionar minhocas e cabinho)

struct AppleShape {
    var height: Float = 0.24       // metros
    var maxRadius: Float = 0.12
    var turns: Float = 4           // voltas que se abrem
    var gapPerTurn: Float = 0.05   // espaço entre voltas quando totalmente aberta

    var pitch: Float { height / (turns + 1) }
    var thetaStart: Float { -2 * .pi }
    var thetaEnd: Float { 2 * .pi * (turns + 1) }
    var maxLift: Float { gapPerTurn * turns }

    func radius(atHeight h: Float) -> Float {
        let t = min(max(h / height, 0), 1)
        return maxRadius * (0.12 + 0.88 * sqrt(max(sin(Float.pi * t), 0)))
    }

    func point(theta: Float, s: Float, v: Float, kind: UInt32, opening: Float) -> SIMD3<Float> {
        let turn = theta / (2 * .pi)
        let yb = min(max(turn * pitch, 0), height)
        let yt = min(max((turn + 1) * pitch, 0), height)
        let lift = opening * gapPerTurn * min(max(turn, 0), turns)

        let h: Float
        let r: Float
        switch kind {
        case 0:  h = yt; r = radius(atHeight: h) * s
        case 1:  h = yb; r = radius(atHeight: h) * s
        default: h = yb + (yt - yb) * v; r = radius(atHeight: h)
        }
        return [r * cos(theta), h + lift, r * sin(theta)]
    }
}

// MARK: - Controlador

@MainActor
@Observable
final class AppleController {
    let shape = AppleShape()
    let root = Entity()
    let handle = Entity()

    private(set) var opening: Float = 0
    private(set) var collected = 0
    let totalWorms = 3

    @ObservationIgnored private var worms: [(entity: Entity, theta: Float, s: Float)] = []

    // Metal
    @ObservationIgnored private let device: MTLDevice
    @ObservationIgnored private let queue: MTLCommandQueue
    @ObservationIgnored private let pipeline: MTLComputePipelineState
    @ObservationIgnored private var lowMesh: LowLevelMesh!
    @ObservationIgnored private var paramsBuffer: MTLBuffer!
    @ObservationIgnored private var vertexCount = 0

    init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        let function = device.makeDefaultLibrary()!.makeFunction(name: "deformApple")!
        pipeline = try! device.makeComputePipelineState(function: function)

        lowMesh = try! buildMesh()
        setOpening(0)   // preenche os vértices pela primeira vez

        let resource = try! MeshResource(from: lowMesh)
        let apple = ModelEntity(mesh: resource, materials: [Self.fleshMaterial(), Self.skinMaterial()])
        root.addChild(apple)

        buildHandle()
        spawnWorms()
        updateAttachments()
    }

    // MARK: Geometria

    private func buildMesh() throws -> LowLevelMesh {
        let segmentsPerTurn = 64
        let nTheta = Int(shape.turns + 2) * segmentsPerTurn + 1
        let nS = 10   // amostras do centro até a borda
        let nV = 5    // amostras na altura da casca

        var params: [VertexParams] = []
        var fleshIdx: [UInt32] = []
        var skinIdx: [UInt32] = []

        func theta(_ i: Int) -> Float {
            shape.thetaStart + (shape.thetaEnd - shape.thetaStart) * Float(i) / Float(nTheta - 1)
        }

        func addGrid(_ indices: inout [UInt32], base: UInt32, rows: Int, cols: Int) {
            for i in 0..<(rows - 1) {
                for j in 0..<(cols - 1) {
                    let a = base + UInt32(i * cols + j)
                    let b = a + 1
                    let c = a + UInt32(cols)
                    let d = c + 1
                    indices += [a, c, b, b, c, d]
                }
            }
        }

        // Faces de polpa: cima (kind 0) e baixo (kind 1)
        for kind: UInt32 in [0, 1] {
            let base = UInt32(params.count)
            for i in 0..<nTheta {
                for j in 0..<nS {
                    params.append(.init(theta: theta(i), s: Float(j) / Float(nS - 1), v: 0, kind: kind))
                }
            }
            addGrid(&fleshIdx, base: base, rows: nTheta, cols: nS)
        }

        // Casca (kind 2)
        let base = UInt32(params.count)
        for i in 0..<nTheta {
            for j in 0..<nV {
                params.append(.init(theta: theta(i), s: 1, v: Float(j) / Float(nV - 1), kind: 2))
            }
        }
        addGrid(&skinIdx, base: base, rows: nTheta, cols: nV)

        vertexCount = params.count
        paramsBuffer = device.makeBuffer(bytes: params,
                                         length: params.count * MemoryLayout<VertexParams>.stride,
                                         options: .storageModeShared)

        var desc = LowLevelMesh.Descriptor()
        desc.vertexAttributes = [
            .init(semantic: .position, format: .float3,
                  offset: MemoryLayout<AppleVertex>.offset(of: \.position)!),
            .init(semantic: .normal, format: .float3,
                  offset: MemoryLayout<AppleVertex>.offset(of: \.normal)!)
        ]
        desc.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<AppleVertex>.stride)]
        desc.vertexCapacity = params.count
        desc.indexCapacity = fleshIdx.count + skinIdx.count
        desc.indexType = .uint32

        let mesh = try LowLevelMesh(descriptor: desc)

        let allIdx = fleshIdx + skinIdx
        mesh.withUnsafeMutableIndices { raw in
            let dst = raw.bindMemory(to: UInt32.self)
            for k in allIdx.indices { dst[k] = allIdx[k] }
        }

        // Bounds generosos que cobrem a maçã totalmente aberta (evita culling errado).
        let r = shape.maxRadius
        let bounds = BoundingBox(min: [-r, 0, -r], max: [r, shape.height + shape.maxLift + 0.01, r])

        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexOffset: 0,
                              indexCount: fleshIdx.count,
                              topology: .triangle,
                              materialIndex: 0,
                              bounds: bounds),
            LowLevelMesh.Part(indexOffset: fleshIdx.count * MemoryLayout<UInt32>.stride, // em bytes
                              indexCount: skinIdx.count,
                              topology: .triangle,
                              materialIndex: 1,
                              bounds: bounds)
        ])
        return mesh
    }

    // MARK: Abertura (roda o compute shader)

    func setOpening(_ value: Float) {
        opening = min(max(value, 0), 1)

        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        // Pede ao RealityKit o buffer de vértices que a GPU vai escrever.
        let vertexBuffer = lowMesh.replace(bufferIndex: 0, using: commandBuffer)

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        var uniforms = AppleUniforms(opening: opening,
                                     height: shape.height,
                                     maxRadius: shape.maxRadius,
                                     turns: shape.turns,
                                     gapPerTurn: shape.gapPerTurn,
                                     vertexCount: UInt32(vertexCount))

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 0)
        encoder.setBuffer(vertexBuffer, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<AppleUniforms>.stride, index: 2)
        encoder.dispatchThreads(
            MTLSize(width: vertexCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(64, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()

        updateAttachments()
    }

    // MARK: Cabinho e minhocas

    private func buildHandle() {
        var stemMat = PhysicallyBasedMaterial()
        stemMat.baseColor = .init(tint: UIColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 1))
        let stem = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 0.006), materials: [stemMat])
        stem.position = [0, 0.025, 0]
        handle.addChild(stem)

        handle.components.set(CollisionComponent(shapes: [
            ShapeResource.generateSphere(radius: 0.04).offsetBy(translation: [0, 0.025, 0])
        ]))
        handle.components.set(InputTargetComponent())
        handle.components.set(HoverEffectComponent())
        root.addChild(handle)
    }

    private func spawnWorms() {
        worms.forEach { $0.entity.removeFromParent() }
        worms = []

        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: UIColor(red: 0.45, green: 0.8, blue: 0.3, alpha: 1))
        mat.roughness = 0.6

        for k in 1...totalWorms {
            let theta = 2 * Float.pi * (Float(k) + 0.3)
            let worm = Entity()
            for i in 0..<3 {
                let segment = ModelEntity(mesh: .generateSphere(radius: 0.007), materials: [mat])
                segment.position = [Float(i - 1) * 0.009, 0, 0]
                worm.addChild(segment)
            }
            worm.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.025)]))
            worm.components.set(InputTargetComponent())
            worm.components.set(HoverEffectComponent())
            root.addChild(worm)
            worms.append((worm, theta, 0.6))
        }
    }

    private func updateAttachments() {
        handle.position = [0, shape.height + opening * shape.maxLift, 0]

        for worm in worms {
            let p = shape.point(theta: worm.theta, s: worm.s, v: 0, kind: 0, opening: opening)
            worm.entity.position = p + [0, 0.007, 0]
            // Alinha a minhoca com a tangente da espiral.
            worm.entity.orientation = simd_quatf(angle: -worm.theta - .pi / 2, axis: [0, 1, 0])
        }
    }

    func tryCollect(_ entity: Entity) {
        guard opening > 0.35,
              let idx = worms.firstIndex(where: { $0.entity === entity }) else { return }

        let worm = worms.remove(at: idx).entity
        collected += 1

        var t = worm.transform
        t.translation += [0, 0.06, 0]
        t.scale = .zero
        worm.move(to: t, relativeTo: worm.parent, duration: 0.35)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            worm.removeFromParent()
        }
    }

    func reset() {
        collected = 0
        spawnWorms()
        setOpening(0)
    }

    // MARK: Materiais

    private static func fleshMaterial() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.98, green: 0.95, blue: 0.84, alpha: 1))
        m.roughness = 0.8
        m.faceCulling = .none
        return m
    }

    private static func skinMaterial() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.78, green: 0.12, blue: 0.15, alpha: 1))
        m.roughness = 0.35
        m.faceCulling = .none
        return m
    }
}
