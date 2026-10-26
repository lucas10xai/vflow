import Foundation

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
