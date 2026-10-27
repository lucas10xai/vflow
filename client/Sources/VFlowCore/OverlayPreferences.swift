import Foundation

/// Đọc/ghi "Vị trí" và "Cỡ" HUD ghi âm qua `UserDefaults` (lớp truy cập cô lập theo `VFLOW_HOME` —
/// xem `VFlowDefaults`). Giá trị thiếu hoặc lạ (vd. bản sau đổi tên) rơi về MẶC ĐỊNH CŨ — "Dưới màn
/// hình" + "Vừa", đúng hành vi trước khi có cài đặt — không bao giờ ném lỗi hay đổi vị trí âm thầm.
public enum OverlayPreferences {
    public static let positionKey = "overlayPosition"
    public static let sizeKey = "overlaySize"
    public static let defaultPosition: OverlayPosition = .bottom
    public static let defaultSize: OverlaySize = .medium

    public static func position(from defaults: UserDefaults) -> OverlayPosition {
        defaults.string(forKey: positionKey).flatMap(OverlayPosition.init(rawValue:)) ?? defaultPosition
    }

    public static func size(from defaults: UserDefaults) -> OverlaySize {
        defaults.string(forKey: sizeKey).flatMap(OverlaySize.init(rawValue:)) ?? defaultSize
    }

    public static func save(position: OverlayPosition, to defaults: UserDefaults) {
        defaults.set(position.rawValue, forKey: positionKey)
    }

    public static func save(size: OverlaySize, to defaults: UserDefaults) {
        defaults.set(size.rawValue, forKey: sizeKey)
    }
}
