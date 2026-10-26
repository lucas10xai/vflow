import Foundation

/// Bốn mục của cửa sổ chính "vflow" (Cài đặt là CỬA SỔ RIÊNG chuẩn macOS — xem `SettingsWindow.swift`
/// — không còn nằm trong thanh bên này). `flag` khớp `--open-tab <tongquan|lichsu|tudien|snippet>`;
/// `caidat` vẫn được chấp nhận ở `main.swift` nhưng mở cửa sổ Cài đặt thay vì chọn mục thanh bên
/// (dùng để chụp ảnh từng mục).
enum MainTab: String, CaseIterable, Identifiable {
    case overview, history, dictionary, snippets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Tổng quan"
        case .history: "Lịch sử"
        case .dictionary: "Từ điển"
        case .snippets: "Snippets"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "book.closed"
        case .snippets: "text.badge.plus"
        }
    }

    /// Nhóm thanh bên: "Sử dụng" (Tổng quan, Lịch sử) và "Cá nhân hoá" (Từ điển, Snippets).
    enum Group: String, CaseIterable, Identifiable {
        case usage = "Sử dụng"
        case personalization = "Cá nhân hoá"
        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .overview, .history: .usage
        case .dictionary, .snippets: .personalization
        }
    }

    /// Phím tắt chuyển mục (⌘1…⌘4, theo thứ tự `allCases`).
    var keyboardShortcutDigit: Character {
        switch self {
        case .overview: "1"
        case .history: "2"
        case .dictionary: "3"
        case .snippets: "4"
        }
    }

    init?(flag: String) {
        switch flag {
        case "tongquan": self = .overview
        case "lichsu": self = .history
        case "tudien": self = .dictionary
        case "snippet": self = .snippets
        default: return nil
        }
    }
}
