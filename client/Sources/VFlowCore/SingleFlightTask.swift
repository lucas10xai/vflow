import Foundation

/// Điều phối MỘT tác vụ async tại một thời điểm — dùng cho sheet "Dịch câu này" (V4/V5,
/// `TranslationSheet`): bấm "Dịch" khi đã có một lượt đang bay sẽ HUỶ lượt cũ rồi chạy lượt mới
/// (khác `LivePreviewCoordinator`, vốn BỎ QUA lượt mới khi đang bận — ở đây không có khái niệm
/// "lượt bị bỏ", người dùng luôn thấy đúng kết quả của yêu cầu MỚI NHẤT họ bấm). Tách khỏi
/// SwiftUI để test được (`client/Tests/VFlowCoreTests/SingleFlightTaskTests.swift`) không cần dựng
/// `View`/`@State` — `TranslationSheet.swift` chỉ gọi `run`/`cancel`/`isRunning`.
@MainActor
public final class SingleFlightTask<Success: Sendable> {
    private var current: Task<Void, Never>?

    public init() {}

    /// Huỷ tác vụ đang bay (nếu có) rồi chạy `operation` mới; `onResult` CHỈ gọi nếu tác vụ này
    /// chạy xong tới cuối mà KHÔNG bị huỷ giữa chừng (bởi một lần `run`/`cancel` khác) — đảm bảo
    /// kết quả của lượt CŨ không bao giờ ghi đè lên màn hình sau khi người dùng đã bấm lượt MỚI.
    public func run(_ operation: @escaping () async -> Success, onResult: @escaping (Success) -> Void) {
        current?.cancel()
        current = Task { @MainActor [weak self] in
            let result = await operation()
            guard let self, !Task.isCancelled else { return }
            // Phòng trường hợp hiếm: `operation` xong RẤT nhanh trước khi `cancel()` của một lượt
            // `run` khác (gọi ngay sau, đồng bộ) kịp set `current` — `Task.isCancelled` đã đọc tại
            // đây vẫn đúng vì `cancel()` luôn gọi trên `current` đang có TRƯỚC khi gán `Task` mới.
            self.current = nil
            onResult(result)
        }
    }

    /// Huỷ tác vụ đang bay (nếu có) — không chạy gì thay vào đó (dùng khi đóng sheet/bấm Huỷ).
    public func cancel() {
        current?.cancel()
        current = nil
    }

    public var isRunning: Bool { current != nil }
}
