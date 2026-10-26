import SwiftUI
import VFlowCore

/// Hệ thống thiết kế (U1) phía SwiftUI/AppKit — bọc lại hằng số/hàm thuần của
/// `VFlowCore.DesignSystem` thành `Color`/khoảng cách dùng chung cho Tổng quan, Cài đặt, Chào
/// mừng, và sau này (U2) Lịch sử/Từ điển/Snippets. Giữ MỘT nơi định nghĩa để đổi màu nhấn không
/// phải sửa từng view.
enum Theme {
    /// Màu nhấn thương hiệu cam #ED6300 — dùng cho công tắc, mục chọn, nút chính (`.tint`/`.accentColor`).
    static let accent = Color(hex: BrandColor.accentHex)

    /// Chữ trên nền màu nhấn (đạt WCAG AA — xem `VFlowCore.ContrastText`); rơi về đen nếu không
    /// đọc được hex (không bao giờ xảy ra với hằng số hợp lệ, chỉ để không ép buộc).
    static let textOnAccent: Color = {
        switch ContrastText.textColor(onBackgroundHex: BrandColor.accentHex) {
        case .white: return .white
        case .black, .none: return .black
        }
    }()

    /// Lưới khoảng cách 4/8pt dùng trong các thẻ Tổng quan/Cài đặt.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let cardCornerRadius: CGFloat = 12
}

extension Color {
    /// `hex`: 6 ký tự RRGGBB, không dấu `#`. Dùng nội bộ cho `Theme.accent`.
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// Thẻ nền `.regularMaterial` bo góc nhẹ, dùng chung cho các khối ở Tổng quan — khớp chuẩn macOS
/// 14+ (vật liệu hệ thống thay vì màu nền tự vẽ), tôn trọng sáng/tối tự động.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.lg)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}
