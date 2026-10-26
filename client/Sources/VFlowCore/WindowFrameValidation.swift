import CoreGraphics

/// Chuẩn hoá khung cửa sổ chính đã lưu (`NSWindow` frame) khi mở lại app — khung lưu từ lần trước có
/// thể không còn hợp lệ nếu màn hình đã bị tháo/đổi độ phân giải/sắp xếp lại giữa hai lần mở: nằm
/// NGOÀI mọi màn hình hiện có, NHỎ HƠN kích thước tối thiểu, hoặc LỚN HƠN màn hình chứa nó (U3). Hàm
/// thuần (không AppKit) để test được không cần cửa sổ/màn hình thật — xem `WindowFramePersistence`
/// (lớp AppKit gọi hàm này) và `VFlowTests/LayoutRegressionTests.swift`.
public enum WindowFrameValidation {
    /// Tách 4 số đầu (x y width height) khỏi chuỗi mô tả khung kiểu `NSWindow.frameDescriptor`
    /// (`"x y w h screenX screenY screenW screenH"`) — bỏ qua phần màn hình đã lưu, vì màn hình hiện
    /// tại mới là nguồn đáng tin để kẹp/định vị lại, không phải màn hình của lần chạy trước.
    public static func parseLeadingRect(_ descriptor: String) -> CGRect? {
        let parts = descriptor.split(separator: " ").compactMap { Double($0) }
        guard parts.count >= 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// `frame` có giao đủ lớn (>= `minOverlap` mỗi chiều) với ít nhất một màn hình trong `screens`
    /// không — tránh coi 1px chồng lấn ở rìa là "còn nhìn thấy được".
    public static func intersectsAnyScreen(_ frame: CGRect, screens: [CGRect], minOverlap: CGFloat = 40) -> Bool {
        screens.contains { screen in
            let i = frame.intersection(screen)
            return !i.isNull && i.width >= minOverlap && i.height >= minOverlap
        }
    }

    /// Màn hình giao nhiều diện tích nhất với `frame` (nil nếu không giao màn hình nào).
    static func containingScreen(_ frame: CGRect, screens: [CGRect]) -> CGRect? {
        screens.max { a, b in
            let ia = frame.intersection(a), ib = frame.intersection(b)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        }
    }

    /// Chuẩn hoá `frame`: kẹp kích thước vào `[minSize, kích thước màn hình chứa nó]`, giữ nguyên vị
    /// trí nếu còn hợp lệ (chỉ dịch vào trong nếu kẹp kích thước khiến tràn mép màn hình); nếu
    /// `frame` không giao màn hình nào (vd. màn hình ngoài đã tháo) thì đặt giữa `mainScreen`.
    /// `screens`/`mainScreen` rỗng/`nil` ⇒ trả `frame` nguyên văn (không có cơ sở để chuẩn hoá).
    public static func normalize(frame: CGRect, minSize: CGSize, screens: [CGRect], mainScreen: CGRect?) -> CGRect {
        guard !screens.isEmpty, let mainScreen else { return frame }
        let onScreen = intersectsAnyScreen(frame, screens: screens)
        let target = (onScreen ? containingScreen(frame, screens: screens) : nil) ?? mainScreen

        var width = max(frame.width, minSize.width)
        var height = max(frame.height, minSize.height)
        width = min(width, target.width)
        height = min(height, target.height)

        if onScreen {
            var x = frame.minX
            var y = frame.minY
            if x + width > target.maxX { x = target.maxX - width }
            if x < target.minX { x = target.minX }
            if y + height > target.maxY { y = target.maxY - height }
            if y < target.minY { y = target.minY }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        let x = mainScreen.midX - width / 2
        let y = mainScreen.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
