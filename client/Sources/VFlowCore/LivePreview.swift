import Foundation

/// Điều phối "Xem chữ chạy trực tiếp" (`POST /v1/partial`, contract mục cùng tên): TỐI ĐA một yêu
/// cầu đang bay, bỏ qua lượt (không xếp hàng) khi đang bận, huỷ khi dừng/bắt đầu ghi âm mới, tạm
/// dừng cho lượt ghi âm hiện tại sau nhiều lỗi liên tiếp. Tách khỏi mạng/HTTP để test được bằng
/// engine giả (closure) — xem `LivePreviewTick`, `client/Tests/VFlowCoreTests/LivePreviewTests.swift`.
public final class LivePreviewCoordinator: @unchecked Sendable {
    public enum Outcome: Sendable { case success, busy, failure }

    private let lock = NSLock()
    private var inFlight = false
    private var consecutiveFailures = 0
    private var paused = false
    public let maxConsecutiveFailures: Int

    public init(maxConsecutiveFailures: Int = 3) {
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }

    /// Gọi TRƯỚC khi gửi yêu cầu — `true` ⇒ được phép gửi (đã đánh dấu đang bận, PHẢI gọi
    /// `endRequest` khi xong); `false` ⇒ bỏ qua lượt này (đang bận lượt trước, hoặc đã tạm dừng).
    public func beginRequestIfAllowed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !paused, !inFlight else { return false }
        inFlight = true
        return true
    }

    /// Gọi SAU khi có kết quả (chỉ khi `beginRequestIfAllowed()` vừa trả `true`) — bận (429) KHÔNG
    /// tính là lỗi (engine tự chặn, không phải lỗi thật); lỗi khác đếm dồn, đủ `maxConsecutiveFailures`
    /// lần liên tiếp ⇒ tạm dừng cho tới khi `cancelForNewRecording()`.
    public func endRequest(outcome: Outcome) {
        lock.lock(); defer { lock.unlock() }
        inFlight = false
        switch outcome {
        case .success: consecutiveFailures = 0
        case .busy: break
        case .failure:
            consecutiveFailures += 1
            if consecutiveFailures >= maxConsecutiveFailures { paused = true }
        }
    }

    /// Dừng ghi hoặc bắt đầu lượt ghi mới — huỷ "đang bay" và mở lại cho lượt kế (không mang lỗi
    /// liên tiếp từ lượt trước sang lượt sau).
    public func cancelForNewRecording() {
        lock.lock(); defer { lock.unlock() }
        inFlight = false
        consecutiveFailures = 0
        paused = false
    }

    public var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
    public var hasInFlightRequest: Bool { lock.lock(); defer { lock.unlock() }; return inFlight }
}

/// Một lượt gửi hoàn chỉnh (xin phép → gọi engine → báo kết quả) — hàm tự do để AppController dùng
/// THẬT (với `EngineAPI.partialRequest` qua `URLSession`) và test dùng GIẢ (engine giả bất kỳ).
public enum LivePreviewTick {
    @discardableResult
    public static func attempt(_ coordinator: LivePreviewCoordinator, pcm: Data,
                               send: @Sendable (Data) async -> Result<PartialResult, ClientError>) async -> Result<PartialResult, ClientError>? {
        guard coordinator.beginRequestIfAllowed() else { return nil }
        let result = await send(pcm)
        switch result {
        case .success:
            coordinator.endRequest(outcome: .success)
        case .failure(let e):
            coordinator.endRequest(outcome: EngineAPI.isPartialBusy(e) ? .busy : .failure)
        }
        return result
    }
}

/// HUD hiện tối đa 2 dòng, CHỈ PHẦN CUỐI (`client/Sources/VFlow/OverlayPanel.swift` dùng
/// `.lineLimit(2).truncationMode(.head)` để ngắt dòng thật theo độ rộng — việc đó phụ thuộc phông
/// chữ/độ rộng nên KHÔNG thuần/không test được ở đây). Hàm này chỉ chặn chuỗi quá dài (câu nói rất
/// dài) trước khi đưa vào UI, giữ đúng phần CUỐI, để không làm layout phình to vô hạn.
public enum LivePreviewDisplay {
    public static let maxSafeCharacters = 240

    public static func capToTail(_ text: String, max: Int = maxSafeCharacters) -> String {
        guard text.count > max else { return text }
        return String(text.suffix(max))
    }
}
