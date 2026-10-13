import Foundation
import RealityKit
import simd

/// Rig per l'asset vero del design team. Viene usato automaticamente quando nel bundle c'è `DragonBody`.
///
/// - `DragonBody` (USDZ / Reality Composer Pro): mesh skinnata con una catena di joint
///   `spine_00` (collo, vicino alla testa) … `spine_NN` (punta della coda), ognuno figlio del precedente.
///   La spina è guidata dalla simulazione a ogni frame: NON deve avere animazioni sulla spina.
///   Ali opzionali: joint `wing_L` / `wing_R` (figli di una vertebra delle spalle), aperti dal codice
///   ruotando attorno all'asse locale `Asset.wingFlareAxis`.
/// - `DragonHead` (opzionale): testa separata con le animazioni (vedi `clipName`) e due entità vuote
///   `nostrils` e `mouth` da cui escono fumo e fuoco. Origine nel punto di attacco al collo, muso verso +Z.
///   Se manca, si usano le animazioni di `DragonBody`.
///
/// ⚠️ Non testato con un asset reale: verificare con il primo export del design team.
@MainActor
final class SkeletalDragonRig: DragonRig {
    enum Asset {
        static let body = "DragonBody"
        static let head = "DragonHead"
        static let spineJointPrefix = "spine_"
        static let leftWingJoint = "wing_L"
        static let rightWingJoint = "wing_R"
        /// Asse locale attorno a cui ruota l'osso dell'ala per spiegarsi.
        static let wingFlareAxis = SIMD3<Float>(0, 0, 1)
        /// Tratto di collo (m) che esce dalla nuca nella direzione della testa prima di raggiungere il corpo simulato.
        static let neckBlendLength: Float = 0.18
        /// Punti della curva tra due nodi simulati: la spina ha più ossa dei nodi, senza questi seguirebbe gli spigoli.
        static let curveSubdivisions = 4
    }

    /// Nomi delle animazioni attese nell'asset: prima quella del movimento in corso, poi quella dello stato d'animo.
    static func clipName(for mood: DragonMood, action: DragonAction?) -> String {
        switch action {
        case .rearUp: return "roar"
        case .turn: return "turn"
        case .tailLash: return "lash"
        case .coil: return "coil"
        case nil: break
        }
        switch mood {
        case .calm: return "idle"
        case .annoyed: return "annoyed"
        case .restless: return "restless"
        case .wriggling: return "wriggle"
        case .free: return "happy"
        }
    }

    let entity = Entity()

    private var animator: DragonLifeAnimator
    private let model: ModelEntity
    private let head: Entity?
    /// Segue la testa (asset o, se manca, un'entità vuota): da qui escono fumo, fuoco e versi.
    private let headAnchor: Entity
    private let animatedEntity: Entity
    private let clips: [String: AnimationResource]
    private var playingClip: String?
    private let effects = DragonEffects()
    /// Joint delle ali (indice, lato: -1 sinistra, +1 destra).
    private let wingJoints: [(index: Int, side: Float)]

    private let spineIndices: [Int]
    private let bindTransforms: [Transform]
    /// Trasformazione (spazio modello) del genitore di `spine_00`: considerato fisso.
    private let chainParentMatrix: float4x4
    /// Orientamento di `spine_00` nella posa di riposo (spazio modello): mantiene il "roll" dell'artista.
    private let bindRootOrientation: simd_quatf
    /// Direzione di ogni osso nel proprio spazio locale (verso il joint figlio).
    private let boneAxes: [SIMD3<Float>]
    /// Distanza di ogni joint da `spine_00` lungo la catena (unità del modello).
    private let arcLengths: [Float]

    static func load(config: TangleConfig) async -> SkeletalDragonRig? {
        guard let bodyRoot = try? await Entity(named: Asset.body, in: .main) else { return nil }
        guard let model = findSkinnedModel(in: bodyRoot) else {
            print("⚠️ \(Asset.body): no ModelEntity with a skeleton, using the placeholder dragon.")
            return nil
        }
        let head = try? await Entity(named: Asset.head, in: .main)
        return SkeletalDragonRig(config: config, bodyRoot: bodyRoot, model: model, head: head)
    }

