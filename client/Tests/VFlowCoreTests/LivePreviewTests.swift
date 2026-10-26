import Foundation
import Testing
@testable import VFlowCore

@Suite struct LivePreviewCoordinatorTests {
    @Test func secondBeginWhileInFlightIsRefused() {
        let c = LivePreviewCoordinator()
        #expect(c.beginRequestIfAllowed())
        #expect(c.hasInFlightRequest)
        #expect(!c.beginRequestIfAllowed(), "lượt thứ hai khi đang bay phải bị bỏ qua, không xếp hàng")
        c.endRequest(outcome: .success)
        #expect(!c.hasInFlightRequest)
        #expect(c.beginRequestIfAllowed(), "sau khi lượt trước xong, lượt mới phải được phép")
    }

    @Test func busyDoesNotCountTowardConsecutiveFailures() {
        let c = LivePreviewCoordinator(maxConsecutiveFailures: 2)
        for _ in 0..<10 {
            #expect(c.beginRequestIfAllowed())
            c.endRequest(outcome: .busy)
        }
        #expect(!c.isPaused, "429 busy không phải lỗi — không được tạm dừng vì bận")
    }

    @Test func threeConsecutiveFailuresPausesForThisTake() {
        let c = LivePreviewCoordinator(maxConsecutiveFailures: 3)
        for _ in 0..<2 {
            #expect(c.beginRequestIfAllowed())
            c.endRequest(outcome: .failure)
            #expect(!c.isPaused)
        }
        #expect(c.beginRequestIfAllowed())
        c.endRequest(outcome: .failure)
        #expect(c.isPaused, "đủ 3 lỗi liên tiếp phải tạm dừng")
        #expect(!c.beginRequestIfAllowed(), "đã tạm dừng thì không gửi lượt nào nữa cho tới khi huỷ")
    }

    @Test func oneSuccessResetsConsecutiveFailureCount() {
        let c = LivePreviewCoordinator(maxConsecutiveFailures: 3)
        _ = c.beginRequestIfAllowed(); c.endRequest(outcome: .failure)
        _ = c.beginRequestIfAllowed(); c.endRequest(outcome: .failure)
        _ = c.beginRequestIfAllowed(); c.endRequest(outcome: .success)
        _ = c.beginRequestIfAllowed(); c.endRequest(outcome: .failure)
        _ = c.beginRequestIfAllowed(); c.endRequest(outcome: .failure)
        #expect(!c.isPaused, "thành công xen giữa phải đặt lại bộ đếm lỗi liên tiếp")
    }

    @Test func cancelForNewRecordingClearsPauseAndInFlight() {
        let c = LivePreviewCoordinator(maxConsecutiveFailures: 1)
        _ = c.beginRequestIfAllowed(); c.endRequest(outcome: .failure)
        #expect(c.isPaused)
        c.cancelForNewRecording()
        #expect(!c.isPaused && !c.hasInFlightRequest)
        #expect(c.beginRequestIfAllowed(), "lượt ghi âm mới phải được phép gửi lại từ đầu")
    }
}

@Suite struct LivePreviewTickTests {
    private func ok(_ text: String) -> Result<PartialResult, ClientError> {
        .success(PartialResult(text: text, audioMs: 1000, sttMs: 50))
    }
    private func busyError() -> ClientError { .engine(status: 429, code: "busy", message: "Đang bận") }

    @Test func busyResultIsReturnedButDoesNotCountAsFailure() async {
        let c = LivePreviewCoordinator(maxConsecutiveFailures: 1)
        let r = await LivePreviewTick.attempt(c, pcm: Data()) { _ in .failure(self.busyError()) }
        guard case .failure(let e) = r, EngineAPI.isPartialBusy(e) else { Issue.record("phải trả lỗi busy"); return }
        #expect(!c.isPaused)
        #expect(!c.hasInFlightRequest)
    }

    /// "Một yêu cầu bay" dùng ENGINE GIẢ thật (closure async) với một lượt chậm (mô phỏng mạng) —
    /// lượt thứ hai bắt đầu TRONG LÚC lượt đầu còn đang chạy phải bị bỏ qua (`nil`), không chờ/xếp hàng.
    @Test func whileOneRequestIsInFlightASecondConcurrentTickIsSkipped() async {
        let c = LivePreviewCoordinator()
        let slowStarted = Signal()
        let releaseSlow = Signal()
        let slow = Task {
            await LivePreviewTick.attempt(c, pcm: Data()) { _ in
                slowStarted.fire()
                await releaseSlow.wait()
                return self.ok("đang nói")
            }
        }
        await slowStarted.wait()
        // Lượt thứ hai bắt đầu TRONG KHI lượt đầu vẫn đang "bay" (chưa `releaseSlow`).
        let second = await LivePreviewTick.attempt(c, pcm: Data()) { _ in self.ok("không nên tới đây") }
        #expect(second == nil, "lượt thứ hai khi đang bận phải bị bỏ qua")
        releaseSlow.fire()
        let first = await slow.value
        guard case .success(let p) = first else { Issue.record("lượt đầu phải thành công"); return }
        #expect(p.text == "đang nói")
        // Sau khi lượt đầu xong, cổng lại mở cho lượt kế tiếp.
        #expect(!c.hasInFlightRequest)
    }

    @Test func cancelStopsFurtherSendsForThisRecordingTake() async {
        let c = LivePreviewCoordinator(maxConsecutiveFailures: 1)
        _ = await LivePreviewTick.attempt(c, pcm: Data()) { _ in .failure(.network("x")) }
        #expect(c.isPaused)
        let skipped = await LivePreviewTick.attempt(c, pcm: Data()) { _ in self.ok("không nên tới đây") }
        #expect(skipped == nil)
        c.cancelForNewRecording()
        let resumed = await LivePreviewTick.attempt(c, pcm: Data()) { _ in self.ok("lượt ghi mới") }
        guard case .success(let p) = resumed else { Issue.record("sau huỷ phải gửi lại được"); return }
        #expect(p.text == "lượt ghi mới")
    }
}

@Suite struct LivePreviewDisplayTests {
    @Test func shortTextIsUnchanged() {
        #expect(LivePreviewDisplay.capToTail("xin chào") == "xin chào")
    }

    @Test func longTextKeepsOnlyTheTail() {
        let long = String(repeating: "a", count: 300) + "TAIL"
        let capped = LivePreviewDisplay.capToTail(long, max: 10)
        #expect(capped == "aaaaaaTAIL")
        #expect(capped.count == 10)
    }
}

/// Cổng async đơn giản (fire/wait một lần) — dùng để ép hai `Task` chắc chắn chồng lấn thời gian
/// trong test, không dựa vào `Task.sleep` (không chắc chắn về thời điểm).
private final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func fire() {
        let cs = withLock {
            fired = true
            let cs = continuations
            continuations = []
            return cs
        }
        for c in cs { c.resume() }
    }

    func wait() async {
        let alreadyFired = withLock { fired }
        if alreadyFired { return }
        await withCheckedContinuation { cont in
            let resumeNow = withLock { () -> Bool in
                if fired { return true }
                continuations.append(cont)
                return false
            }
            if resumeNow { cont.resume() }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
