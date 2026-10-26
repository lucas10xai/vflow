import SwiftUI
import VFlowCore

/// `--render-offscreen caidat:<mục>`: thay `TabView` bằng thanh tab TỰ VẼ + nội dung KHÔNG bọc
/// `Form` — đã đo thật: cả `TabView` lẫn `Form(.formStyle(.grouped))` không chụp được qua
/// `ImageRenderer` khi cửa sổ chưa từng lên màn hình (ra ảnh "cấm" toàn khung, giống `List`/
/// `ScrollView`/`NavigationSplitView` — xem `OffscreenRender`). Thanh tab vẽ ở đây CHỨNG MINH biểu
/// tượng SF Symbols của cả 4 mục cùng lúc (mục G), nội dung bên dưới là mục đang chọn.
struct SettingsOffscreenPreview: View {
    let selected: SettingsCategory
    let model: StatusModel
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
            Divider()
            content
                .padding(20)
        }
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsCategory.allCases) { cat in
                VStack(spacing: 4) {
                    Image(systemName: cat.symbol).font(.system(size: 18))
                    Text(cat.title).font(.caption)
                }
                .foregroundStyle(cat == selected ? Theme.accent : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(cat == selected ? Theme.accent.opacity(0.12) : Color.clear)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch selected {
        case .general:
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Chế độ mặc định") {
                    ModeSection(mode: model.mode) { _ in }
                }
                GroupBox("Hành vi") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật khi đăng nhập", isOn: .constant(model.launchAtLogin))
                        Toggle("Hiện cửa sổ \"vflow\" khi mở app", isOn: .constant(true))
                        Toggle("Hiện biểu tượng trên thanh menu", isOn: .constant(true))
                    }
                }
            }
        case .cloud:
            VStack(alignment: .leading, spacing: 16) {
                Text("Âm thanh không bao giờ rời máy. Chế độ Gọn, Thư và Command Mode gửi CHỮ (không phải âm thanh) qua 9Router tới nhà cung cấp model.")
                    .font(.footnote).foregroundStyle(.secondary)
                if model.engineReady {
                    GroupBox("9Router") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Cho phép gửi chữ qua 9Router", isOn: .constant(true))
                            Text("Model: (xem Cài đặt › Đám mây thật để biết giá trị hiện tại)").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(model.engineBlocked ? model.engineSummary : "Đang chờ engine khởi động…")
                        .foregroundStyle(model.engineBlocked ? Color.red : .secondary)
                }
            }
        case .historyPrivacy:
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Lịch sử") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Lưu lịch sử", isOn: .constant(controller.historyEnabled))
                        Text("Tắt: không ghi mục mới, không xoá lịch sử đã có.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                GroupBox("Riêng tư") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Âm thanh không bao giờ được ghi xuống đĩa và không rời máy này.", systemImage: "waveform.badge.exclamationmark").font(.footnote)
                        Label("Chế độ Gọn, Thư và Command Mode gửi CHỮ qua 9Router.", systemImage: "text.bubble").font(.footnote)
                    }
                }
            }
        case .advanced:
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Dữ liệu") {
                    LabeledContent("Thư mục dữ liệu") { Text(controller.dataHomePath).textSelection(.enabled).font(.footnote) }
                }
                GroupBox("Phiên bản") {
                    LabeledContent("Phiên bản vflow", value: AppVersion.current)
                }
            }
        }
    }
}