    private init?(config: TangleConfig, bodyRoot: Entity, model: ModelEntity, head: Entity?) {
        let names = model.jointNames
        let spine = names.indices
            .filter { Self.lastComponent(names[$0]).hasPrefix(Asset.spineJointPrefix) }
            .sorted { Self.lastComponent(names[$0]) < Self.lastComponent(names[$1]) }
        guard spine.count >= 2 else {
            print("⚠️ \(Asset.body): needs at least 2 '\(Asset.spineJointPrefix)*' joints, found \(spine.count).")
            return nil
        }

        animator = DragonLifeAnimator(config: config)
        self.model = model
        self.head = head
        spineIndices = spine
        let bind = model.jointTransforms
        bindTransforms = bind

        let parentPath = Self.parentPath(names[spine[0]])
        let parentMatrix = Self.modelMatrix(path: parentPath, names: names, bind: bind)
        chainParentMatrix = parentMatrix
        bindRootOrientation = simd_quatf(parentMatrix) * bind[spine[0]].rotation

        // Offset di ogni joint rispetto al precedente: dà lunghezza e direzione delle ossa.
        let offsets = spine.dropFirst().map { bind[$0].translation }
        var lengths: [Float] = [0]
        for offset in offsets { lengths.append(lengths.last! + simd_length(offset)) }
        arcLengths = lengths
        let spineLength = lengths.last!
        var axes = offsets.map { simd_length($0) > 1e-6 ? simd_normalize($0) : SIMD3<Float>(0, 1, 0) }
        axes.append(axes.last!)
        boneAxes = axes

        let animated = head ?? bodyRoot
        animatedEntity = animated
        clips = Self.collectClips(from: animated)

        wingJoints = names.indices.compactMap { index in
            switch Self.lastComponent(names[index]) {
            case Asset.leftWingJoint: (index, -1)
            case Asset.rightWingJoint: (index, 1)
            default: nil
            }
        }

        entity.name = "SkeletalDragon"
        entity.addChild(bodyRoot)
        // La testa sta dentro un contenitore: il codice muove il contenitore e non sovrascrive la
        // trasformazione della radice dell'asset (es. la rotazione Z-up → Y-up aggiunta dall'export di Blender).
        let anchor = Entity()
        if let head { anchor.addChild(head) }
        headAnchor = anchor
        entity.addChild(anchor)
        let nostrils = anchor.findEntity(named: "nostrils") ?? Self.marker(in: anchor, at: SIMD3(0, 0.01, 0.08))
        let mouth = anchor.findEntity(named: "mouth") ?? Self.marker(in: anchor, at: SIMD3(0, -0.01, 0.08))
        effects.attach(nostrils: nostrils, mouth: mouth, voice: anchor)

        // Scala l'asset perché la spina sia lunga quanto il corpo simulato.
        let measured = simd_length(entity.convert(position: SIMD3(spineLength, 0, 0), from: model)
                                   - entity.convert(position: .zero, from: model))
        let simulatedLength = config.segmentLength * Float(config.nodeCount - 1)
        if measured > 1e-6 {
            let factor = simulatedLength / measured
            bodyRoot.scale *= factor
            head?.scale *= factor
        }
    }

    func update(_ frame: DragonFrame, deltaTime: Float) {
        animator.update(frame, deltaTime: deltaTime)
        let head = animator.pose.headOrientation
        let visual = Self.neckFollowingHead(animator.visualPositions(frame), headOrientation: head)

        headAnchor.position = visual[0]
        headAnchor.orientation = head
        playClip(named: Self.clipName(for: frame.mood, action: frame.action), loops: frame.action == nil)
        effects.update(pose: animator.pose, frame: frame)

        var transforms = model.jointTransforms
        poseSpine(along: Self.smoothed(visual).map { model.convert(position: $0, from: entity) }, transforms: &transforms)
        poseWings(&transforms)
        model.jointTransforms = transforms
    }

    private func poseWings(_ transforms: inout [Transform]) {
        let pose = animator.pose
        let angle = -0.2 + 1.2 * pose.wingFlare + pose.wingFlap
        for (index, side) in wingJoints {
            transforms[index].rotation = bindTransforms[index].rotation
                * simd_quatf(angle: side * angle, axis: Asset.wingFlareAxis)
        }
    }

    // MARK: - Spina guidata dalla simulazione

    private func poseSpine(along curve: [SIMD3<Float>], transforms: inout [Transform]) {
        let targets = arcLengths.map { Self.point(on: curve, atArcLength: $0) }
        var previousOrientation = bindRootOrientation

        for (k, jointIndex) in spineIndices.enumerated() {
            let next = k + 1 < targets.count ? targets[k + 1] : targets[k] + (targets[k] - targets[k - 1])
            let direction = next - targets[k]
            guard simd_length(direction) > 1e-6 else { continue }

            // Trasporto parallelo: ruota il minimo indispensabile rispetto all'osso precedente (niente torsioni).
            let currentAxis = previousOrientation.act(boneAxes[k])
            let orientation = simd_quatf(from: simd_normalize(currentAxis), to: simd_normalize(direction)) * previousOrientation

            var local = bindTransforms[jointIndex]
            if k == 0 {
                let world = float4x4(translation: targets[0]) * float4x4(orientation)
                let relative = Transform(matrix: chainParentMatrix.inverse * world)
                local.translation = relative.translation
                local.rotation = relative.rotation
            } else {
                // La lunghezza dell'osso resta quella dell'asset: cambia solo la rotazione.
                local.rotation = previousOrientation.inverse * orientation
            }
            transforms[jointIndex] = local
            previousOrientation = orientation
        }
    }

