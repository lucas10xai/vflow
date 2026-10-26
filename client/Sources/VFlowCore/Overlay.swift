import Foundation

/// Các trạng thái của thanh trạng thái nổi (cộng “thông báo ngắn” dùng chung kiểu xong/lỗi).
public enum OverlayState: Equatable, Sendable {
    case listening(level: Float)
    /// Ghi "khoá" (hands-free, đúp ⌥): không cần giữ phím, bấm ⌥ để xong, Esc để huỷ.
    case listeningLocked(level: Float)
    /// Đang ghi lệnh (Command Mode, ⌥+⌃).
    case listeningCommand(level: Float)
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
    /// Hiện vòng xoay (đang dịch) THAY cho `symbol` — chỉ đúng một trong hai được hiện.
    public var showsSpinner: Bool
    /// Thời gian tự ẩn; nil = giữ tới khi trạng thái đổi.
    public var autoHide: TimeInterval?
    public var isError: Bool

    public init(symbol: String, text: String, accessibilityLabel: String, showsLevel: Bool,
                showsSpinner: Bool = false, autoHide: TimeInterval?, isError: Bool) {
        self.symbol = symbol
        self.text = text
        self.accessibilityLabel = accessibilityLabel
        self.showsLevel = showsLevel
        self.showsSpinner = showsSpinner
        self.autoHide = autoHide
        self.isError = isError
    }
}

public enum OverlayText {
    /// Giới hạn độ dài thông điệp lỗi trên thanh (menu vẫn hiện đầy đủ).
    public static let maxErrorChars = 90

    public static func present(_ s: OverlayState) -> OverlayPresentation {
        switch s {
        case .listening:
            return .init(symbol: "mic.fill", text: "Đang nghe", accessibilityLabel: "vflow đang nghe",
                         showsLevel: true, autoHide: nil, isError: false)
        case .listeningLocked:
            return .init(symbol: "mic.fill", text: "Đang nghe (đã khoá, bấm ⌥ để xong, Esc để huỷ)",
                         accessibilityLabel: "vflow đang nghe, đã khoá, bấm Option để xong, Esc để huỷ",
                         showsLevel: true, autoHide: nil, isError: false)
        case .listeningCommand:
            return .init(symbol: "command", text: "Đang nghe lệnh", accessibilityLabel: "vflow đang nghe lệnh",
                         showsLevel: true, autoHide: nil, isError: false)
        case .transcribing:
            return .init(symbol: "waveform", text: "Đang dịch", accessibilityLabel: "vflow đang dịch giọng nói",
                         showsLevel: false, showsSpinner: true, autoHide: nil, isError: false)
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

/// Chiều cao từng vạch của sóng âm trên thanh trạng thái (HUD) — hàm thuần, test được không cần
/// SwiftUI. Dùng CHUNG cho vạch có hoạt ảnh (nội suy mượt mỗi lần mức âm đổi) và vạch tĩnh (Reduce
/// Motion bật — không hoạt ảnh nhưng vẫn phải đổi NGAY theo mức âm, không phải lúc nào cũng một
/// chiều cao).
public enum WaveformMeter {
    /// Số lẻ để luôn có MỘT vạch giữa đúng tâm (distanceRatio = 0 ⇒ đạt chiều cao tối đa khi mức
    /// âm = 1) — số chẵn sẽ chia đôi "vạch giữa" thành hai vạch lệch tâm bằng nhau, không vạch nào
    /// thật sự cao nhất.
    public static let defaultBarCount = 7
    /// Tỉ lệ chiều cao tối thiểu (mức âm 0 vẫn thấy vạch, không biến mất hẳn).
    public static let minHeightRatio = 0.15

    /// Chiều cao chuẩn hoá (0...1) của vạch `barIndex` (0-based) trong tổng `barCount` vạch, ở mức
    /// âm `level`. Vạch GIỮA cao nhất, thấp dần ra hai bên (hình chuông nhẹ) để trông giống sóng âm
    /// thật hơn là một hàng cột đồng đều. `level` ngoài [0, 1] bị KẸP (không bao giờ ra âm hoặc vượt
    /// 1, kể cả khi bộ đo mic trả giá trị lỗi).
    public static func barHeight(level: Float, barIndex: Int, barCount: Int = defaultBarCount) -> Double {
        precondition(barCount > 0 && barIndex >= 0 && barIndex < barCount, "barIndex phải trong [0, barCount)")
        let clamped = Double(max(0, min(1, level)))
        let mid = Double(barCount - 1) / 2
        let distanceRatio = mid == 0 ? 0 : abs(Double(barIndex) - mid) / mid
        let shapeFactor = 1 - distanceRatio * 0.6
        return minHeightRatio + (1 - minHeightRatio) * clamped * shapeFactor
    }
}
