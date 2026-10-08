import Foundation
import simd

/// Posizione della piattaforma su cui giace il drago, nello spazio immersivo
/// (origine ai piedi dell'utente, -Z davanti).
struct PlayAreaPlacement: Equatable {
    var position: SIMD3<Float>
    /// Rotazione attorno all'asse verticale (radianti).
    var yaw: Float
    /// Inclinazione verso l'utente (radianti): il bordo lontano si alza.
    var tilt: Float

    /// Pensata per un utente seduto: all'altezza delle ginocchia/tavolino, leggermente inclinata.
    static let seated = PlayAreaPlacement(position: SIMD3(0, 0.75, -0.6), yaw: 0, tilt: 15 * .pi / 180)

    static let tiltRange: ClosedRange<Float> = 0...(45 * .pi / 180)
    static let heightRange: ClosedRange<Float> = 0.3...1.8

    var rotation: simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: tilt, axis: SIMD3(1, 0, 0))
    }
}