    /// La testa è un pezzo rigido: se si gira rispetto al collo si vede il taglio. Il primo tratto di collo esce
    /// quindi dalla nuca nella direzione opposta al muso e si raccorda gradualmente al corpo simulato.
    /// Se la testa guarda in alto si solleva un po', così il collo non scende sotto la piattaforma.
    private static func neckFollowingHead(_ points: [SIMD3<Float>], headOrientation: simd_quatf) -> [SIMD3<Float>] {
        guard points.count > 1 else { return points }
        let blendLength = Asset.neckBlendLength
        let back = headOrientation.act(SIMD3(0, 0, -1))
        let start = points[0] + SIMD3(0, 0.5 * blendLength * max(0, -back.y), 0)
        var result = points
        result[0] = start
        var travelled: Float = 0
        for index in points.indices.dropFirst() {
            travelled += simd_length(points[index] - points[index - 1])
            guard travelled < blendLength else { break }
            let progress = travelled / blendLength
            let weight = progress * progress * (3 - 2 * progress)
            result[index] = simd_mix(start + back * travelled, points[index], SIMD3(repeating: weight))
        }
        return result
    }

    /// Spline di Catmull-Rom che passa per i nodi: curve morbide invece della polilinea.
    private static func smoothed(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard points.count > 2 else { return points }
        let steps = Asset.curveSubdivisions
        var result: [SIMD3<Float>] = []
        result.reserveCapacity((points.count - 1) * steps + 1)
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            // Coefficienti del polinomio cubico del tratto p1 → p2.
            let c0 = 2 * p1
            let c1 = p2 - p0
            let c2 = 2 * p0 - 5 * p1 + 4 * p2 - p3
            let c3 = 3 * p1 - p0 - 3 * p2 + p3
            for step in 0..<steps {
                let along = Float(step) / Float(steps)
                result.append(0.5 * (c0 + c1 * along + c2 * (along * along) + c3 * (along * along * along)))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    // MARK: - Animazioni

    private func playClip(named name: String, loops: Bool) {
        guard name != playingClip else { return }
        playingClip = name
        guard let clip = clips[name] ?? clips["idle"] else { return }
        animatedEntity.playAnimation(loops ? clip.repeat() : clip, transitionDuration: 0.3, startsPaused: false)
    }

    private static func marker(in parent: Entity, at position: SIMD3<Float>) -> Entity {
        let marker = Entity()
        marker.position = position
        parent.addChild(marker)
        return marker
    }

    private static func collectClips(from root: Entity) -> [String: AnimationResource] {
        var result: [String: AnimationResource] = [:]
        // Reality Composer Pro: Animation Library.
        if let library = root.components[AnimationLibraryComponent.self] {
            for (name, animation) in library.animations { result[name] = animation }
        }
        // USDZ: animazioni con nome.
        for animation in root.availableAnimations {
            if let name = animation.name, result[name] == nil { result[name] = animation }
        }
        return result
    }

    // MARK: - Utilità

    private static func findSkinnedModel(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
        for child in entity.children {
            if let found = findSkinnedModel(in: child) { return found }
        }
        return nil
    }

    private static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private static func parentPath(_ path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// Trasformazione nello spazio del modello di un joint, componendo la posa di riposo degli antenati.
    private static func modelMatrix(path: String, names: [String], bind: [Transform]) -> float4x4 {
        guard !path.isEmpty, let index = names.firstIndex(of: path) else { return matrix_identity_float4x4 }
        return modelMatrix(path: parentPath(path), names: names, bind: bind) * bind[index].matrix
    }

    /// Punto sulla polilinea a una certa distanza dall'inizio (estrapola oltre la fine).
    private static func point(on curve: [SIMD3<Float>], atArcLength target: Float) -> SIMD3<Float> {
        var travelled: Float = 0
        for i in 0..<(curve.count - 1) {
            let segment = simd_length(curve[i + 1] - curve[i])
            if travelled + segment >= target, segment > 0 {
                return curve[i] + (curve[i + 1] - curve[i]) * ((target - travelled) / segment)
            }
            travelled += segment
        }
        return curve.last!
    }
}

private extension float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(translation, 1)
    }
}
