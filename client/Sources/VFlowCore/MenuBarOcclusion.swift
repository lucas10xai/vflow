import Foundation

/// Phát hiện biểu tượng thanh menu (NSStatusItem) có bị che (dưới notch, hoặc thanh menu đầy khiến
/// hệ thống co biểu tượng về 0) hay không — THUẦN: chỉ nhận toạ độ, không đụng AppKit, test được
/// (xem contract mục 4b). Lớp AppKit (`AppController`) đưa `item.button?.window?.frame` và
/// `NSScreen.main?.frame`/`auxiliaryTopLeftArea`/`auxiliaryTopRightArea` vào đây.
public enum MenuBarOcclusion {
    /// Chỉ cần hoành độ ngang (x) — biểu tượng thanh menu và notch luôn ở cùng dải y trên cùng.
    public struct Rect: Equatable, Sendable {
        public var minX: Double
        public var maxX: Double
        public init(minX: Double, maxX: Double) {
            self.minX = minX
            self.maxX = maxX
        }
        public var width: Double { maxX - minX }
    }

    /// `itemFrame` nil ⇒ AppKit CHƯA gán cửa sổ cho status item (vd. mới khởi động) — KHÔNG báo bị
    /// che để tránh báo nhầm. `auxiliaryLeft`/`auxiliaryRight` nil ⇒ máy không có notch (mọi vị trí
    /// trong `screenFrame` đều hợp lệ).
    public static func isOccluded(itemFrame: Rect?, screenFrame: Rect,
                                  auxiliaryLeft: Rect?, auxiliaryRight: Rect?) -> Bool {
        guard let item = itemFrame else { return false }
        if item.width <= 0 { return true } // hệ thống co biểu tượng về 0: thanh menu đầy
        guard item.minX >= screenFrame.minX, item.maxX <= screenFrame.maxX else { return true } // ngoài màn hình hẳn

        guard let left = auxiliaryLeft, let right = auxiliaryRight else { return false }
        let insideLeft = item.minX >= left.minX && item.maxX <= left.maxX
        let insideRight = item.minX >= right.minX && item.maxX <= right.maxX
        if insideLeft || insideRight { return false }
        // Giao với khoảng GIỮA hai dải phụ (vùng notch) ⇒ bị che.
        return item.maxX > left.maxX && item.minX < right.minX
    }
}

/// Thẻ nhắc "biểu tượng bị che" ở Tổng quan — đóng được, NHỚ theo NGÀY (không "đóng vĩnh viễn":
/// hoàn cảnh đổi mỗi ngày — cắm màn hình ngoài, đổi độ phân giải, cài/gỡ app khác…).
public enum MenuBarOcclusionReminder {
    public static let message = "Biểu tượng vflow đang nằm sau notch hoặc thanh menu đầy. Thoát bớt ứng dụng có biểu tượng thanh menu, rồi giữ ⌘ và kéo biểu tượng vflow sang sát bên phải; hoặc dùng menu ở Dock."

    /// `dismissedOnDayKey`: ngày (xem `dayKey`) của lần đóng gần nhất, `nil` = chưa đóng bao giờ.
    public static func shouldShow(isOccluded: Bool, todayKey: String, dismissedOnDayKey: String?) -> Bool {
        isOccluded && dismissedOnDayKey != todayKey
    }

    /// Khoá ngày ổn định ("yyyy-MM-dd") để so sánh — không phụ thuộc giờ/múi giờ trong ngày.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
