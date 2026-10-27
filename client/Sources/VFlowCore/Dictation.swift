import Foundation

/// HUD ngắn tiếng Việt cho `post.degraded_reason` (contract mục "Chế độ", item 7) — bản dự phòng
/// cục bộ đã dùng thay cho đám mây đã định; chữ đã chèn KHÔNG đổi, chỉ báo đúng nguyên nhân.
public enum DegradedText {
    public static func message(_ reason: String) -> String {
        switch reason {
        case "llm_timeout": return "9Router chậm — đã dùng bản làm sạch trong máy"
        case "llm_error": return "9Router lỗi — đã dùng bản làm sạch trong máy"
        case "guard": return "Bản viết lại bị chặn vì đổi nghĩa — đã dùng bản làm sạch trong máy"
        case "cloud_disabled": return "Đám mây đang tắt — dùng Làm sạch"
        default: return "Đã dùng bản làm sạch trong máy (\(reason))"
        }
    }
}

/// Quyết định sau khi engine trả kết quả: chèn gì, hiện gì. Thuần để test.
public enum DictationDecision {
    public struct Plan: Equatable, Sendable {
        public var insert: String?
        public var overlay: OverlayState
        /// Xoá bản âm thanh “thử lại” (thành công thật).
        public var clearRetry: Bool
    }

    public static func plan(for result: Result<TranscribeResult, ClientError>) -> Plan {
        switch result {
        case .failure(let e):
            return Plan(insert: nil, overlay: .error(ErrorText.message(e)), clearRetry: false)
        case .success(let r):
            let trimmed = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if r.silence || trimmed.isEmpty {
                return Plan(insert: nil, overlay: .notice(OverlayText.heardNothing), clearRetry: true)
            }
            if r.degraded, let reason = r.degradedReason {
                return Plan(insert: r.text, overlay: .notice(DegradedText.message(reason)), clearRetry: true)
            }
            if let code = r.rewriteError {
                // Hợp đồng: text vẫn dùng được (chưa viết lại) ⇒ vẫn dán, nhưng báo rõ.
                return Plan(insert: r.text, overlay: .error("Viết lại thư lỗi (\(code)), đã dán bản chưa viết lại"),
                            clearRetry: true)
            }
            return Plan(insert: r.text, overlay: .done, clearRetry: true)
        }
    }

    /// Thông điệp sau khi dán.
    public static func overlay(after paste: PasteOutcome, planned: OverlayState) -> OverlayState {
        switch paste {
        case .pastedRestored, .nothingToPaste: return planned
        case .pastedNotRestoredUserChanged: return planned
        case .pasteFailedTextLeftOnClipboard:
            return .error("Không dán được (thiếu quyền Trợ năng); chữ đã nằm trong clipboard, bấm ⌘V")
        }
    }
}

/// "Lỗi gần nhất" (thẻ ở Tổng quan, mục trong menu, thẻ "Có vấn đề cần xử lý") sau khi MỘT lượt kết thúc.
/// Lỗi chỉ giữ lại khi chính lượt vừa rồi lại lỗi; mọi kết quả khác (đã dán, "không nghe thấy gì", nhắc
/// nhẹ) xoá lỗi cũ — người dùng không phải bấm X sau khi đã dùng lại được bình thường.
public enum LastErrorPolicy {
    public static func after(overlay: OverlayState) -> String? {
        if case .error(let message) = overlay { return message }
        return nil
    }
}
