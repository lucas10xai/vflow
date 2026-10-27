import SwiftUI
import VFlowCore

/// Bốn mục của cửa sổ Cài đặt (`SettingsWindow.swift`) — xem mô tả từng mục ở từng `*SettingsTab`
/// bên dưới. Giữ TOÀN BỘ hành vi/kết nối engine cũ (U1: chỉ sắp xếp lại vào cửa sổ chuẩn macOS).
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, voice, apps, cloud, data, hotkeys, historyPrivacy, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Chung"
        case .voice: "Giọng nói"
        case .apps: "Ứng dụng"
        case .cloud: "Đám mây"
        case .data: "Dữ liệu"
        case .hotkeys: "Phím tắt"
        case .historyPrivacy: "Lịch sử & riêng tư"
        case .advanced: "Nâng cao"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .voice: "waveform"
        case .apps: "app.badge"
        case .cloud: "cloud"
        case .data: "tray.full"
        case .hotkeys: "command"
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
                .foregroundStyle(mode.sendsTextToCloud ? Theme.warningText : Color.secondary)
        }
    }
}

/// Mục "Chung": chế độ mặc định, bật khi đăng nhập, hiện cửa sổ khi mở app, biểu tượng thanh menu.
struct GeneralSettingsTab: View {
    let model: StatusModel
    let controller: AppController

