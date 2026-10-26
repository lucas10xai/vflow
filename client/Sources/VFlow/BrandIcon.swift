import AppKit

/// Logo vflow (`client/Resources/branding/`, sinh bằng `scripts/make-icon.sh`):
/// - `AppIcon.icns` (từ `logo-main.png`) ⇒ biểu tượng app (Dock/Finder/Cmd-Tab/Giới thiệu), khai
///   trong Info.plist, không cần nạp tay.
/// - `menubar-mark-18{,@2x,@3x}.png` (từ `logo-mark.png`) ⇒ biểu tượng thanh menu, đầu cửa sổ
///   chính, cạnh chữ trên thanh trạng thái ghi âm — nạp ở đây.
///
/// Trạng thái (nghe/dịch/lỗi…) KHÔNG dựa riêng vào màu: logo màu cam giống nhau mọi lúc, phân biệt
/// bằng một chấm nhỏ phủ lên góc dưới-phải (`MenuBarBadge`) — khác nhau bằng HÌNH, không chỉ màu —
/// cộng với tooltip/nhãn trợ năng (xem `StatusMenu.iconState`).
enum MenuBarBadge: Equatable {
    case none
    /// Đang nghe (giữ phím hoặc đã khoá).
    case listening
    /// Đang nghe lệnh (Command Mode).
    case command
    /// Đang dịch.
    case busy
    /// Lỗi/thiếu quyền/xung đột phím.
    case warning
}

enum BrandIcon {
    /// Ảnh logo-mark 18pt @1x/@2x/@3x đóng gói trong bundle; `nil` nếu chưa đóng gói (vd. chạy từ
    /// `swift build`/`swift test` không qua `build-app.sh`) — nơi gọi tự rơi về SF Symbol cũ.
    static func menuBarMark() -> NSImage? {
        guard let dir = Bundle.main.resourcePath else { return nil }
        let img = NSImage()
        var any = false
        for suffix in ["", "@2x", "@3x"] {
            let path = "\(dir)/menubar-mark-18\(suffix).png"
            guard let data = FileManager.default.contents(atPath: path), let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = NSSize(width: 18, height: 18) // cùng kích thước LOGIC cho mọi mật độ (@1x/@2x/@3x)
            img.addRepresentation(rep)
            any = true
        }
        guard any else { return nil }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = false // logo có màu cam thương hiệu, không phải glyph đơn sắc
        return img
    }

    /// Ảnh logo-mark cỡ lớn hơn (đầu cửa sổ chính, ~28–32pt) — dùng cùng bộ tệp, phóng theo kích
    /// thước yêu cầu (AppKit tự chọn representation @2x/@3x có sẵn khi vẽ ở độ phân giải Retina).
    static func headerMark(pointSize: CGFloat = 28) -> NSImage? {
        guard let mark = menuBarMark() else { return nil }
        let img = mark.copy() as! NSImage
        img.size = NSSize(width: pointSize, height: pointSize)
        return img
    }

    /// Logo + chấm trạng thái phủ góc dưới-phải (7pt, viền trắng để nổi trên mọi nền thanh menu).
    static func statusImage(badge: MenuBarBadge) -> NSImage? {
        guard let mark = menuBarMark() else { return nil }
        guard badge != .none else { return mark }
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            mark.draw(in: rect)
            let badgeRect = NSRect(x: rect.maxX - 8, y: rect.minY, width: 8, height: 8)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1, dy: -1)).fill()
            Self.color(for: badge).setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
            return true
        }
    }

    private static func color(for badge: MenuBarBadge) -> NSColor {
        switch badge {
        case .none: return .clear
        case .listening: return .systemOrange
        case .command: return .systemBlue
        case .busy: return .systemTeal
        case .warning: return .systemRed
        }
    }
}
