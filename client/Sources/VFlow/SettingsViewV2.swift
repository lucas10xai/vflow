import AppKit
import SwiftUI
import VFlowCore

/// Mục "Giọng nói" (V2): dấu câu bằng giọng, nói nhỏ, xem chữ chạy trực tiếp, tự dừng khi im lặng
/// (dời từ "Chung"), giọng điệu (Gọn/Thư). `GET/PUT /v1/settings` — hiệu lực ngay, giống `CloudSettingsSection`.
struct VoiceSettingsTab: View {
    let model: StatusModel
    let controller: AppController

    @State private var loaded = false
    @State private var loadError: ClientError?
    @State private var voicePunctuation = true
    @State private var whisperMode = false
    @State private var livePreview = true
    @State private var tone: Tone = .neutral
    @State private var cloudLlm = true
    @State private var contextSymbols = true
    @State private var saveError: String?

    var body: some View {
        Form {
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
        Section("Lệnh dấu câu bằng giọng") {
            Toggle("Ra lệnh dấu câu bằng giọng", isOn: $voicePunctuation)
                .onChange(of: voicePunctuation) { _, v in Task { await save(.init(voicePunctuation: v)) } }
            VStack(alignment: .leading, spacing: 4) {
                Text("Ví dụ: nói \u{201C}xuống dòng\u{201D} để xuống dòng, \u{201C}dấu phẩy\u{201D} để chèn dấu phẩy.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Chỉ các cụm ≥ 2 từ mới kích hoạt — lời nói thường như \u{201C}chấm điểm\u{201D}, \u{201C}câu hỏi\u{201D} không bị nhầm.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        Section("Nói nhỏ") {
            Toggle("Chế độ nói nhỏ", isOn: $whisperMode)
                .onChange(of: whisperMode) { _, v in Task { await save(.init(whisperMode: v)) } }
            Text("Tự khuếch đại âm lượng hoàn toàn trong máy trước khi nhận dạng — dùng khi cần nói rất nhỏ (họp, nơi công cộng).")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section("Xem chữ chạy trực tiếp") {
            Toggle("Hiện chữ đang nghe lúc nói", isOn: $livePreview)
                .onChange(of: livePreview) { _, v in Task { await save(.init(livePreview: v)) } }
            Text("Chữ mờ hiện tạm trên HUD trong lúc đang ghi âm — KHÔNG dán vào ô đang gõ; kết quả cuối vẫn là bản dịch đầy đủ sau khi nhả phím.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section("Ký hiệu theo ngữ cảnh") {
            Toggle("Hiểu ký hiệu theo ngữ cảnh", isOn: $contextSymbols)
                .onChange(of: contextSymbols) { _, v in Task { await save(.init(contextSymbols: v)) } }
            Text("Ví dụ: \u{201C}gạch chéo\u{201D} ⇒ \u{201C}/\u{201D}, \u{201C}a còng\u{201D} ⇒ \u{201C}@\u{201D} — CHỈ có hiệu lực trong app lập trình/terminal/AI (vd. VS Code, Terminal, Claude) và Slack/Discord/Teams. Ở các app khác (soạn email, ghi chú…), vẫn ra đúng chữ bình thường (\u{201C}gạch chéo\u{201D}, \u{201C}a còng\u{201D}).")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        SilenceStopSection(model: model, controller: controller)
        Section("Giọng điệu") {
            Picker("Giọng điệu", selection: $tone) {
                ForEach(Tone.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .disabled(!cloudLlm)
            .onChange(of: tone) { _, v in Task { await save(.init(tone: v)) } }
            if cloudLlm {
                Text("Chỉ áp dụng cho chế độ Gọn và Thư (viết lại qua 9Router) — không đổi chế độ Thường/Làm sạch/Lập trình.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Đám mây đang tắt (Cài đặt › Đám mây) — Gọn/Thư không gọi 9Router nên giọng điệu không có tác dụng.")
                    .font(.footnote).foregroundStyle(Color.orange)
            }
        }
        if let saveError {
            Section { Text(saveError).foregroundStyle(Color.red) }
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
        voicePunctuation = s.voicePunctuation
        whisperMode = s.whisperMode
        livePreview = s.livePreview
        tone = s.tone
        cloudLlm = s.cloudLlm
        contextSymbols = s.contextSymbols
    }

    private func save(_ patch: SettingsPatch) async {
        switch await controller.applySettingsPatch(patch) {
        case .success(let s): apply(s); saveError = nil
        case .failure(let e): saveError = ErrorText.message(e)
        }
    }
}

/// Mục "Ứng dụng" (V2): trình sửa `app_rules` — bundle id → chế độ, ghi đè `auto` cho từng ứng dụng.
struct AppsSettingsTab: View {
    let model: StatusModel
    let controller: AppController

    @State private var loaded = false
    @State private var loadError: ClientError?
    @State private var rules: [AppRule] = []
    @State private var cloudLlm = true
    @State private var saveError: String?
    @State private var addError: String?
    @State private var showRunningAppsMenu = false

    var body: some View {
        Form {
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
        Section("Luật theo ứng dụng") {
            Text("Ghi đè chế độ \u{201C}Tự động\u{201D} cho từng ứng dụng cụ thể — vd. luôn dùng Lập trình trong một IDE, hoặc Gọn trong một app ghi chú.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if rules.isEmpty {
                Text("Chưa có luật nào.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(rules) { rule in
                    AppRuleRow(rule: rule, cloudLlm: cloudLlm,
                              onChangeMode: { mode in Task { await updateMode(rule.bundleId, mode) } },
                              onDelete: { Task { await remove(rule.bundleId) } })
                }
            }
        }
        Section {
            HStack {
                Button("Chọn ứng dụng…") { pickAppFromOpenPanel() }
                Button("Từ ứng dụng đang chạy…") { showRunningAppsMenu = true }
                    .popover(isPresented: $showRunningAppsMenu) { runningAppsPicker }
            }
            if let addError { Text(addError).font(.footnote).foregroundStyle(Color.red) }
        }
        if let saveError {
            Section { Text(saveError).foregroundStyle(Color.red) }
        }
    }

    private var runningAppsPicker: some View {
        let apps = NSWorkspace.shared.runningApplications
            .compactMap { app -> (name: String, bundleId: String)? in
                guard let id = app.bundleIdentifier, let name = app.localizedName,
                      AppRuleValidation.isValidBundleId(id) else { return nil }
                return (name, id)
            }
            .sorted { $0.name < $1.name }
        return List(apps, id: \.bundleId) { app in
            Button(app.name) {
                showRunningAppsMenu = false
                Task { await add(bundleId: app.bundleId) }
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 240, minHeight: 200)
    }

    private func pickAppFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return }
        Task { await add(bundleId: bundleId) }
    }

    private func add(bundleId: String) async {
        if let error = AppRuleValidation.error(bundleId: bundleId, currentCount: rules.count) {
            addError = error
            return
        }
        addError = nil
        var next = rules
        next.removeAll { $0.bundleId == bundleId }
        next.append(AppRule(bundleId: bundleId, mode: .normal))
        await save(next)
    }

    private func updateMode(_ bundleId: String, _ mode: AppRuleMode) async {
        var next = rules
        guard let i = next.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        next[i].mode = mode
        await save(next)
    }

    private func remove(_ bundleId: String) async {
        await save(rules.filter { $0.bundleId != bundleId })
    }

    private func save(_ next: [AppRule]) async {
        switch await controller.applySettingsPatch(.init(appRules: next)) {
        case .success(let s): rules = s.appRules; cloudLlm = s.cloudLlm; saveError = nil
        case .failure(let e): saveError = ErrorText.message(e)
        }
    }

    private func load() async {
        switch await controller.fetchSettings() {
        case .success(let s): rules = s.appRules; cloudLlm = s.cloudLlm; loadError = nil
        case .failure(let e): loadError = e
        }
        loaded = true
    }
}

private struct AppRuleRow: View {
    let rule: AppRule
    let cloudLlm: Bool
    let onChangeMode: (AppRuleMode) -> Void
    let onDelete: () -> Void

    private var icon: NSImage? { StatsAppIdentity.icon(bundleId: rule.bundleId) }
    private var name: String { StatsAppIdentity.displayName(bundleId: rule.bundleId) }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Group {
                if let icon { Image(nsImage: icon).resizable() } else { Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary) }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout)
                Text(rule.bundleId).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(get: { rule.mode }, set: onChangeMode)) {
                ForEach(AppRuleMode.allCases, id: \.self) { m in Text(m.dictationMode.title).tag(m) }
            }
            .labelsHidden()
            .frame(width: 150)
            if rule.mode.sendsTextToCloud {
                Label(cloudLlm ? "gửi chữ qua 9Router" : "đám mây tắt — rơi về Làm sạch", systemImage: cloudLlm ? "cloud" : "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(cloudLlm ? Color.secondary : Color.orange)
            }
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.plain).accessibilityLabel("Xoá luật \(name)")
        }
    }
}

/// Mục "Dữ liệu" (V2): công tắc thống kê, học từ lần sửa, xoá thống kê, xuất/nhập, chẩn đoán.
struct DataSettingsTab: View {
    let model: StatusModel
    let controller: AppController

    @State private var loaded = false
    @State private var loadError: ClientError?
    @State private var statsEnabled = true
    @State private var learnFromEdits = true
    @State private var includeHistoryOnExport = false
    @State private var saveError: String?
    @State private var confirmClearStats = false
    @State private var clearStatsError: String?
    @State private var exportError: String?
    @State private var importError: String?
    @State private var importResultText: String?
    @State private var diagnosticsCopiedAt: Date?
    @State private var diagnosticsError: String?
    // Lưu âm thanh để nghe lại (V3)
    /// Cùng khoá/kho với `AppController.historyEnabled` (công tắc "Lưu lịch sử" ở tab Lịch sử & riêng tư).
    @AppStorage("historyEnabled", store: VFlowDefaults.resolve()) private var historyEnabled = true
    @State private var audioHistory = false
    @State private var audioMb = 200
    @State private var audioDays = 7
    /// Giá trị engine đang giữ (để không gửi lại giới hạn y hệt sau khi nhận phản hồi).
    @State private var serverAudioMb = 200
    @State private var serverAudioDays = 7
    @State private var audioSummary: AudioHistorySummary?
    @State private var audioSummaryError: String?
    @State private var confirmEnableAudio = false
    @State private var confirmDeleteAudio = false
    @State private var audioError: String?
    @State private var audioNotice: String?
    @State private var audioLimitTask: Task<Void, Never>?
    @State private var audioExporting = false

    var body: some View {
        Form {
            body_
        }
        .formStyle(.grouped)
        .task(id: model.engineReady) {
            guard model.engineReady, !loaded else { return }
            await load()
        }
        .alert("Xoá toàn bộ thống kê?", isPresented: $confirmClearStats) {
            Button("Xoá", role: .destructive) { Task { await clearStats() } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Không thể hoàn tác — không ảnh hưởng lịch sử, từ điển hay snippets.")
        }
        .onChange(of: historyEnabled) { _, now in
            // Lịch sử vừa TẮT ⇒ tắt luôn lưu âm thanh (không có mục lịch sử nào để gắn bản ghi). Bật lại
            // Lịch sử KHÔNG tự bật lưu âm thanh: `reconcilePatch` không bao giờ trả `true`.
            if let patch = AudioHistoryPolicy.reconcilePatch(historyEnabled: now, engineAudioHistory: audioHistory) {
                audioNotice = "Đã tự tắt lưu âm thanh vì Lịch sử đang tắt."
                Task { await save(patch) }
            }
        }
        .alert("Bật lưu âm thanh để nghe lại?", isPresented: $confirmEnableAudio) {
            Button("Bật lưu âm thanh") { Task { await save(.init(audioHistory: true, audioHistoryMb: audioMb, audioHistoryDays: audioDays)) } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("vflow sẽ lưu giọng nói của từng câu bạn đọc chính tả vào thư mục ~/.vflow/audio trên máy này. Âm thanh không gửi đi đâu. Chỉ lưu khi Lịch sử đang bật.\n\nGiới hạn: tối đa \(audioMb) MB (chỉnh được 50–2000 MB) và giữ \(audioDays) ngày (chỉnh được 1–90 ngày) — vượt thì bản cũ nhất bị xoá trước. Tệp quyền 0600: chỉ tài khoản của bạn đọc được. Bạn xoá được bất cứ lúc nào ở đây hoặc trong tab Lịch sử.")
        }
        .alert("Xoá toàn bộ âm thanh?", isPresented: $confirmDeleteAudio) {
            Button("Xoá", role: .destructive) { Task { await deleteAllAudio() } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Xoá mọi bản ghi giọng nói đã lưu trong ~/.vflow/audio. Câu chữ trong Lịch sử vẫn còn, chỉ mất nút nghe lại. Không thể hoàn tác.")
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
        Section("Thống kê") {
            Toggle("Thu thập thống kê (số từ, chuỗi ngày, ứng dụng)", isOn: $statsEnabled)
                .onChange(of: statsEnabled) { _, v in Task { await save(.init(statsEnabled: v)) } }
            Toggle("Học từ lần sửa (gợi ý từ điển)", isOn: $learnFromEdits)
                .onChange(of: learnFromEdits) { _, v in Task { await save(.init(learnFromEdits: v)) } }
            Button("Xoá thống kê…", role: .destructive) { confirmClearStats = true }
            if let clearStatsError { Text(clearStatsError).font(.footnote).foregroundStyle(Color.red) }
        }
        audioSection
        Section("Xuất/nhập dữ liệu") {
            Toggle("Gồm lịch sử khi xuất", isOn: $includeHistoryOnExport)
            Button("Xuất dữ liệu…") { exportData() }
            if let exportError { Text(exportError).font(.footnote).foregroundStyle(Color.red) }
            Button("Nhập dữ liệu…") { importDataMerge() }
            Button("Nhập và THAY THẾ toàn bộ…") { importDataReplace() }
                .foregroundStyle(Color.orange)
            if let importError { Text(importError).font(.footnote).foregroundStyle(Color.red) }
            if let importResultText { Text(importResultText).font(.footnote).foregroundStyle(.secondary) }
        }
        Section("Chẩn đoán") {
            Button("Sao chép chẩn đoán") { copyDiagnostics() }
            Button("Lưu chẩn đoán…") { saveDiagnostics() }
            if let diagnosticsCopiedAt {
                Text("Đã sao chép lúc \(diagnosticsCopiedAt.formatted(date: .omitted, time: .standard)).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let diagnosticsError { Text(diagnosticsError).font(.footnote).foregroundStyle(Color.red) }
        }
        if let saveError {
            Section { Text(saveError).foregroundStyle(Color.red) }
        }
    }

    private func load() async {
        switch await controller.fetchSettings() {
        case .success(let s):
            applySettings(s)
            loadError = nil
            // Lịch sử đang tắt mà engine còn nhớ audio_history=true (vd. tắt Lịch sử khi tab này không mở) ⇒ sửa ngay.
            if let patch = AudioHistoryPolicy.reconcilePatch(historyEnabled: controller.historyEnabled, engineAudioHistory: s.audioHistory) {
                audioNotice = "Đã tự tắt lưu âm thanh vì Lịch sử đang tắt."
                await save(patch)
            }
        case .failure(let e): loadError = e
        }
        loaded = true
        await refreshAudioSummary()
    }

    private func applySettings(_ s: AppSettings) {
        statsEnabled = s.statsEnabled
        learnFromEdits = s.learnFromEdits
        audioHistory = s.audioHistory
        audioMb = s.audioHistoryMb
        audioDays = s.audioHistoryDays
        serverAudioMb = s.audioHistoryMb
        serverAudioDays = s.audioHistoryDays
    }

    private func save(_ patch: SettingsPatch) async {
        switch await controller.applySettingsPatch(patch) {
        case .success(let s):
            applySettings(s)
            saveError = nil
            if patch.audioHistory != nil || patch.audioHistoryMb != nil || patch.audioHistoryDays != nil {
                await refreshAudioSummary()
            }
        case .failure(let e):
            saveError = ErrorText.message(e)
            // Gửi lỗi thì công tắc/giới hạn phải trở về giá trị engine thật, không giữ giá trị người dùng vừa chỉnh.
            audioMb = serverAudioMb
            audioDays = serverAudioDays
        }
    }

    // MARK: lưu âm thanh để nghe lại

    @ViewBuilder private var audioSection: some View {
        let canEnable = AudioHistoryPolicy.canEnable(historyEnabled: historyEnabled)
        let on = AudioHistoryPolicy.effectiveToggle(historyEnabled: historyEnabled, engineAudioHistory: audioHistory)
        Section("Lưu âm thanh để nghe lại") {
            Toggle("Lưu giọng nói của từng câu để nghe lại trong Lịch sử", isOn: Binding(
                get: { on },
                set: { v in
                    audioNotice = nil
                    if v { confirmEnableAudio = true } else { Task { await save(.init(audioHistory: false)) } }
                }))
                .disabled(!canEnable)
            if let reason = AudioHistoryPolicy.disabledReason(historyEnabled: historyEnabled) {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            }
            Text("Tắt mặc định. Khi bật, giọng nói lưu trong ~/.vflow/audio trên máy này (quyền 0600), không gửi đi đâu.")
                .font(.footnote).foregroundStyle(.secondary)
            if on {
                Stepper(value: $audioMb, in: AudioHistoryValidation.minMb...AudioHistoryValidation.maxMb, step: 50) {
                    Text("Giới hạn dung lượng: \(audioMb) MB")
                }
                .onChange(of: audioMb) { _, _ in scheduleAudioLimitSave() }
                Stepper(value: $audioDays, in: AudioHistoryValidation.minDays...AudioHistoryValidation.maxDays) {
                    Text("Giữ tối đa \(audioDays) ngày")
                }
                .onChange(of: audioDays) { _, _ in scheduleAudioLimitSave() }
            }
            if let s = audioSummary {
                Text(AudioHistoryFormat.usageText(s)).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel("Âm thanh đã lưu: \(AudioHistoryFormat.usageText(s))")
            } else if let audioSummaryError {
                Text(audioSummaryError).font(.footnote).foregroundStyle(Color.red)
            }
            Button("Xoá toàn bộ âm thanh…", role: .destructive) { confirmDeleteAudio = true }
                .disabled((audioSummary?.count ?? 0) == 0)
            Button(audioExporting ? "Đang xuất…" : "Xuất ZIP…") { exportAudioZip() }
                .disabled((audioSummary?.count ?? 0) == 0 || audioExporting)
            if let audioError { Text(audioError).font(.footnote).foregroundStyle(Color.red) }
            if let audioNotice { Text(audioNotice).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func refreshAudioSummary() async {
        switch await controller.fetchAudioHistory() {
        case .success(let s):
            audioSummary = s
            audioSummaryError = nil
        case .failure(let e):
            audioSummary = nil
            audioSummaryError = "Không đọc được thông tin âm thanh đã lưu: \(ErrorText.message(e))"
        }
    }

    /// Gom các lần bấm Stepper (mỗi lần bấm đổi 1 đơn vị) thành MỘT lần `PUT /v1/settings` sau 0,6 giây.
    private func scheduleAudioLimitSave() {
        guard audioMb != serverAudioMb || audioDays != serverAudioDays else { return }
        audioLimitTask?.cancel()
        audioLimitTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            if case .failure(let e) = AudioHistoryValidation.validateMb(audioMb) { saveError = e.message; return }
            if case .failure(let e) = AudioHistoryValidation.validateDays(audioDays) { saveError = e.message; return }
            await save(.init(audioHistoryMb: audioMb, audioHistoryDays: audioDays))
        }
    }

    private func deleteAllAudio() async {
        switch await controller.deleteAllAudioHistory() {
        case .success(let n):
            audioError = nil
            audioNotice = "Đã xoá \(n) tệp âm thanh."
        case .failure(let e):
            audioError = "Không xoá được âm thanh: \(ErrorText.message(e))"
        }
        await refreshAudioSummary()
    }

    private func exportAudioZip() {
        if let s = audioSummary, s.bytes > AudioHistoryFormat.maxExportBytes {
            audioError = "Âm thanh đang chiếm \(AudioHistoryFormat.sizeText(bytes: s.bytes)) — quá lớn để xuất một lần (tối đa \(AudioHistoryFormat.sizeText(bytes: AudioHistoryFormat.maxExportBytes))). Giảm giới hạn dung lượng hoặc xoá bớt rồi xuất lại."
            return
        }
        audioExporting = true
        Task {
            defer { audioExporting = false }
            switch await controller.fetchAudioExport() {
            case .failure(let e):
                audioError = "Không xuất được âm thanh: \(ErrorText.message(e))"
            case .success(let data):
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.zip]
                panel.nameFieldStringValue = "vflow-audio.zip"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try AudioExportWriter.write(data, to: url)
                    audioError = nil
                    audioNotice = "Đã lưu \(url.lastPathComponent) (quyền 0600)."
                } catch {
                    audioError = "Không lưu được tệp ZIP: \(error)"
                }
            }
        }
    }

    private func clearStats() async {
        switch await controller.deleteStats() {
        case .success: clearStatsError = nil
        case .failure(let e): clearStatsError = ErrorText.message(e)
        }
    }

    private func exportData() {
        Task {
            switch await controller.fetchExport(includeHistory: includeHistoryOnExport) {
            case .failure(let e): exportError = ErrorText.message(e)
            case .success(let data):
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "vflow-export.json"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    exportError = nil
                } catch {
                    exportError = "Không lưu được tệp: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importDataMerge() { pickAndImport(mode: .merge) }
    private func importDataReplace() { pickAndImport(mode: .replace) }

    private func pickAndImport(mode: ImportMode) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            importError = "Không đọc được tệp đã chọn"
            return
        }
        Task {
            switch await controller.sendImport(mode: mode, data: data) {
            case .success(let applied):
                importError = nil
                importResultText = "Đã nhập: từ điển \(applied.dictionary), snippets \(applied.snippets), cài đặt \(applied.settings), thống kê \(applied.statsDays) ngày, lịch sử \(applied.history)."
                    + (applied.ignored.isEmpty ? "" : " Bỏ qua: \(applied.ignored.joined(separator: ", ")).")
                await load()
            case .failure(let e):
                importResultText = nil
                importError = ErrorText.message(e)
            }
        }
    }

    private func copyDiagnostics() {
        Task {
            switch await controller.fetchDiagnostics() {
            case .success(let d):
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(d.prettyText, forType: .string)
                diagnosticsCopiedAt = Date()
                diagnosticsError = nil
            case .failure(let e):
                diagnosticsError = ErrorText.message(e)
            }
        }
    }

    private func saveDiagnostics() {
        Task {
            switch await controller.fetchDiagnostics() {
            case .success(let d):
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "vflow-diagnostics.json"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try d.prettyText.write(to: url, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    diagnosticsError = nil
                } catch {
                    diagnosticsError = "Không lưu được tệp: \(error.localizedDescription)"
                }
            case .failure(let e):
                diagnosticsError = ErrorText.message(e)
            }
        }
    }
}
