import SwiftUI
import VFlowCore

/// Menu nhỏ (mặt trời/mặt trăng) ở thanh công cụ cửa sổ chính: Hệ thống / Sáng / Tối. Chọn là áp dụng
/// ngay cho mọi cửa sổ vflow (xem `AppearanceStore`). Dấu tích hiện ở lựa chọn đang dùng.
struct AppearanceMenu: View {
    @ObservedObject var store: AppearanceStore

    var body: some View {
        Menu {
            Picker("Giao diện", selection: Binding(get: { store.preference }, set: { store.set($0) })) {
                ForEach(AppearancePreference.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: store.preference.symbol)
        }
        .menuIndicator(.hidden)
        .help("Giao diện: \(store.preference.title)")
        .accessibilityLabel("Giao diện")
        .accessibilityValue(store.preference.title)
    }
}

/// Viên "Hôm nay: N từ" ở thanh công cụ — bấm để mở tab Thống kê. Chữ dùng màu chính (đủ tương phản ở
/// cả hai giao diện), chỉ nền viên và biểu tượng mang màu nhấn.
struct TodayPillButton: View {
    let text: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 4) {
                Image(systemName: "waveform").foregroundStyle(Theme.accent)
                Text(text).foregroundStyle(Color.primary)
            }
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Xem thống kê")
        .accessibilityLabel(text)
        .accessibilityHint("Mở tab Thống kê")
    }
}
