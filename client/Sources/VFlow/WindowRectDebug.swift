import AppKit

/// In toạ độ cửa sổ (hệ quy chiếu `screencapture -R`, gốc trên-trái) ra stdout khi biến môi trường
/// `VFLOW_PRINT_WINDOW_RECT=1` được đặt — CHỈ dùng để chụp ảnh riêng từng cửa sổ bằng
/// `screencapture -R` trong kiểm tự động (không cần quyền Ghi màn hình cho
/// `CGWindowListCopyWindowInfo`, vốn không có sẵn trong môi trường kiểm). Không có tác dụng gì khi
/// biến môi trường không được đặt (mặc định khi chủ dự án dùng app thật).
@MainActor
enum WindowRectDebug {
    static func printIfRequested(_ window: NSWindow, label: String, forceHeight: CGFloat? = nil) {
        guard ProcessInfo.processInfo.environment["VFLOW_PRINT_WINDOW_RECT"] == "1" else { return }
        // Ghim vị trí CỐ ĐỊNH (bỏ qua frame đã lưu từ lần chạy trước/`center()`) — máy kiểm có thể
        // nhiều màn hình/độ phân giải khác nhau; vị trí cố định tránh cửa sổ lấn sang vùng màn hình
        // có nội dung khác khi chụp bằng `screencapture -R` (toạ độ tuyệt đối, không theo cửa sổ).
        let size = window.frame.size
        let height = forceHeight ?? size.height
        // y=120 (gốc dưới-trái của AppKit): chừa khoảng cách với Dock để `screencapture -R` không
        // lẫn icon Dock vào ảnh (đã đo thật: y=40 bị Dock đè lên đáy cửa sổ).
        window.setFrame(NSRect(x: 80, y: 90, width: max(size.width, 960), height: height), display: true)
        guard let screen = window.screen ?? NSScreen.main else { return }
        let f = window.frame
        let x = Int(f.origin.x.rounded())
        let y = Int((screen.frame.height - f.origin.y - f.height).rounded())
        let w = Int(f.width.rounded())
        let h = Int(f.height.rounded())
        // `windowNumber` cuối dòng: cho phép chụp bằng `screencapture -l <windowNumber>` (CHỈ cửa sổ
        // này, không phải toàn màn hình) — số này do CHÍNH tiến trình tự biết (không cần enumerate
        // cửa sổ của tiến trình khác qua CGWindowListCopyWindowInfo, vốn cần quyền Ghi màn hình).
        print("VFLOW_WINDOW_RECT \(label) \(x) \(y) \(w) \(h) \(window.windowNumber)")
        fflush(stdout)
    }
}
