import Testing
@testable import VFlowCore

@Suite struct AudioHistoryValidationTests {
    @Test func mbWithinRangePasses() {
        #expect(AudioHistoryValidation.validateMb(200).isOk)
        #expect(AudioHistoryValidation.validateMb(50).isOk)
        #expect(AudioHistoryValidation.validateMb(2000).isOk)
    }

    @Test func mbBelowMinimumFails() {
        #expect(!AudioHistoryValidation.validateMb(49).isOk)
    }

    @Test func mbAboveMaximumFails() {
        #expect(!AudioHistoryValidation.validateMb(2001).isOk)
    }

    @Test func daysWithinRangePasses() {
        #expect(AudioHistoryValidation.validateDays(1).isOk)
        #expect(AudioHistoryValidation.validateDays(90).isOk)
    }

    @Test func daysOutsideRangeFails() {
        #expect(!AudioHistoryValidation.validateDays(0).isOk)
        #expect(!AudioHistoryValidation.validateDays(91).isOk)
    }
}

private extension Result {
    var isOk: Bool { if case .success = self { return true }; return false }
}

@Suite struct AudioPlaybackCoordinatorTests {
    @Test func startsNewPlaybackFromIdle() {
        var c = AudioPlaybackCoordinator()
        let intent = c.togglePlay(id: "a")
        #expect(intent == .startNew(id: "a"))
        #expect(c.state == .playing(id: "a"))
    }

    @Test func togglingSameIdWhilePlayingStops() {
        var c = AudioPlaybackCoordinator()
        _ = c.togglePlay(id: "a")
        let intent = c.togglePlay(id: "a")
        #expect(intent == .stop)
        #expect(c.state == .idle)
    }

    @Test func togglingDifferentIdWhilePlayingStartsNewOneInstead() {
        var c = AudioPlaybackCoordinator()
        _ = c.togglePlay(id: "a")
        let intent = c.togglePlay(id: "b")
        #expect(intent == .startNew(id: "b"))
        #expect(c.state == .playing(id: "b")) // chỉ MỘT bản đang phát tại một thời điểm
    }

    @Test func finishedClearsStateOnlyForMatchingId() {
        var c = AudioPlaybackCoordinator()
        _ = c.togglePlay(id: "a")
        c.finished(id: "b") // id khác — không ảnh hưởng (vd. bản cũ hoàn tất muộn sau khi đã đổi bài)
        #expect(c.state == .playing(id: "a"))
        c.finished(id: "a")
        #expect(c.state == .idle)
    }

    @Test func failedSetsErrorState() {
        var c = AudioPlaybackCoordinator()
        _ = c.togglePlay(id: "a")
        c.failed(id: "a", message: "không phát được")
        #expect(c.state == .error(id: "a", message: "không phát được"))
    }
}
