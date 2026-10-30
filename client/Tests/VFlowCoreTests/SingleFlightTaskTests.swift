import Testing
@testable import VFlowCore

/// `SingleFlightTask` điều phối sheet "Dịch câu này" (V5, mục 2f): một yêu cầu một lúc (bấm "Dịch"
/// lần hai HUỶ lần nhất, không chạy song song), huỷ giữa chừng không gọi `onResult`, lỗi mạng/kết
/// quả rỗng đi qua `onResult` nguyên vẹn (không phải việc của `SingleFlightTask`, nhưng xác nhận nó
/// không "nuốt" hay biến hình kết quả thật).
@MainActor
@Suite struct SingleFlightTaskTests {
    /// Cổng điều khiển tay: `resume()` mới cho tác vụ bên trong `operation` hoàn tất — mô phỏng
    /// "lượt cũ chậm trả lời, lượt mới bấm trước" mà không cần `Task.sleep` thật (nhanh, không cờ).
    final class Gate: @unchecked Sendable {
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { self.continuation = $0 } }
        func resume() { continuation?.resume(); continuation = nil }
    }

    @Test func deliversResultWhenNotCancelled() async {
        let t = SingleFlightTask<Int>()
        var delivered: Int?
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            t.run({ 42 }, onResult: { delivered = $0; cont.resume() })
        }
        #expect(delivered == 42)
        #expect(!t.isRunning)
    }

    /// Bấm "Dịch" lần hai TRƯỚC KHI lần nhất trả lời ⇒ lần nhất bị huỷ, `onResult` của nó KHÔNG
    /// BAO GIỜ được gọi (không được ghi đè lên kết quả của lần hai dù lần nhất xong SAU).
    @Test func secondRunCancelsFirstBeforeItDelivers() async {
        let t = SingleFlightTask<String>()
        let firstGate = Gate()
        var firstDelivered = false
        t.run({ await firstGate.wait(); return "cũ" }, onResult: { _ in firstDelivered = true })
        #expect(t.isRunning)

        var secondDelivered: String?
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            t.run({ "mới" }, onResult: { secondDelivered = $0; cont.resume() })
        }
        #expect(secondDelivered == "mới")

        // Giờ mới cho lượt cũ "trả lời" — vì đã bị huỷ, onResult của nó không được gọi.
        firstGate.resume()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!firstDelivered, "lượt cũ bị huỷ không được gọi onResult dù trả lời SAU lượt mới")
    }

    /// Bấm "Huỷ"/đóng sheet giữa chừng ⇒ không bao giờ gọi `onResult` (không hiện kết quả mồ côi
    /// sau khi người dùng đã huỷ và có thể đã đóng sheet).
    @Test func cancelSuppressesResult() async {
        let t = SingleFlightTask<String>()
        let gate = Gate()
        var delivered = false
        t.run({ await gate.wait(); return "x" }, onResult: { _ in delivered = true })
        #expect(t.isRunning)
        t.cancel()
        #expect(!t.isRunning)
        gate.resume()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!delivered)
    }

    /// `SingleFlightTask` chỉ điều phối — không biến hình giá trị trả về (lỗi mạng/kết quả rỗng đi
    /// qua nguyên vẹn, việc kiểm "rỗng không coi là thành công" thuộc `EngineAPIv4.parseTranslate`).
    @Test func passesThroughFailureResultUnchanged() async {
        let t = SingleFlightTask<Result<TranslationResult, ClientError>>()
        var delivered: Result<TranslationResult, ClientError>?
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            t.run({ .failure(.network("mất mạng")) }, onResult: { delivered = $0; cont.resume() })
        }
        guard case .failure(.network(let msg)) = delivered else { Issue.record("phải giữ đúng lỗi mạng"); return }
        #expect(msg == "mất mạng")
    }

    @Test func isRunningReflectsInFlightState() async {
        let t = SingleFlightTask<Int>()
        #expect(!t.isRunning)
        let gate = Gate()
        // Chờ ĐÚNG lúc `onResult` chạy (không `Task.sleep` cố định — máy đang bận chạy TOÀN bộ bộ
        // test song song có thể trễ hơn một khoảng thời gian cố định, ra test chập chờn giả).
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            t.run({ await gate.wait(); return 1 }, onResult: { _ in cont.resume() })
            #expect(t.isRunning)
            gate.resume()
        }
        #expect(!t.isRunning, "isRunning phải về false NGAY sau khi onResult đã chạy xong")
    }
}
