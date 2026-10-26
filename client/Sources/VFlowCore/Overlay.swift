import Foundation

/// Bốn trạng thái của thanh trạng thái nổi (cộng “thông báo ngắn” dùng chung kiểu xong/lỗi).
public enum OverlayState: Equatable, Sendable {
    case listening(level: Float)
    case transcribing
    case done
    case notice(String)
    case error(String)
}

public struct OverlayPresentation: Equatable, Sendable {
    public var symbol: String
    public var text: String
    public var accessibilityLabel: String
    public var showsLevel: Bool
    /// Thời gian tự ẩn; nil = giữ tới khi trạng thái đổi.
    public var autoHide: TimeInterval?
    public var isError: Bool
}

public enum OverlayText {
    /// Giới hạn độ dài thông điệp lỗi trên thanh (menu vẫn hiện đầy đủ).
    public static let maxErrorChars = 90

    public static func present(_ s: OverlayState) -> OverlayPresentation {
        switch s {
        case .listening:
            return .init(symbol: "mic.fill", text: "Đang nghe", accessibilityLabel: "vflow đang nghe",
                         showsLevel: true, autoHide: nil, isError: false)
        case .transcribing:
            return .init(symbol: "waveform", text: "Đang dịch", accessibilityLabel: "vflow đang dịch giọng nói",
                         showsLevel: false, autoHide: nil, isError: false)
        case .done:
            return .init(symbol: "checkmark.circle.fill", text: "Xong", accessibilityLabel: "vflow đã chèn chữ",
                         showsLevel: false, autoHide: 1.0, isError: false)
        case .notice(let m):
            return .init(symbol: "info.circle", text: m, accessibilityLabel: "vflow: \(m)",
                         showsLevel: false, autoHide: 1.5, isError: false)
        case .error(let m):
            let short = m.count > maxErrorChars ? String(m.prefix(maxErrorChars - 1)) + "…" : m
            return .init(symbol: "exclamationmark.triangle.fill", text: "Lỗi: \(short)",
                         accessibilityLabel: "vflow lỗi: \(m)", showsLevel: false, autoHide: 6, isError: true)
        }
    }

    public static let cancelled = "Đã huỷ"
    public static let heardNothing = "Không nghe thấy gì"
}
