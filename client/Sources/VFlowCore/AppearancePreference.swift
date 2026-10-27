import Foundation

/// Giao diện của TOÀN BỘ cửa sổ vflow: theo hệ thống (mặc định), luôn sáng, luôn tối. Lớp AppKit
/// (`AppearanceStore`) đặt `NSApp.appearance` theo giá trị này; ở đây chỉ có phần thuần (tên, biểu
/// tượng, lưu/đọc `UserDefaults`) để test được không cần cửa sổ.
public enum AppearancePreference: String, CaseIterable, Sendable {
    case system, light, dark

    public static let defaultsKey = "appearanceMode"
    public static let `default`: AppearancePreference = .system

    public var title: String {
        switch self {
        case .system: "Hệ thống"
        case .light: "Sáng"
        case .dark: "Tối"
        }
    }

    /// Biểu tượng SF Symbols trên thanh công cụ: mặt trời / mặt trăng / nửa vòng tròn (theo hệ thống).
    public var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// Giá trị lưu thiếu hoặc lạ ⇒ "Hệ thống" (mặc định), không bao giờ ép sáng/tối khi không có lựa
    /// chọn rõ ràng của người dùng.
    public static func load(from defaults: UserDefaults) -> AppearancePreference {
        defaults.string(forKey: defaultsKey).flatMap(AppearancePreference.init(rawValue:)) ?? .default
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
