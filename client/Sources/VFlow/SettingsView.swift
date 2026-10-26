import SwiftUI
import VFlowCore

/// Bốn mục của cửa sổ Cài đặt (`SettingsWindow.swift`) — xem mô tả từng mục ở từng `*SettingsTab`
/// bên dưới. Giữ TOÀN BỘ hành vi/kết nối engine cũ (U1: chỉ sắp xếp lại vào cửa sổ chuẩn macOS).
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, cloud, historyPrivacy, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Chung"
        case .cloud: "Đám mây"
        case .historyPrivacy: "Lịch sử & riêng tư"
        case .advanced: "Nâng cao"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .cloud: "cloud"
        case .historyPrivacy: "lock.shield"
        case .advanced: "wrench.and.screwdriver"
        }
    }
}

/// Bộ chọn chế độ dạng Picker gọn (dùng ở Cài đặt › Chung; Tổng quan dùng `ModeCard`, dạng thẻ đầy
/// đủ hơn — cùng nguồn `DictationMode`/`ModeCloudLabel` nên không bao giờ nói khác nhau).
struct ModeSection: View {
    let mode: DictationMode
    let onChange: @MainActor (DictationMode) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Chế độ", selection: Binding(get: { mode }, set: onChange)) {
                ForEach(DictationMode.allCases, id: \.self) { m in
                    Text(m.title).tag(m)
                }
            }
            .labelsHidden()
            Text(mode.subtitle).font(.footnote).foregroundStyle(.secondary)
            Text(ModeCloudLabel.text(mode))
                .font(.caption)
                .foregroundStyle(mode.sendsTextToCloud ? Color.orange : Color.secondary)
        }
    }
}

/// Mục "Chung": chế độ mặc định, bật khi đăng nhập, hiện cửa sổ khi mở app, biểu tượng thanh menu.
struct GeneralSettingsTab: View {
    let model: StatusModel
    let controller: AppController

    @AppStorage("showWindowOnLaunch") private var showWindowOnLaunch = ShowWindowPreference.defaultValue
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Form {
            Section("Chế độ mặc định") {
                ModeSection(mode: model.mode) { controller.mode = $0 }
            }
            Section("Hành vi") {
                Toggle("Bật khi đăng nhập", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { _ in controller.toggleLaunchAtLogin() }))
                Toggle("Hiện cửa sổ \"vflow\" khi mở app", isOn: $showWindowOnLaunch)
                Toggle("Hiện biểu tượng trên thanh menu", isOn: Binding(
                    get: { showMenuBarIcon },
                    set: { controller.showMenuBarIcon = $0; showMenuBarIcon = $0 }))
                    .help("Biểu tượng thanh menu chỉ là phụ — cách điều khiển chính là cửa sổ \"vflow\" (Dock, ⌘-Tab).")
            }
            Section {
                Button("Thoát vflow") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .formStyle(.grouped)
    }
}

/// Mục "Lịch sử & riêng tư": công tắc lưu lịch sử + xoá toàn bộ, câu giải thích riêng tư.
struct HistoryPrivacySettingsTab: View {
    let controller: AppController
    @AppStorage("historyEnabled") private var historyEnabled = true
    @State private var confirmClearHistory = false
    @State private var clearHistoryError: String?

    var body: some View {
        Form {
            Section("Lịch sử") {
                Toggle("Lưu lịch sử", isOn: Binding(
                    get: { historyEnabled },
                    set: { controller.historyEnabled = $0; historyEnabled = $0 }))
                Text("Tắt: không ghi mục mới, không xoá lịch sử đã có. Chỉ lưu văn bản, không bao giờ lưu âm thanh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Xoá toàn bộ lịch sử…", role: .destructive) { confirmClearHistory = true }
                if let e = clearHistoryError {
                    Text(e).font(.footnote).foregroundStyle(Color.red)
                }
            }
            Section("Riêng tư") {
                Label("Âm thanh không bao giờ được ghi xuống đĩa và không rời máy này.", systemImage: "waveform.badge.exclamationmark")
                    .font(.footnote)
                Label("Chế độ Gọn, Thư và Command Mode gửi CHỮ (không phải âm thanh) qua 9Router — xem mục Đám mây.", systemImage: "text.bubble")
                    .font(.footnote)
            }
        }
        .formStyle(.grouped)
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

/// Mục "Nâng cao": thư mục dữ liệu, phiên bản.
struct AdvancedSettingsTab: View {
    let controller: AppController

    var body: some View {
        Form {
            Section("Dữ liệu") {
                LabeledContent("Thư mục dữ liệu") {
                    Text(controller.dataHomePath).textSelection(.enabled)
                }
                Button("Mở thư mục dữ liệu") { controller.openDataFolder() }
            }
            Section("Phiên bản") {
                LabeledContent("Phiên bản vflow", value: AppVersion.current)
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section {
                Text("Âm thanh không bao giờ rời máy. Chế độ Gọn, Thư và Command Mode gửi CHỮ (không phải âm thanh) qua 9Router tới nhà cung cấp model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            body_
        }
        .formStyle(.grouped)
        .task(id: model.engineReady) {
            guard model.engineReady, !loaded else { return }
            await load()
        }
    }

    @ViewBuilder private var body_: some View {
        if model.engineBlocked {
            Section { Text(model.engineSummary).foregroundStyle(Color.red) }
        } else if !model.engineReady {
            Section { Text("Đang chờ engine khởi động…").foregroundStyle(.secondary) }
        } else if let e = loadError {
            Section {
                Text(ErrorText.message(e)).foregroundStyle(Color.red)
                Button("Thử lại") { Task { await load() } }
            }
        } else if !loaded {
            Section { Text("Đang tải…").foregroundStyle(.secondary) }
        } else {
            form
        }
    }

    @ViewBuilder private var form: some View {
        Section("9Router") {
            Toggle("Cho phép gửi chữ qua 9Router", isOn: $cloudLlm)
                .onChange(of: cloudLlm) { _, v in Task { await save(.init(cloudLlm: v)) } }
            VStack(alignment: .leading, spacing: 4) {
                Text("Model").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("vd. ag/gemini-3.8-flash", text: $llmModelText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await save(.init(llmModel: .some(llmModelText.isEmpty ? nil : llmModelText))) } }
                    Button("Lưu") { Task { await save(.init(llmModel: .some(llmModelText.isEmpty ? nil : llmModelText))) } }
                }
                if llmModelText.isEmpty {
                    Text("Chưa đặt model: Gọn/Thư/Command Mode sẽ không chạy được.")
                        .font(.footnote).foregroundStyle(Color.orange)
                } else {
                    Text("Đang dùng: \(llmModelText)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Thời gian chờ").font(.caption).foregroundStyle(.secondary)
                Stepper(value: $timeoutSeconds, in: 1...30) { Text("\(timeoutSeconds) giây") }
                    .onChange(of: timeoutSeconds) { _, v in Task { await save(.init(llmTimeoutMs: v * 1000)) } }
            }
        }
        Section("Hành động bằng giọng") {
            Toggle("Nhấn Enter bằng giọng", isOn: $actionsEnabled)
                .onChange(of: actionsEnabled) { _, v in Task { await save(.init(actionsEnabled: v)) } }
                .help("Nói \"nhấn enter\" ở cuối câu để tự động gửi phím Return sau khi dán.")
        }
        if let e = saveError {
            Section { Text(e).foregroundStyle(Color.red) }
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
