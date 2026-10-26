import Foundation

/// Bốn mục của cửa sổ chính "vflow". `flag` khớp `--open-tab <tongquan|lichsu|tudien|caidat>`
/// (dùng để chụp ảnh riêng từng tab).
enum MainTab: String, CaseIterable, Identifiable {
    case overview, history, dictionary, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Tổng quan"
        case .history: "Lịch sử"
        case .dictionary: "Từ điển"
        case .settings: "Cài đặt"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "book.closed"
        case .settings: "gearshape"
        }
    }

    init?(flag: String) {
        switch flag {
        case "tongquan": self = .overview
        case "lichsu": self = .history
        case "tudien": self = .dictionary
        case "caidat": self = .settings
        default: return nil
        }
    }
}
