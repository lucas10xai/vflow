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

            CloudSettingsSection(model: model, controller: controller)

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

/// Mục "Đám mây (9Router)": `GET/PUT /v1/settings` — công tắc gửi chữ qua 9Router, model, thời gian
/// chờ, công tắc "Nhấn Enter bằng giọng". Hiệu lực ngay, lỗi `bad_request` của engine hiện tiếng Việt.
struct CloudSettingsSection: View {
    let model: StatusModel
    let controller: AppController

    @State private var loaded = false
    @State private var loadError: ClientError?
    @State private var cloudLlm = true
    @State private var llmModelText = ""
    @State private var timeoutSeconds = 8
    @State private var actionsEnabled = true
    @State private var saveError: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Đám mây (9Router)")
            Text("Âm thanh không bao giờ rời máy. Chế độ Gọn, Thư và Command Mode gửi CHỮ (không phải âm thanh) qua 9Router tới nhà cung cấp model.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            body_
        }
        .task(id: model.engineReady) {
            guard model.engineReady, !loaded else { return }
            await load()
        }
    }

    @ViewBuilder private var body_: some View {
        if model.engineBlocked {
            Text(model.engineSummary).font(.system(size: 13)).foregroundStyle(Color.red)
        } else if !model.engineReady {
            Text("Đang chờ engine khởi động…").font(.system(size: 13)).foregroundStyle(.secondary)
        } else if let e = loadError {
            VStack(alignment: .leading, spacing: 6) {
                Text(ErrorText.message(e)).font(.system(size: 13)).foregroundStyle(Color.red)
                Button("Thử lại") { Task { await load() } }
            }
        } else if !loaded {
            Text("Đang tải…").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Cho phép gửi chữ qua 9Router", isOn: $cloudLlm)
                .font(.system(size: 13))
                .onChange(of: cloudLlm) { _, v in Task { await save(.init(cloudLlm: v)) } }
            VStack(alignment: .leading, spacing: 4) {
                Text("Model").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    TextField("vd. ag/gemini-3.8-flash (để trống = chưa đặt)", text: $llmModelText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                        .onSubmit { Task { await save(.init(llmModel: .some(llmModelText.isEmpty ? nil : llmModelText))) } }
                    Button("Lưu") { Task { await save(.init(llmModel: .some(llmModelText.isEmpty ? nil : llmModelText))) } }
                }
                if llmModelText.isEmpty {
                    Text("Chưa đặt model: Gọn/Thư/Command Mode sẽ không chạy được.")
                        .font(.system(size: 11)).foregroundStyle(Color.orange)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Thời gian chờ (giây)").font(.system(size: 12)).foregroundStyle(.secondary)
                Stepper(value: $timeoutSeconds, in: 1...30) { Text("\(timeoutSeconds) s") }
                    .frame(maxWidth: 160)
                    .onChange(of: timeoutSeconds) { _, v in Task { await save(.init(llmTimeoutMs: v * 1000)) } }
            }
            Toggle("Nhấn Enter bằng giọng", isOn: $actionsEnabled)
                .font(.system(size: 13))
                .onChange(of: actionsEnabled) { _, v in Task { await save(.init(actionsEnabled: v)) } }
            if let e = saveError {
                Text(e).font(.system(size: 13)).foregroundStyle(Color.red)
            }
        }
    }

    private func load() async {
        switch await controller.fetchSettings() {
        case .success(let s): apply(s); loadError = nil
        case .failure(let e): loadError = e
        }
        loaded = true
    }

    private func apply(_ s: AppSettings) {
        cloudLlm = s.cloudLlm
        llmModelText = s.llmModel ?? ""
        timeoutSeconds = max(1, s.llmTimeoutMs / 1000)
        actionsEnabled = s.actionsEnabled
    }

    private func save(_ patch: SettingsPatch) async {
        saving = true
        let result = await controller.applySettingsPatch(patch)
        saving = false
        switch result {
        case .success(let s): apply(s); saveError = nil
        case .failure(let e): saveError = ErrorText.message(e)
        }
    }
}
