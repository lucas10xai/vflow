import AppKit

/// Logo vflow (`client/Resources/branding/`, sinh bằng `scripts/make-icon.sh`):
/// - `AppIcon.icns` (từ `logo-main.png`) ⇒ biểu tượng app (Dock/Finder/Cmd-Tab/Giới thiệu), khai
///   trong Info.plist, không cần nạp tay.
/// - `menubar-mark-18{,@2x,@3x}.png` (màu, từ `logo-mark.png`) ⇒ đầu cửa sổ chính, cạnh chữ trên
///   thanh trạng thái ghi âm — nạp ở đây.
/// - `menubar-mark-18-template{,@2x,@3x}.png` (đơn sắc đen+alpha, `make-icon-template.swift`) ⇒
///   biểu tượng THANH MENU THẬT — nạp với `isTemplate = true` để macOS tự vẽ TRẮNG trên thanh menu
///   tối và ĐEN trên thanh menu sáng (đúng chuẩn hệ điều hành; đây là lý do chủ dự án thấy biểu
///   tượng "trắng" trên máy của anh — thanh menu của anh ở giao diện tối).
///
/// Trạng thái (nghe/dịch/lỗi…) KHÔNG dựa vào màu (ảnh template chỉ có MỘT màu do hệ thống quyết
/// định): phân biệt bằng HÌNH DẠNG của một huy hiệu nhỏ ở góc dưới-phải — chấm đặc (đang nghe),
/// vòng (đang nghe lệnh), ngôi sao lấp lánh (đang dịch), dấu chấm than khoét (lỗi/thiếu quyền) —
/// cộng với tooltip/nhãn trợ năng luôn mô tả bằng chữ (xem `StatusMenu.iconState`).
enum MenuBarBadge: Equatable {
    case none
    /// Đang nghe (giữ phím hoặc đã khoá) — chấm đặc.
    case listening
    /// Đang nghe lệnh (Command Mode) — vòng.
    case command
    /// Đang dịch — ngôi sao lấp lánh.
    case busy
    /// Lỗi/thiếu quyền/xung đột phím — dấu chấm than khoét ở góc.
    case warning
}

enum BrandIcon {
    /// Nạp bộ ảnh 18pt @1x/@2x/@3x đóng gói trong bundle theo tên gốc `baseName`; `nil` nếu chưa
    /// đóng gói (vd. chạy từ `swift build`/`swift test` không qua `build-app.sh`).
    private static func loadMark(baseName: String) -> NSImage? {
        guard let dir = Bundle.main.resourcePath else { return nil }
        let img = NSImage()
        var any = false
        for suffix in ["", "@2x", "@3x"] {
            let path = "\(dir)/\(baseName)\(suffix).png"
            guard let data = FileManager.default.contents(atPath: path), let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = NSSize(width: 18, height: 18) // cùng kích thước LOGIC cho mọi mật độ (@1x/@2x/@3x)
            img.addRepresentation(rep)
            any = true
        }
        guard any else { return nil }
        img.size = NSSize(width: 18, height: 18)
        return img
    }

    /// Ảnh logo-mark MÀU (cam thương hiệu) 18pt @1x/@2x/@3x — dùng cho đầu cửa sổ chính và thanh
    /// trạng thái nổi, nơi màu cam có ý nghĩa thương hiệu, KHÔNG dùng cho biểu tượng thanh menu
    /// thật (xem `menuBarTemplateMark`).
    static func menuBarMark() -> NSImage? {
        guard let img = loadMark(baseName: "menubar-mark-18") else { return nil }
        img.isTemplate = false
        return img
    }

    /// Ảnh logo-mark TEMPLATE (đơn sắc đen+alpha) 18pt @1x/@2x/@3x — dùng CHO BIỂU TƯỢNG THANH MENU
    /// THẬT; `isTemplate = true` để macOS tự vẽ TRẮNG trên thanh menu tối, ĐEN trên thanh menu sáng.
    static func menuBarTemplateMark() -> NSImage? {
        guard let img = loadMark(baseName: "menubar-mark-18-template") else { return nil }
        img.isTemplate = true
        return img
    }

    /// Ảnh logo-mark MÀU cỡ lớn hơn (đầu cửa sổ chính, ~28–32pt) — dùng cùng bộ tệp màu, phóng theo
    /// kích thước yêu cầu (AppKit tự chọn representation @2x/@3x có sẵn khi vẽ ở độ phân giải Retina).
    static func headerMark(pointSize: CGFloat = 28) -> NSImage? {
        guard let mark = menuBarMark() else { return nil }
        let img = mark.copy() as! NSImage
        img.size = NSSize(width: pointSize, height: pointSize)
        return img
    }

