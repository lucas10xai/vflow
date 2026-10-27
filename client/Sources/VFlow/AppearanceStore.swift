import AppKit
import SwiftUI
import VFlowCore

/// Nguồn DUY NHẤT của lựa chọn giao diện Sáng/Tối/Hệ thống: thanh công cụ cửa sổ chính và Cài đặt ›
/// Chung cùng quan sát một đối tượng nên không bao giờ lệch nhau. Đặt `NSApp.appearance` ⇒ áp dụng NGAY
/// cho mọi cửa sổ vflow (chính, Cài đặt, Chào mừng, HUD) mà không cần mở lại.
@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    @Published private(set) var preference: AppearancePreference
    private let defaults: UserDefaults
    private let apply: (NSAppearance?) -> Void
    /// Cờ dòng lệnh `--appearance light|dark` (chụp ảnh/kiểm thử) thắng giá trị đã lưu lúc khởi động —
    /// nếu không, "Hệ thống" mặc định sẽ xoá mất giao diện mà công cụ chụp ảnh đã ép.
    private let launchOverrideActive: Bool

    /// `apply` mặc định đặt `NSApp.appearance`; test truyền closure riêng để không đụng trạng thái chung.
    init(defaults: UserDefaults = VFlowDefaults.resolve(),
         arguments: [String] = CommandLine.arguments,
         apply: @escaping (NSAppearance?) -> Void = { NSApp.appearance = $0 }) {
        self.defaults = defaults
        self.apply = apply
        self.launchOverrideActive = arguments.contains("--appearance")
        self.preference = AppearancePreference.load(from: defaults)
    }

    static func nsAppearance(for preference: AppearancePreference) -> NSAppearance? {
        switch preference {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Áp dụng giá trị đã lưu khi app khởi động (gọi lúc dựng cửa sổ chính). Có `--appearance` ⇒ bỏ qua.
    func applyAtLaunch() {
        guard !launchOverrideActive else { return }
        apply(Self.nsAppearance(for: preference))
    }

    /// Người dùng chọn: áp dụng ngay + lưu để lần mở sau giữ nguyên.
    func set(_ new: AppearancePreference) {
        preference = new
        new.save(to: defaults)
        apply(Self.nsAppearance(for: new))
    }
}
