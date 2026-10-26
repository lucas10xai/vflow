import SwiftUI
import VFlowCore

/// Tab "Cài đặt": chế độ mặc định, bật khi đăng nhập, hiện cửa sổ/biểu tượng thanh menu, lưu lịch
/// sử + xoá, đường dẫn dữ liệu (tôn trọng `VFLOW_HOME`), phiên bản.
struct SettingsView: View {
    let model: StatusModel
    let controller: AppController

    @AppStorage("showWindowOnLaunch") private var showWindowOnLaunch = ShowWindowPreference.defaultValue
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("historyEnabled") private var historyEnabled = true
    @State private var confirmClearHistory = false
    @State private var clearHistoryError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModeSection(mode: model.mode) { controller.mode = $0 }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Hành vi")
                Toggle("Bật khi đăng nhập", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { _ in controller.toggleLaunchAtLogin() }))
                    .font(.system(size: 13))
                Toggle("Hiện cửa sổ này khi mở app", isOn: $showWindowOnLaunch)
                    .font(.system(size: 13))
                Toggle("Hiện biểu tượng trên thanh menu", isOn: Binding(
                    get: { showMenuBarIcon },
                    set: { controller.showMenuBarIcon = $0; showMenuBarIcon = $0 }))
                    .font(.system(size: 13))
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Lịch sử")
                Toggle("Lưu lịch sử", isOn: Binding(
                    get: { historyEnabled },
                    set: { controller.historyEnabled = $0; historyEnabled = $0 }))
                    .font(.system(size: 13))
                Text("Tắt: không ghi mục mới, không xoá lịch sử đã có. Chỉ lưu văn bản, không lưu âm thanh.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Xoá toàn bộ lịch sử…") { confirmClearHistory = true }
                if let e = clearHistoryError {
                    Text(e).font(.system(size: 12)).foregroundStyle(Color.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "Dữ liệu")
                Text("Thư mục dữ liệu: \(controller.dataHomePath)")
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                Button("Mở thư mục dữ liệu") { controller.openDataFolder() }
                Text("Phiên bản vflow: \(AppVersion.current)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Button("Thoát vflow") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .alert("Xoá toàn bộ lịch sử?", isPresented: $confirmClearHistory) {
            Button("Xoá", role: .destructive) {
                do { try controller.clearHistory() } catch { clearHistoryError = "Không xoá được lịch sử: \(error.localizedDescription)" }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Không thể hoàn tác. Toàn bộ các câu đã đọc chính tả được lưu ở thiết bị này sẽ bị xoá.")
        }
    }
}

enum AppVersion {
    static let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
}
