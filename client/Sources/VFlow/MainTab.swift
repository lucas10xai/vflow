import Foundation

/// Năm mục của cửa sổ chính "vflow". `flag` khớp `--open-tab <tongquan|lichsu|tudien|snippet|caidat>`
/// (dùng để chụp ảnh riêng từng tab).
enum MainTab: String, CaseIterable, Identifiable {
    case overview, history, dictionary, snippets, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Tổng quan"
        case .history: "Lịch sử"
        case .dictionary: "Từ điển"
        case .snippets: "Snippets"
        case .settings: "Cài đặt"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "book.closed"
        case .snippets: "text.badge.plus"
        case .settings: "gearshape"
        }
    }

    init?(flag: String) {
        switch flag {
        case "tongquan": self = .overview
        case "lichsu": self = .history
        case "tudien": self = .dictionary
        case "snippet": self = .snippets
        case "caidat": self = .settings
        default: return nil
        }
    }
}
