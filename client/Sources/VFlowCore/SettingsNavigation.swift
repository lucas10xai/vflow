import Foundation

/// Các mục cấp một của cửa sổ Cài đặt — CHỈ 5 mục để thanh tab ngang không phải cắt chữ (bản 8 mục cũ
/// cắt 6/8 nhãn). Gộp theo nghĩa: Chung (chế độ mặc định, hành vi, giao diện, micro) · Giọng nói (phím
/// tắt, dấu câu, nói nhỏ, chữ trực tiếp, tự dừng, giọng điệu, hành động) · Ứng dụng (luật theo app) ·
/// Dữ liệu & Riêng tư (lịch sử, lưu âm thanh, thống kê, xuất/nhập, chẩn đoán) · Nâng cao (9Router,
/// độ trễ, thông tin kỹ thuật).
///
/// `rawValue` mới là tên tiếng Anh ngắn; `init?(rawValue:)` còn nhận TÊN CŨ của 8 mục trước khi gộp
/// (`hotkeys`, `cloud`, `historyPrivacy`) và đưa về đúng mục mới — mọi nơi gọi cũ (cờ
/// `--open-settings-tab`, `--render-offscreen caidat:<mục>`, `openSettingsWindow(tab:)`) vẫn tới đúng chỗ.
public enum SettingsPane: CaseIterable, Sendable, Hashable, RawRepresentable {
    case general, voice, apps, data, advanced

    public init?(rawValue: String) {
        guard let pane = Self.resolve(rawValue) else { return nil }
        self = pane
    }

    public var rawValue: String {
        switch self {
        case .general: "general"
        case .voice: "voice"
        case .apps: "apps"
        case .data: "data"
        case .advanced: "advanced"
        }
    }

    /// Tên mục (mới và cũ) ⇒ mục hiện tại; `nil` nếu không biết.
    public static func resolve(_ name: String) -> SettingsPane? {
        switch name {
        case "general": .general
        case "voice", "hotkeys": .voice // "Phím tắt" cũ nay nằm trong Giọng nói
        case "apps": .apps
        case "data", "historyPrivacy": .data // "Lịch sử & riêng tư" cũ nay nằm trong Dữ liệu & Riêng tư
        case "advanced", "cloud": .advanced // "Đám mây" cũ nay nằm trong Nâng cao
        default: nil
        }
    }

    public var title: String {
        switch self {
        case .general: "Chung"
        case .voice: "Giọng nói"
        case .apps: "Ứng dụng"
        case .data: "Dữ liệu & Riêng tư"
        case .advanced: "Nâng cao"
        }
    }
}
