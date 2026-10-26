import SwiftUI
import VFlowCore

/// Tab "Tổng quan": đúng nội dung cửa sổ trạng thái cũ (M3b) — engine, model, 3 quyền, chế độ,
/// lỗi gần nhất, cảnh báo xung đột Haynoi, hướng dẫn giữ ⌥ trái. Dùng CHUNG `StatusModel` với menu
/// thanh trạng thái nên hai nơi không bao giờ nói khác nhau.
struct OverviewView: View {
    let model: StatusModel
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let warning = model.conflictWarning {
                ConflictBanner(text: warning)
            }
            Label("Giữ ⌥ Option trái để nói, nhả ra để chữ hiện ở chỗ con trỏ", systemImage: "mic.circle")
                .font(.system(size: 13, weight: .medium))
                .accessibilityLabel("Giữ Option trái để nói, nhả ra để chữ hiện ở chỗ con trỏ")

            if let status = model.modelBootstrapStatus {
                Text(status).font(.system(size: 13))
                    .foregroundStyle(status.hasPrefix("Chép model lần đầu lỗi") ? Color.red : Color.secondary)
            }

            EngineSection(model: model)
            PermissionsSection(permissions: model.permissions)
            ModeSection(mode: model.mode) { controller.mode = $0 }

            if let error = model.lastError {
                ErrorSection(text: error)
            }

            ActionsSection(model: model, controller: controller)

            Text("Không thấy biểu tượng trên thanh menu? Tắt/mở lại ở Cài đặt › “Hiện biểu tượng trên thanh menu”, hoặc dùng biểu tượng vflow ở Dock.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ConflictBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
    }
}

private struct EngineSection: View {
    let model: StatusModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Engine")
            Text(model.engineSummary).font(.system(size: 13))
            if model.models.isEmpty {
                Text("Chưa đọc được /healthz").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                ForEach(model.models, id: \.id) { m in
                    HStack(spacing: 6) {
                        Image(systemName: m.loaded ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(m.loaded ? Color.green : Color.orange)
                        Text(EngineAPI.menuLine(m)).font(.system(size: 13))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct PermissionsSection: View {
    let permissions: [PermissionItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Quyền macOS")
            ForEach(permissions, id: \.kind) { p in
                HStack {
                    Label(p.kind.title, systemImage: p.kind.symbol)
                        .font(.system(size: 13))
                    Spacer()
                    Text(p.statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(p.granted ? Color.green : Color.orange)
                    Button("Cấp quyền…") {
                        p.kind.request()
                        p.kind.openSettings()
                    }
                    .accessibilityLabel("Cấp quyền \(p.kind.title)")
                    .disabled(p.granted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(p.kind.title): \(p.statusText)")
            }
        }
    }
}

struct ModeSection: View {
    let mode: DictationMode
    let onChange: @MainActor (DictationMode) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Chế độ")
            Picker("Chế độ", selection: Binding(get: { mode }, set: onChange)) {
                ForEach(DictationMode.allCases, id: \.self) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct ErrorSection: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "Lỗi gần nhất")
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct ActionsSection: View {
    let model: StatusModel
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Thao tác")
            HStack(spacing: 10) {
                Button("Thử lại lần cuối") { controller.retryLast() }
                    .disabled(!model.canRetryLast)
                Button("Khởi động lại engine") { controller.restartEngine() }
                Button("Mở thư mục dữ liệu") { controller.openDataFolder() }
            }
        }
    }
}
