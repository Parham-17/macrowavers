import Foundation
import QuartzCore
import simd
#if os(visionOS)
import ARKit
#endif

/// Dove si trovano gli occhi dell'utente (il "cavaliere"), così il drago può guardarlo in faccia.
/// Su visionOS usa il tracciamento del dispositivo di ARKit (nessun permesso richiesto);
/// se non è disponibile (es. simulatore) usa l'altezza tipica degli occhi di una persona seduta.
@MainActor
final class ViewerTracker {
    /// Occhi di una persona seduta, all'origine dello spazio immersivo.
    static let fallbackPosition = SIMD3<Float>(0, 1.15, 0)

    #if os(visionOS)
    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var isRunning = false
    #endif

    func start() async {
        #if os(visionOS)
        guard WorldTrackingProvider.isSupported, !isRunning else { return }
        do {
            try await session.run([worldTracking])
            isRunning = true
        } catch {
            print("⚠️ Head tracking unavailable: \(error)")
        }
        #endif
    }

    func stop() {
        #if os(visionOS)
        session.stop()
        isRunning = false
        #endif
    }

    /// Posizione degli occhi nello spazio della scena immersiva.
    func viewerPosition() -> SIMD3<Float> {
        #if os(visionOS)
        guard isRunning, worldTracking.state == .running,
              let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return Self.fallbackPosition
        }
        let column = device.originFromAnchorTransform.columns.3
        return SIMD3(column.x, column.y, column.z)
        #else
        return Self.fallbackPosition
        #endif
    }
}
