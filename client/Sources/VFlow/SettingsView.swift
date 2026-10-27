import SwiftUI
import VFlowCore

/// Năm mục của cửa sổ Cài đặt (`SettingsWindow.swift`) — logic chọn mục/tên cũ nằm ở
/// `VFlowCore.SettingsPane` (có test); ở đây chỉ thêm biểu tượng. Giữ TOÀN BỘ chức năng cũ, chỉ gộp 8
/// mục thành 5 để nhãn tab không bị cắt chữ.
typealias SettingsCategory = SettingsPane

extension SettingsPane: Identifiable {
    public var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .voice: "waveform"
        case .apps: "app.badge"
        case .data: "lock.shield"
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


/// Mục "Nâng cao": đám mây 9Router (công tắc, model, thời gian chờ), độ trễ bắt đầu ghi, thông tin kỹ
/// thuật (thư mục dữ liệu, phiên bản). `GET/PUT /v1/settings` — hiệu lực ngay, lỗi `bad_request` của
/// engine hiện tiếng Việt. (Gộp từ "Đám mây" + "Nâng cao" cũ để cửa sổ chỉ còn 5 mục, không cắt chữ.)
struct AdvancedSettingsTab: View {
    let model: StatusModel
    let controller: AppController

    @State private var latencyLog = RecordingLatencyStore.shared.snapshot
    @State private var loaded = false
    @State private var loadError: ClientError?
    @State private var cloudLlm = true
    @State private var llmModelText = ""
    @State private var timeoutSeconds = 8
    @State private var saveError: String?

    var body: some View {
        Form {
            cloudBody
            Section("Độ trễ bắt đầu ghi") {
                LabeledContent("Từ nhấn phím tới khối âm thanh đầu") {
                    Text(RecordingLatencyText.summary(log: latencyLog)).textSelection(.enabled)
                }
                Text("Đo trong phiên này, chỉ giữ trong bộ nhớ (50 lượt gần nhất) — không ghi đĩa, không chứa nội dung giọng nói. Mở lại app là xoá.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Thông tin kỹ thuật") {
                LabeledContent("Thư mục dữ liệu") {
                    Text(controller.dataHomePath).textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Mở thư mục dữ liệu") { controller.openDataFolder() }
                LabeledContent("Phiên bản vflow", value: AppVersion.current)
            }
        }
        .formStyle(.grouped)
        .task(id: model.engineReady) {
            guard model.engineReady, !loaded else { return }
            await load()
        }
        .onAppear { latencyLog = RecordingLatencyStore.shared.snapshot }
        .onReceive(NotificationCenter.default.publisher(for: RecordingLatencyStore.didRecord).receive(on: DispatchQueue.main)) { _ in
            latencyLog = RecordingLatencyStore.shared.snapshot
        }
    }

    @ViewBuilder private var cloudBody: some View {
        if model.engineBlocked {
            Section("Đám mây (9Router)") { Text(model.engineSummary).foregroundStyle(Color.red) }
        } else if !model.engineReady {
            Section("Đám mây (9Router)") { Text("Đang chờ engine khởi động…").foregroundStyle(.secondary) }
        } else if let e = loadError {
            Section("Đám mây (9Router)") {
                Text(ErrorText.message(e)).foregroundStyle(Color.red)
                Button("Thử lại") { Task { await load() } }
            }
        } else if !loaded {
            Section("Đám mây (9Router)") { Text("Đang tải…").foregroundStyle(.secondary) }
        } else {
            cloudForm
        }
    }

    @ViewBuilder private var cloudForm: some View {
        Section("Đám mây (9Router)") {
            Text("Âm thanh không rời máy. Chế độ Gọn, Thư và Command Mode gửi CHỮ (không phải âm thanh) qua 9Router tới nhà cung cấp model.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                        .fixedSize(horizontal: false, vertical: true)
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
    }

    private func save(_ patch: SettingsPatch) async {
        switch await controller.applySettingsPatch(patch) {
        case .success(let s): apply(s); saveError = nil
        case .failure(let e): saveError = ErrorText.message(e)
        }
    }
}

enum AppVersion {
    static let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
}