    /// Biểu tượng thanh menu thật: logo template (trắng/đen tự động theo nền) + huy hiệu trạng thái
    /// PHÂN BIỆT BẰNG HÌNH, không dựa vào màu (ảnh template chỉ có một màu do hệ thống chọn) — xem
    /// `MenuBarBadge`. Luôn `isTemplate = true` kể cả khi có huy hiệu, vì huy hiệu được vẽ bằng
    /// cách thêm/khoét alpha trên CHÍNH ảnh template, không vẽ màu riêng.
    static func statusImage(badge: MenuBarBadge) -> NSImage? {
        guard let mark = menuBarTemplateMark() else { return nil }
        guard badge != .none else { return mark }
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            mark.draw(in: rect)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            drawBadge(badge, in: rect, ctx: ctx)
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Vẽ huy hiệu ở góc dưới-phải (đường kính ~7pt) trực tiếp lên alpha của ảnh template — chấm
    /// đặc (nghe), vòng (lệnh), ngôi sao lấp lánh (dịch), dấu chấm than PHỦ ĐÈ (lỗi/thiếu quyền).
    /// Dùng PHỦ ĐÈ (thêm alpha mới) thay vì khoét (xoá alpha có sẵn) cho MỌI huy hiệu — kể cả
    /// "khoét" theo gợi ý trong spec — vì góc dưới-phải của logo-mark thường TRONG SUỐT sẵn (glyph
    /// không lấp tới góc): khoét một vùng vốn đã rỗng không tạo ra khác biệt thấy được, đã kiểm
    /// bằng ảnh chụp thật (`--demo-icon`) trước khi chọn cách làm này.
    private static func drawBadge(_ badge: MenuBarBadge, in rect: NSRect, ctx: CGContext) {
        let d: CGFloat = 7
        let badgeRect = CGRect(x: rect.maxX - d - 1, y: rect.minY + 1, width: d, height: d)
        switch badge {
        case .none:
            return
        case .listening: // chấm đặc
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillEllipse(in: badgeRect)
        case .command: // vòng (khoét lõi khỏi chấm đặc)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillEllipse(in: badgeRect)
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: badgeRect.insetBy(dx: 1.6, dy: 1.6))
            ctx.setBlendMode(.normal)
        case .busy: // ngôi sao lấp lánh (4 cánh)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(sparkleStarPath(in: badgeRect))
            ctx.fillPath()
        case .warning: // tam giác cảnh báo khoét dấu chấm than — cùng hình với SF Symbol
            // "exclamationmark.triangle" đã dùng cho cảnh báo ở nơi khác trong app (StatusMenu),
            // và silhouette tam giác phân biệt rõ với tròn/vòng/sao ngay cả ở cỡ rất nhỏ.
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(warningTrianglePath(in: badgeRect))
            ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.addPath(exclamationPath(in: badgeRect.insetBy(dx: 1.6, dy: 0.6)))
            ctx.fillPath()
            ctx.setBlendMode(.normal)
        }
    }

    /// Hình ngôi sao lấp lánh 4 cánh (kim cương lồi-lõm xen kẽ) gọn trong `rect`.
    private static func sparkleStarPath(in rect: CGRect) -> CGPath {
        let cx = rect.midX, cy = rect.midY
        let outer = rect.width / 2
        let inner = outer * 0.38
        let path = CGMutablePath()
        let points = 8
        for i in 0..<points {
            let r = i.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(i) * (.pi / CGFloat(points / 2))
            let x = cx + r * cos(angle)
            let y = cy + r * sin(angle)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }

    /// Hình tam giác đều (đỉnh hướng lên), bo góc nhẹ, gọn trong `rect`.
    private static func warningTrianglePath(in rect: CGRect) -> CGPath {
        let top = CGPoint(x: rect.midX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.minY)
        let path = CGMutablePath()
        path.move(to: top)
        path.addLine(to: right)
        path.addLine(to: left)
        path.closeSubpath()
        return path
    }

    /// Hình dấu chấm than (thân chữ nhật thuôn + chấm tròn dưới) gọn trong `rect`.
    private static func exclamationPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let stemWidth = rect.width * 0.26
        let stemRect = CGRect(x: rect.midX - stemWidth / 2, y: rect.midY + rect.height * 0.08,
                              width: stemWidth, height: rect.height * 0.52)
        path.addRoundedRect(in: stemRect, cornerWidth: stemWidth / 2, cornerHeight: stemWidth / 2)
        let dotDiameter = stemWidth * 1.1
        let dotRect = CGRect(x: rect.midX - dotDiameter / 2, y: rect.minY, width: dotDiameter, height: dotDiameter)
        path.addEllipse(in: dotRect)
        return path
    }
}
