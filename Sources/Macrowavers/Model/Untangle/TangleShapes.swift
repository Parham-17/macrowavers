import Foundation
import simd

/// Pose iniziali "aggrovigliate" generate da codice.
/// Ogni livello del puzzle può usare una curva diversa (o una posa salvata dal design team).
enum TangleShape {
    /// Nodo trifoglio aperto: 3 incroci, si scioglie tirando la coda fuori dalle anse.
    case trefoil
    /// Nodo a otto aperto: 4 incroci, più difficile.
    case figureEight

    /// Curva parametrica: (x, z) è la proiezione vista dall'alto, y è l'altezza che decide chi passa sopra.
    private func point(at angle: Float) -> SIMD3<Float> {
        switch self {
        case .trefoil:
            return SIMD3(sin(angle) + 2 * sin(2 * angle),
                         -sin(3 * angle),
                         cos(angle) - 2 * cos(2 * angle))
        case .figureEight:
            return SIMD3((2 + cos(2 * angle)) * cos(3 * angle),
                         sin(4 * angle),
                         (2 + cos(2 * angle)) * sin(3 * angle))
        }
    }

    /// Campiona la curva (aperta, lasciando un varco tra testa e coda) in `config.nodeCount` nodi
    /// equidistanti `config.segmentLength`, scalata in modo che la lunghezza combaci.
    func positions(config: TangleConfig) -> [SIMD3<Float>] {
        let gap: Float = 0.35
        let heightFactor: Float = 1
        let start: Float = 0.2
        let end = start + 2 * .pi - gap

        // Campionamento fitto e lunghezza d'arco cumulativa.
        let samples = 2000
        var dense: [SIMD3<Float>] = []
        var arc: [Float] = [0]
        for k in 0...samples {
            var sample = point(at: start + (end - start) * Float(k) / Float(samples))
            // Esagera l'altezza: separazione netta sopra/sotto agli incroci.
            sample.y *= heightFactor
            if let last = dense.last { arc.append(arc.last! + simd_length(sample - last)) }
            dense.append(sample)
        }

        let targetLength = config.segmentLength * Float(config.nodeCount - 1)
        let scale = targetLength / arc.last!

        // Ricampionamento a passo costante.
        var result: [SIMD3<Float>] = []
        var k = 0
        for node in 0..<config.nodeCount {
            let distance = arc.last! * Float(node) / Float(config.nodeCount - 1)
            while k < arc.count - 2 && arc[k + 1] < distance { k += 1 }
            let fraction = (distance - arc[k]) / max(arc[k + 1] - arc[k], 1e-6)
            let point = simd_mix(dense[k], dense[k + 1], SIMD3(repeating: fraction)) * scale
            result.append(point + SIMD3(0, config.radius, 0))
        }
        return result
    }
}