    @AppStorage("showWindowOnLaunch") private var showWindowOnLaunch = ShowWindowPreference.defaultValue
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @ObservedObject private var appearance = AppearanceStore.shared
    @AppStorage(OverlayPreferences.positionKey) private var overlayPosition: OverlayPosition = OverlayPreferences.defaultPosition
    @AppStorage(OverlayPreferences.sizeKey) private var overlaySize: OverlaySize = OverlayPreferences.defaultSize

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
            Section("Giao diện") {
                Picker("Giao diện", selection: Binding(get: { appearance.preference }, set: { appearance.set($0) })) {
                    ForEach(AppearancePreference.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Áp dụng ngay cho mọi cửa sổ vflow. \"Hệ thống\" theo cài đặt Sáng/Tối của macOS.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Thanh ghi âm") {
                Picker("Vị trí", selection: $overlayPosition) {
                    ForEach(OverlayPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Cỡ", selection: $overlaySize) {
                    ForEach(OverlaySize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Gọn: chỉ trạng thái và sóng âm. Vừa: thêm 2 dòng chữ chạy trực tiếp. Lớn: 4 dòng, rộng hơn. \"Cạnh notch\" đặt ở giữa cạnh trên, dưới thanh menu. Có hiệu lực ở lần ghi kế tiếp.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Micro") {
                MicrophonePickerSection(controller: controller)
            }
            Section {
                Button("Thoát vflow") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .formStyle(.grouped)
    }
}

/// Mục "Phím tắt": phím giữ-để-nói, phím thứ hai cho Command Mode, tổ hợp "Chèn lại câu vừa rồi" —
/// áp dụng NGAY cho lần ghi kế tiếp (không ảnh hưởng lần ghi đang chạy, xem
/// `VFlowCore.ActiveHotkeyConfig`); lưu qua `AppController.hotkeyConfig`/`reinsertChord`
/// (UserDefaults, cô lập theo `VFLOW_HOME`).
struct HotkeysSettingsTab: View {
    let controller: AppController
    @State private var holdKey: HoldModifierKey = .leftOption
    @State private var commandKey: HoldModifierKey = .leftControl
    @State private var reinsertPreset: ReinsertChordPreset = .optionCommandV

    var body: some View {
        Form {
            Section("Giữ để nói") {
                Picker("Phím giữ để nói", selection: $holdKey) {
                    ForEach(HoldModifierKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: holdKey) { _, _ in save() }
                Text("Giữ phím này, nói, nhả để chèn — đúp phím này để ghi hands-free.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Command Mode (sửa/soạn văn bản bằng lời)") {
                Picker("Phím thứ hai (cùng phím giữ để nói)", selection: $commandKey) {
                    ForEach(HoldModifierKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: commandKey) { _, _ in save() }
                Text("Giữ phím giữ-để-nói rồi bấm thêm phím này trong 400 ms đầu.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let warning = HotkeyConfigValidation.conflictMessage(HotkeyKeyConfig(holdKey: holdKey, commandKey: commandKey)) {
                Section { Text(warning).foregroundStyle(Color.red).font(.footnote) }
            }
            Section("Chèn lại câu vừa rồi") {
                Picker("Tổ hợp phím", selection: $reinsertPreset) {
                    ForEach(ReinsertChordPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: reinsertPreset) { _, v in controller.reinsertChord = v.chord }
            }
            Section {
                Button("Đặt lại mặc định") {
                    controller.resetHotkeysToDefault()
                    load()
                }
            }
        }
        .formStyle(.grouped)
        .task { load() }
    }

    private func load() {
        let cfg = controller.hotkeyConfig
        holdKey = cfg.holdKey
        commandKey = cfg.commandKey
        reinsertPreset = ReinsertChordPreset.matching(controller.reinsertChord) ?? .optionCommandV
    }

    private func save() {
        controller.hotkeyConfig = HotkeyKeyConfig(holdKey: holdKey, commandKey: commandKey)
    }
}

/// Chọn micro (Cài đặt › Chung) — danh sách thiết bị đầu vào + "Mặc định hệ thống", lưu theo UID
/// (`AppController.micDeviceUID`); thiết bị biến mất ⇒ tự rơi về mặc định + báo một lần bằng HUD
/// (xem `AppController.resolvedMicDeviceUIDForRecording`, `VFlowCore.MicrophoneSelection`).
private struct MicrophonePickerSection: View {
    let controller: AppController
    @State private var selectedUID: String?
    @State private var devices: [MicrophoneSelection.Device] = []

    var body: some View {
        Picker("Micro", selection: $selectedUID) {
            Text("Mặc định hệ thống").tag(String?.none)
            ForEach(devices, id: \.uid) { d in Text(d.name).tag(Optional(d.uid)) }
        }
        .onChange(of: selectedUID) { _, v in controller.micDeviceUID = v }
        .task {
            devices = controller.availableMicDevices()
            selectedUID = controller.micDeviceUID
        }
    }
}

/// Tự dừng khi im lặng ở chế độ hands-free (Cài đặt › Chung) — `silence_stop_seconds` qua
/// `GET/PUT /v1/settings` hiện có (0 = tắt), xem `VFlowCore.VoiceActivityDetector`.
struct SilenceStopSection: View {
    let model: StatusModel
    let controller: AppController
    @State private var loaded = false
    @State private var seconds = 0
    @State private var saveError: String?

    var body: some View {
        Group {
            if !model.engineReady {
                Text("Đang chờ engine khởi động…").font(.footnote).foregroundStyle(.secondary)
            } else {
                Stepper(value: $seconds, in: 0...60) {
                    Text(seconds == 0 ? "Tự dừng khi im lặng: Tắt" : "Tự dừng khi im lặng: \(seconds) giây")
                }
                .onChange(of: seconds) { _, v in Task { await save(v) } }
                Text("Chỉ áp dụng cho ghi khoá (hands-free, đúp phím giữ-để-nói) — không áp dụng khi giữ phím thường.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let e = saveError { Text(e).font(.footnote).foregroundStyle(Color.red) }
            }
        }
        .task(id: model.engineReady) {
            guard model.engineReady, !loaded else { return }
            if case .success(let s) = await controller.fetchSettings() { seconds = s.silenceStopSeconds }
            loaded = true
        }
    }

    private func save(_ v: Int) async {
        switch await controller.applySettingsPatch(.init(silenceStopSeconds: v)) {
        case .success(let s): seconds = s.silenceStopSeconds; saveError = nil
        case .failure(let e): saveError = ErrorText.message(e)
        }
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
    @State private var latencyLog = RecordingLatencyStore.shared.snapshot

    var body: some View {
        Form {
            Section("Dữ liệu") {
                LabeledContent("Thư mục dữ liệu") {
                    Text(controller.dataHomePath).textSelection(.enabled)
                }
                Button("Mở thư mục dữ liệu") { controller.openDataFolder() }
            }
            Section("Độ trễ bắt đầu ghi") {
                LabeledContent("Từ nhấn phím tới khối âm thanh đầu") {
                    Text(RecordingLatencyText.summary(log: latencyLog)).textSelection(.enabled)
                }
                Text("Đo trong phiên này, chỉ giữ trong bộ nhớ (50 lượt gần nhất) — không ghi đĩa, không chứa nội dung giọng nói. Mở lại app là xoá.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Phiên bản") {
                LabeledContent("Phiên bản vflow", value: AppVersion.current)
            }
        }
        .formStyle(.grouped)
        .onAppear { latencyLog = RecordingLatencyStore.shared.snapshot }
        .onReceive(NotificationCenter.default.publisher(for: RecordingLatencyStore.didRecord).receive(on: DispatchQueue.main)) { _ in
            latencyLog = RecordingLatencyStore.shared.snapshot
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
                        .font(.footnote).foregroundStyle(Theme.warningText)
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
