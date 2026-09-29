import Testing
@testable import Macrowavers

@MainActor
struct AppModelTests {
    @Test func startEntersPlayingWithZeroScore() {
        let model = AppModel()
        model.start()
        model.addScore(5)
        model.start()

        #expect(model.phase == .playing)
        #expect(model.score == 0)
    }

    @Test func scoreOnlyChangesWhilePlaying() {
        let model = AppModel()
        model.addScore(10)
        #expect(model.score == 0)

        model.start()
        model.addScore(10)
        model.pause()
        model.addScore(10)

        #expect(model.score == 10)
        #expect(model.phase == .paused)
    }
}
