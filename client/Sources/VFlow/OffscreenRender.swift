import AppKit
import SwiftUI

/// Kiểm thử/chụp ảnh KHÔNG BAO GIỜ hiện cửa sổ lên màn hình thật (sự cố đã xảy ra: chủ dự án có
/// thể đang họp/trình chiếu bất cứ lúc nào — xem U2). Bật khi chạy với cờ `--render-offscreen`. Khi
/// bật: các `*WindowController.show()` KHÔNG BAO GIỜ gọi
/// `makeKeyAndOrderFront`/`orderFront`/`NSApp.activate()` — cửa sổ vẫn được tạo (để các flow hiện có
/// hoạt động bình thường) nhưng không bao giờ "lên màn hình"; nội dung thật sự được chụp bằng
/// `ImageRenderer` (SwiftUI) thẳng từ cây view — KHÔNG dùng `NSView.cacheDisplay`/
/// `bitmapImageRepForCachingDisplay` (đã đo thật: API đó không chụp đúng cây layer-backed của
/// SwiftUI khi cửa sổ chưa từng lên màn hình — ảnh ra "đông cứng" sai lệch, không đổi dù sửa
/// scroll/animation/layout, trong khi `ImageRenderer` chụp đúng ngay).
@MainActor
enum OffscreenRender {
    static let enabled = CommandLine.arguments.contains("--render-offscreen")

    /// Suy ra sáng/tối từ cờ `--appearance light|dark` (giống `NSApp.appearance`, nhưng
    /// `ImageRenderer` cần truyền tường minh — xem `capture`).
    static let colorScheme: ColorScheme? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--appearance"), args.count > i + 1 else { return nil }
        switch args[i + 1] {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }()

    /// Chụp một `View` SwiftUI thành PNG bằng `ImageRenderer` — không cần và không được phép có cửa
    /// sổ nào lên màn hình. `size`: khung logic (points) để đo nội dung (KHÔNG gồm thanh tiêu
    /// đề/toolbar của `NSWindow` — đó là chrome AppKit nằm NGOÀI cây SwiftUI, `ImageRenderer` chỉ
    /// chụp đúng cây view, không chụp được phần đó). `fixedHeight`: `true` ép đúng `size.height`
    /// (dùng cho nội dung đã tự cuộn/vừa khung, vd. HUD); `false` chỉ ép CHIỀU RỘNG, để
    /// `ImageRenderer` tự đo chiều cao THẬT theo nội dung — đã đo thật: `ScrollView` không chụp
    /// được qua `ImageRenderer` khi cửa sổ chưa từng lên màn hình (ra ảnh trống), nên nội dung cuộn
    /// được (Tổng quan/Lịch sử/Từ điển/Snippets) phải chụp KHÔNG BỌC `ScrollView`, để tự giãn hết cỡ.
    /// `colorScheme`: `NSApp.appearance` (đặt bởi `--appearance`) không tự áp dụng cho
    /// `ImageRenderer` (không có cửa sổ thật để suy ra ngữ cảnh vẽ màu động) — phải truyền tường
    /// minh qua `.preferredColorScheme` thì mới ra đúng sáng/tối.
    static func capture<V: View>(_ view: V, size: CGSize, fixedHeight: Bool = true, scale: CGFloat = 2,
                                 colorScheme: ColorScheme? = nil, to path: String) {
        let sized = fixedHeight
            ? AnyView(view.frame(width: size.width, height: size.height, alignment: .top).preferredColorScheme(colorScheme))
            : AnyView(view.frame(width: size.width, alignment: .top).preferredColorScheme(colorScheme))
        let renderer = ImageRenderer(content: sized)
        renderer.scale = scale
        // `.preferredColorScheme` chỉ đổi màu SwiftUI THUẦN (Color.primary…); `NSColor` động
        // (`.controlBackgroundColor`, `.windowBackgroundColor`…) đọc "current drawing appearance"
        // của AppKit tại thời điểm vẽ — không có cửa sổ thật thì phải ép tường minh bằng
        // `performAsCurrentDrawingAppearance`, nếu không luôn ra sáng bất kể cờ `--appearance`.
        let appearance = colorScheme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        var nsImageResult: NSImage?
        if let appearance {
            appearance.performAsCurrentDrawingAppearance { nsImageResult = renderer.nsImage }
        } else {
            nsImageResult = renderer.nsImage
        }
        guard let nsImage = nsImageResult else {
            FileHandle.standardError.write(Data("VFLOW_OFFSCREEN: ImageRenderer không ra được ảnh (\(path))\n".utf8))
            return
        }
        guard let tiff = nsImage.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("VFLOW_OFFSCREEN: không mã hoá được PNG (\(path))\n".utf8))
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("VFLOW_OFFSCREEN_SAVED \(path)")
        } catch {
            FileHandle.standardError.write(Data("VFLOW_OFFSCREEN: ghi tệp lỗi (\(path)): \(error)\n".utf8))
        }
    }

    /// Tự kiểm: xác nhận KHÔNG có cửa sổ nào của TIẾN TRÌNH NÀY đang on-screen — gọi trước khi
    /// thoát ở chế độ `--render-offscreen`, in kết quả ra stdout để có bằng chứng trong báo cáo.
    static func assertNoOnScreenWindow() {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            print("VFLOW_OFFSCREEN_CHECK không đọc được danh sách cửa sổ on-screen (coi như an toàn)")
            return
        }
        let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        if mine.isEmpty {
            print("VFLOW_OFFSCREEN_CHECK OK: 0 cửa sổ on-screen cho pid \(pid)")
        } else {
            print("VFLOW_OFFSCREEN_CHECK LỖI: \(mine.count) cửa sổ ON-SCREEN cho pid \(pid) — \(mine)")
        }
    }
}
