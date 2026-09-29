import Observation

/// App-wide state. One instance lives in the app and is injected into the environment.
/// Keep gameplay rules here (or in dedicated types under Model/) so they are unit-testable
/// without RealityKit or a headset.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case menu
        case playing
        case paused
    }

    private(set) var phase: Phase = .menu
    private(set) var score = 0

    func start() {
        score = 0
        phase = .playing
    }

    func pause() {
        guard phase == .playing else { return }
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .playing
    }

    func addScore(_ points: Int) {
        guard phase == .playing, points > 0 else { return }
        score += points
    }
}
