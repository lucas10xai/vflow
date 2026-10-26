import Foundation

/// Lấy đoạn đang chọn khi bắt đầu Command Mode (contract/engine-api.md, mục "Command Mode"):
/// thử Accessibility (`kAXSelectedTextAttribute`) trước; không có (terminal, app tuỳ biến) thì thử
/// sao chép tổng hợp ⌘C có kiểm soát — lưu NGUYÊN clipboard, gửi ⌘C, chờ tối đa `timeout` thấy
/// `changeCount` đổi thì đọc chuỗi rồi KHÔI PHỤC clipboard; không đổi ⇒ không có đoạn chọn.
/// `nil` ⇒ không có đoạn chọn (chế độ soạn mới, `draft`).
@MainActor
public enum SelectionCapture {
    public static let defaultTimeout: TimeInterval = 0.25
    public static let defaultPollInterval: Duration = .milliseconds(25)

    public static func capture(
        ax: () -> String?,
        pasteboard: PasteboardStore,
        sendCopy: () -> Bool,
        now: () -> TimeInterval,
        sleep: (Duration) async -> Void,
        pollInterval: Duration = defaultPollInterval,
        timeout: TimeInterval = defaultTimeout
    ) async -> String? {
        if let s = ax(), !s.isEmpty { return s }
        let saved = pasteboard.snapshot()
        let before = pasteboard.changeCount
        guard sendCopy() else { return nil }
        let deadline = now() + timeout
        while now() < deadline {
            await sleep(pollInterval)
            if pasteboard.changeCount != before {
                let text = plainText(in: pasteboard.snapshot())
                pasteboard.restore(saved)
                return text
            }
        }
        return nil
    }

    static func plainText(in snapshot: PasteboardSnapshot) -> String? {
        for item in snapshot.items {
            for r in item.representations where r.type == "public.utf8-plain-text" {
                return String(data: r.data, encoding: .utf8)
            }
        }
        return nil
    }
}
