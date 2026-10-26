import AppKit
import ServiceManagement
import VFlowCore

/// Nối các phần: phím nóng ⇒ micro ⇒ engine ⇒ dán ⇒ thanh trạng thái.
@MainActor
final class AppController: NSObject {
    private let overlay = OverlayController()
    private let hotkeys = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let pasteboard = SystemPasteboard()
    private var machine = HotkeyStateMachine()
    private var retry = RetryBuffer()
    private var supervisor: EngineSupervisor?
    /// Spec engine đã resolve (nếu thành công) — nguồn duy nhất cho cổng thật, tách khỏi
    /// `supervisor` để `resolvedPort()` không bao giờ suy đoán cổng mặc định (xem `EnginePortResolution`).
    private var engineSpec: EngineLaunchSpec?
    private var menu: StatusMenu!
    private var statusWindow: StatusWindowController!
    private var settingsWindow: SettingsWindowController!
    private var welcomeWindow: WelcomeWindowController!
    private var tickTimer: Timer?
    private var healthTimer: Timer?
    private var hotkeyRetryTimer: Timer?
    private var inflight: Task<Void, Never>?
    private var targetApp: String?
    private var recordingStartedAt: TimeInterval = 0
    /// Lấy đoạn đang chọn (AX/⌘C) chạy song song với ghi âm lệnh Command Mode (xem `SelectionCapture`).
    private var commandSelectionTask: Task<String?, Never>?
    /// Đã hiện cảnh báo "còn ~20s" cho lần ghi hiện tại chưa (tránh lặp lại mỗi tick).
    private var warnedApproachingLimit = false
    /// Văn bản cuối cùng đã chèn (dictation hoặc Command Mode) — CHỈ TRONG PHIÊN CHẠY (không ghi
    /// đĩa), dùng cho "Chèn lại câu vừa rồi" khi Lưu lịch sử đang TẮT (xem `VFlowCore.LastSpokenText`).
    private var lastSpokenTextMemory: String?
    /// UID micro đã báo "không còn" một lần trong phiên này (tránh báo lặp lại mỗi lần ghi).
    private var warnedMissingMicUIDs: Set<String> = []
    /// VAD đang chạy CHỈ khi ghi khoá (hands-free) và `silence_stop_seconds` > 0 (xem contract mục 7b).
    private var vad: VoiceActivityDetector?
    private var lastVadTickAt: TimeInterval?
    /// Giây đã báo đếm ngược gần nhất (tránh hiện lại cùng một số).
    private var lastAnnouncedVadCountdown: Int?
    /// Cache của `GET/PUT /v1/settings` — dùng để quyết định gửi Enter (xem `EnterAction`); mặc
    /// định khớp `DEFAULT_SETTINGS` của engine cho tới khi đọc được bản thật.
    private(set) var cachedSettings = AppSettings(cloudLlm: true, llmModel: nil, llmTimeoutMs: 8000, actionsEnabled: true)
    private let session: URLSession
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    /// `<VFLOW_HOME>` thật (mặc định `~/.vflow`) — token, lịch sử… Tôn trọng biến môi trường để
    /// thử nghiệm không đụng dữ liệu thật (xem `VFlowHome`).
    private let vflowHome = VFlowHome.resolve()
    /// UserDefaults DUY NHẤT của app — `.standard` nếu không có `VFLOW_HOME` (hành vi cũ, app
    /// thật), suite riêng cô lập nếu có (xem `VFlowCore.VFlowDefaults`). TẤT CẢ truy cập
    /// UserDefaults trong lớp AppKit đi qua đây, không gọi `UserDefaults.standard` trực tiếp nơi
    /// khác.
    private let defaults = VFlowDefaults.resolve()
    private lazy var historyStore = HistoryStore(path: vflowHome + "/history.jsonl")
    private let conflictDetector = ConflictDetector()
    private let runningApps: RunningAppsProvider = WorkspaceRunningApps()

    /// Đường dẫn dữ liệu hiện dùng (hiện ở tab Cài đặt).
    var dataHomePath: String { vflowHome }

    var historyEnabled: Bool {
        get { (defaults.object(forKey: "historyEnabled") as? Bool) ?? true }
        set { defaults.set(newValue, forKey: "historyEnabled") }
    }

    /// Công tắc "Hiện biểu tượng trên thanh menu" (mặc định bật).
    var showMenuBarIcon: Bool {
        get { (defaults.object(forKey: "showMenuBarIcon") as? Bool) ?? true }
        set { defaults.set(newValue, forKey: "showMenuBarIcon"); menu?.setVisible(newValue) }
    }

    private(set) var engineState: EngineState = .stopped
    private(set) var configError: ClientError?
    private(set) var lastError: String?
    /// Trạng thái chép model lần đầu từ bundle (M4b/Phần 2); `nil` = không có gì đáng nói (xem `ModelBootstrap`).
    private(set) var modelBootstrapStatus: String?

    var mode: DictationMode {
        get { DictationMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }

    /// Công tắc "Hiện cửa sổ này khi mở app" (mặc định bật).
    var showWindowOnLaunch: Bool {
        get { ShowWindowPreference.resolve(stored: defaults.object(forKey: "showWindowOnLaunch") as? Bool) }
        set { defaults.set(newValue, forKey: "showWindowOnLaunch") }
    }

    /// Phím "giữ để nói" + phím Command Mode (Cài đặt › Phím tắt) — mặc định giữ ĐÚNG hành vi cũ
    /// (⌥ trái / ⌃ trái). Đổi áp dụng ngay (xem `HotkeyMonitor.keyConfig`/`ActiveHotkeyConfig`).
    var hotkeyConfig: HotkeyKeyConfig {
        get {
            HotkeyKeyConfig(holdKey: HoldModifierKey(rawValue: defaults.string(forKey: "hotkeyHoldKey") ?? "") ?? .leftOption,
                            commandKey: HoldModifierKey(rawValue: defaults.string(forKey: "hotkeyCommandKey") ?? "") ?? .leftControl)
        }
        set {
            defaults.set(newValue.holdKey.rawValue, forKey: "hotkeyHoldKey")
            defaults.set(newValue.commandKey.rawValue, forKey: "hotkeyCommandKey")
            hotkeys.keyConfig = newValue
        }
    }

    /// Tổ hợp "Chèn lại câu vừa rồi" (mặc định ⌥⌘V) — Cài đặt › Phím tắt.
    var reinsertChord: HotkeyChord {
        get {
            guard let data = defaults.data(forKey: "hotkeyReinsertChord"),
                  let chord = try? JSONDecoder().decode(HotkeyChord.self, from: data) else { return .reinsertDefault }
            return chord
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: "hotkeyReinsertChord") }
            hotkeys.reinsertChord = newValue
        }
    }

    /// Đặt lại phím tắt về mặc định (nút "Đặt lại mặc định" ở Cài đặt › Phím tắt).
    func resetHotkeysToDefault() {
        hotkeyConfig = .defaultConfig
        reinsertChord = .reinsertDefault
    }

    // MARK: micro (Cài đặt › Chung, xem contract mục 7a)

    /// UID micro đã chọn — `nil` = "Mặc định hệ thống".
    var micDeviceUID: String? {
        get { defaults.string(forKey: "micDeviceUID") }
        set { defaults.set(newValue, forKey: "micDeviceUID") }
    }

    func availableMicDevices() -> [MicrophoneSelection.Device] { AudioRecorder.availableDevices() }

    /// UID thật sự dùng khi bắt đầu ghi — thiết bị đã chọn biến mất ⇒ rơi về mặc định VÀ báo một
    /// lần bằng HUD (không lặp lại mỗi lần ghi); gọi ngay trước `recorder.start()`.
    private func resolvedMicDeviceUIDForRecording() -> String? {
        switch MicrophoneSelection.resolve(configuredUID: micDeviceUID, availableDevices: availableMicDevices()) {
        case .systemDefault: return nil
        case .configured(let d): return d.uid
        case .fallbackDeviceMissing(let previousUID):
            if !warnedMissingMicUIDs.contains(previousUID) {
                warnedMissingMicUIDs.insert(previousUID)
                overlay.show(.notice("Micro đã chọn không còn — dùng micro mặc định"), thenRestore: currentListeningOverlay())
            }
            micDeviceUID = nil
            return nil
        }
    }

    /// Mô hình thuần dùng chung cho menu và cửa sổ trạng thái — một nguồn duy nhất.
    var statusModel: StatusModel {
        StatusModel.build(engineState: engineState, configError: configError, lastError: lastError,
                           permissions: PermissionKind.items, mode: mode, canRetryLast: canRetry,
                           launchAtLogin: launchAtLogin, conflictWarning: conflictWarning(), hotkeysActive: hotkeysActive,
                           modelBootstrapStatus: modelBootstrapStatus, menuBarIconReminder: menuBarIconReminderMessage())
    }

    private func conflictWarning() -> String? {
        ConflictText.warning(for: conflictDetector.detect(runningBundleIDs: runningApps.runningBundleIDs()))
    }

    /// Biểu tượng thanh menu có đang bị che (notch, hoặc hệ thống co về 0 vì thanh menu đầy) không —
    /// xem `VFlowCore.MenuBarOcclusion`; `false` khi công tắc "Hiện biểu tượng" đang TẮT (không có
    /// gì để che) hoặc chưa đọc được khung cửa sổ/màn hình.
    var isMenuBarIconOccluded: Bool {
        // CHỈ để chụp ảnh thẻ nhắc (U4) — không có tác dụng gì khi không đặt, không bao giờ dùng
        // khi chạy thật (giống `VFLOW_DEMO_PERMISSIONS`); toạ độ màn hình thật lúc kiểm tự động
        // không đoán trước được có notch/đủ chật để tự nhiên bị che hay không.
        if ProcessInfo.processInfo.environment["VFLOW_DEMO_MENUBAR_OCCLUDED"] == "1" { return true }
        guard showMenuBarIcon, let screen = NSScreen.main, let itemFrame = menu?.itemWindowFrame else { return false }
        func rect(_ r: NSRect) -> MenuBarOcclusion.Rect { .init(minX: r.minX, maxX: r.maxX) }
        return MenuBarOcclusion.isOccluded(itemFrame: rect(itemFrame), screenFrame: rect(screen.frame),
                                           auxiliaryLeft: screen.auxiliaryTopLeftArea.map(rect),
                                           auxiliaryRight: screen.auxiliaryTopRightArea.map(rect))
    }

    /// Ngày đóng gần nhất của thẻ nhắc "biểu tượng bị che" ở Tổng quan (xem `MenuBarOcclusionReminder`).
    var menuBarOcclusionReminderDismissedDay: String? {
        get { defaults.string(forKey: "menuBarOcclusionReminderDismissedDay") }
        set { defaults.set(newValue, forKey: "menuBarOcclusionReminderDismissedDay") }
    }

    private func menuBarIconReminderMessage() -> String? {
        let today = MenuBarOcclusionReminder.dayKey(for: Date())
        guard MenuBarOcclusionReminder.shouldShow(isOccluded: isMenuBarIconOccluded, todayKey: today,
                                                  dismissedOnDayKey: menuBarOcclusionReminderDismissedDay) else { return nil }
        return MenuBarOcclusionReminder.message
    }

    /// Đóng thẻ nhắc "biểu tượng bị che" — nhớ theo NGÀY (hiện lại hôm sau nếu vẫn bị che).
    func dismissMenuBarOcclusionReminder() {
        menuBarOcclusionReminderDismissedDay = MenuBarOcclusionReminder.dayKey(for: Date())
        refreshUI()
    }

    override init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:] // chỉ 127.0.0.1, không qua proxy hệ thống
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        session = URLSession(configuration: cfg)
        super.init()
    }

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// `initialTab`: mục thanh bên dựng NGAY TỪ ĐẦU (mặc định Tổng quan) — CHỈ `--render-offscreen`
    /// (U3) cần đổi, để dựng thẳng đúng mục cần chụp thay vì Tổng quan rồi mới chuyển. Đã THỬ coi
    /// đây là nguyên nhân khiến hàng trong `List` (Lịch sử/Từ điển/Snippets) không hiện khi chụp
    /// ngoài màn hình — ĐO LẠI vẫn không hiện ngay cả khi dựng thẳng mục đó (xem ghi chú ở
    /// `StatusWindowController.captureOffscreen`, giới hạn đã biết, không phải nguyên nhân). Giữ
    /// tham số này vì vẫn hợp lý về mặt thiết kế (không cần chuyển mục thừa khi đã biết trước).
    func start(initialTab: MainTab = .overview) {
        menu = StatusMenu(controller: self)
        menu.setVisible(showMenuBarIcon)
        statusWindow = StatusWindowController(controller: self, initialTab: initialTab)
        settingsWindow = SettingsWindowController(controller: self)
        welcomeWindow = WelcomeWindowController(controller: self)
        recorder.onLevel = { [weak self] l in self?.overlay.setLevel(l); self?.processVoiceActivity(level: l) }
        recorder.onInterrupted = { [weak self] why in self?.micInterrupted(why) }
        hotkeys.onInput = { [weak self] input in self?.handle(input) }
        hotkeys.onTapDisabled = { [weak self] in self?.tapDisabled() }
        hotkeys.onReinsertChord = { [weak self] in self?.reinsertLastSentence() }
        hotkeys.isIdle = { [weak self] in self?.machine.phase == .idle }
        hotkeys.keyConfig = hotkeyConfig
        hotkeys.reinsertChord = reinsertChord

        if AudioRecorder.permission() == .notDetermined { PermissionKind.microphone.request() }
        startHotkeys()
        runModelBootstrapIfNeeded()

        switch ClientConfig.resolve(home: home, vflowHome: vflowHome, bundlePath: Bundle.main.bundlePath, fs: .live) {
        case .failure(let e):
            configError = e
            setError(ErrorText.message(e), showOverlay: true)
        case .success(let spec):
            engineSpec = spec
            let port = spec.port
            let sup = EngineSupervisor(spec: spec, launcher: FoundationProcessLauncher(),
                                       probe: { [session] in await Self.probe(session: session, port: port) },
                                       sleep: { try? await Task.sleep(for: $0) },
                                       now: { Self.now })
            sup.onStateChange = { [weak self] s in self?.engineStateChanged(s) }
            supervisor = sup
            Task { await sup.start() }
            healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if let s = self?.supervisor { Task { await s.refresh() } } }
            }
            Task { _ = await self.fetchSettings() } // best-effort; cachedSettings giữ mặc định nếu lỗi
        }
        // Màn hình/menu thay đổi (cắm/rút màn hình ngoài, đổi độ phân giải…) ⇒ dò lại ngay xem
        // biểu tượng thanh menu có bị che không (xem mục 4b trong yêu cầu).
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUI() }
        }
        refreshUI()
        if showWindowOnLaunch { openStatusWindow() }
        if WelcomeDecision.shouldAutoShow(hasSeenWelcome: hasSeenWelcome, permissions: PermissionKind.items),
           !CommandLine.arguments.contains("--no-welcome") {
            openWelcome()
        }
    }

    /// Cờ "đã từng xem Chào mừng" (UserDefaults, tách biệt khỏi "đã cấp đủ quyền" — xem
    /// `VFlowCore.WelcomeDecision`).
    var hasSeenWelcome: Bool {
        get { (defaults.object(forKey: "hasSeenWelcome") as? Bool) ?? false }
        set { defaults.set(newValue, forKey: "hasSeenWelcome") }
    }

    /// UserDefaults dùng cho cả lớp SwiftUI (`@AppStorage`) — xem `defaultAppStorage(_:)` ở
    /// `MainWindowView`/`SettingsRootView`/`WelcomeView`, cùng nguồn với `defaults` ở trên.
    var appStorageDefaults: UserDefaults { defaults }

    func openWelcome() {
        refreshUI()
        welcomeWindow.show()
    }

    /// Đóng tờ Chào mừng (nút "Bắt đầu dùng vflow") — đánh dấu đã xem, giống hành vi đóng cửa sổ
    /// (nút đỏ) qua `windowWillClose`.
    func closeWelcome() {
        welcomeWindow.window?.close()
    }

    func markWelcomeSeen() {
        hasSeenWelcome = true
    }

    /// "Mở README hoặc hướng dẫn quyền" — dùng chung cho menu Trợ giúp và nút trong tờ Chào mừng.
    func openHelpDocument() {
        if let repo = repoPathForHelp(), FileManager.default.fileExists(atPath: repo + "/client/README.md") {
            NSWorkspace.shared.open(URL(fileURLWithPath: repo + "/client/README.md"))
        } else {
            openStatusWindow(tab: .overview)
        }
    }

    /// Thoát: đóng engine con trước.
    func shutdown() async {
        hotkeys.stop()
        recorder.cancel()
        inflight?.cancel()
        await supervisor?.stop()
    }

    /// Cách điều khiển chính không phụ thuộc biểu tượng thanh menu: bấm biểu tượng Dock/`open
    /// VFlow.app` khi đang chạy, menu ứng dụng/menu thanh trạng thái, hoặc (nếu bật) tự mở khi
    /// khởi động. `tab`: dùng cho `--open-tab` (chụp ảnh từng tab) và "Cài đặt…" (⌘,).
    func openStatusWindow(tab: MainTab? = nil) {
        refreshUI()
        statusWindow.show(tab: tab)
        if !OffscreenRender.enabled { NSApp.activate() }
    }

    /// `--render-offscreen`: chụp nội dung cửa sổ chính mà KHÔNG BAO GIỜ hiện lên màn hình.
    func captureStatusWindowOffscreen(tab: MainTab, to path: String) async {
        refreshUI()
        await statusWindow.captureOffscreen(tab: tab, to: path)
    }

    /// `--render-offscreen tudien:them-loi`: sheet Thêm mục từ điển với lỗi hợp lệ, không hiện.
    func captureDictionaryAddInvalidOffscreen(to path: String) {
        refreshUI()
        statusWindow.captureDictionaryAddInvalidOffscreen(to: path)
    }

    /// `--render-offscreen`: chụp nội dung cửa sổ Cài đặt mà KHÔNG BAO GIỜ hiện lên màn hình.
    func captureSettingsWindowOffscreen(tab: SettingsCategory, to path: String) {
        refreshUI()
        settingsWindow.captureOffscreen(tab: tab, to: path)
    }

    /// `--render-offscreen`: chụp nội dung tờ Chào mừng mà KHÔNG BAO GIỜ hiện lên màn hình.
    func captureWelcomeOffscreen(to path: String) {
        refreshUI()
        welcomeWindow.captureOffscreen(to: path)
    }

    /// Cửa sổ Cài đặt CHUẨN macOS, tách khỏi cửa sổ chính (⌘,; menu "vflow › Cài đặt…"); `tab`
    /// dùng cho `--open-tab caidat` (chụp ảnh) và chọn đúng mục khi mở từ nơi khác.
    func openSettingsWindow(tab: SettingsCategory? = nil) {
        refreshUI()
        settingsWindow.show(tab: tab)
    }

    func openDataFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: vflowHome))
    }

    /// Trợ giúp (menu ứng dụng): repo của engine đang dùng, nếu đã biết (để tìm README cạnh đó).
    func repoPathForHelp() -> String? { supervisor?.spec.repo }

    /// CHỈ dùng cho test hồi quy bố cục & công cụ `--snapshot` (U3) — truy cập cửa sổ chính THẬT
    /// (cùng `StatusWindowController` sản phẩm dùng) mà không qua `show()`/`openStatusWindow()`.
    var statusWindowForTesting: StatusWindowController { statusWindow }

    private func refreshUI() {
        let model = statusModel
        menu.refresh(model)
        statusWindow.update(model)
        settingsWindow.update(model)
        welcomeWindow.update(model)
    }

    /// Cửa sổ trạng thái gọi mỗi 2 giây khi đang hiện: quyền có thể vừa được cấp trong System Settings.
    func refreshPermissionsNow() { refreshUI() }

    // MARK: model lần đầu (M4b/Phần 2 — bản dựng tự đủ kèm model trong bundle)

    /// Bản dựng `--no-bundle` hoặc chạy từ repo: không có `Contents/Resources/models` ⇒ bỏ qua êm,
    /// giữ hành vi cũ (`vflow models pull`). Có bundle model ⇒ chép sang `VFLOW_HOME` nếu CHƯA có,
    /// KHÔNG BAO GIỜ đè model đã có; hiện trạng thái trung thực ở tab Tổng quan trong lúc chép.
    private func runModelBootstrapIfNeeded() {
        let modelsDir = Bundle.main.bundlePath + "/Contents/Resources/models"
        guard FileManager.default.fileExists(atPath: modelsDir) else { return }
        modelBootstrapStatus = "Đang chuẩn bị model lần đầu…"
        refreshUI()
        let home = vflowHome
        Task.detached(priority: .utility) { [weak self] in
            let outcome = ModelBootstrap.installIfNeeded(vflowHome: home, modelID: "zipformer-vi-30m",
                                                          bundleModelsDir: modelsDir, fs: .live)
            await MainActor.run {
                guard let self else { return }
                switch outcome {
                case .alreadyPresent, .noBundledSource:
                    self.modelBootstrapStatus = nil
                case .copied:
                    self.modelBootstrapStatus = nil
                case .failed(let e):
                    self.modelBootstrapStatus = "Chép model lần đầu lỗi: \(e)"
                }
                self.refreshUI()
            }
        }
    }

    // MARK: engine

    nonisolated static func probe(session: URLSession, port: Int) async -> HealthProbe {
        do {
            let (data, resp) = try await session.data(for: EngineAPI.healthRequest(port: port))
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let h = EngineAPI.parseHealth(status: status, data: data) { return .engine(h) }
            return .foreign
        } catch {
            return .unreachable
        }
    }

    private func engineStateChanged(_ s: EngineState) {
        engineState = s
        if case .failed(let e) = s { setError(ErrorText.message(e), showOverlay: true) }
        refreshUI()
    }

    func restartEngine() {
        guard let s = supervisor else { return }
        Task { await s.stop(); await s.start() }
    }

    var health: Health? {
        if case .running(_, let h) = engineState { return h }
        return nil
    }

    var engineOwned: Bool { supervisor?.ownsChild ?? false }

    // MARK: phím nóng

    private func startHotkeys() {
        // Chỉ tạo event tap khi đã có quyền (tapCreate khi chưa có quyền tự bật hộp thoại hệ thống).
        if PermissionKind.inputMonitoring.granted, hotkeys.start() {
            hotkeyRetryTimer?.invalidate()
            hotkeyRetryTimer = nil
            refreshUI()
            return
        }
        // Thiếu quyền: hỏi một lần (thêm app vào danh sách), thử lại định kỳ.
        PermissionKind.inputMonitoring.request()
        setError(ErrorText.message(.inputMonitoringDenied), showOverlay: true)
        if hotkeyRetryTimer == nil {
            hotkeyRetryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, PermissionKind.inputMonitoring.granted, self.hotkeys.start() else { return }
                    self.hotkeyRetryTimer?.invalidate()
                    self.hotkeyRetryTimer = nil
                    self.lastError = nil
                    self.refreshUI()
                }
            }
        }
    }

    var hotkeysActive: Bool { hotkeys.isRunning }

    private func handle(_ input: KeyInput) {
        perform(machine.handle(input, at: Self.now))
        updateTicking()
    }

    private func tapDisabled() {
        perform(machine.reset(optionHeld: hotkeys.leftOptionHeldNow()))
        updateTicking()
    }

    private func updateTicking() {
        if machine.needsTicks, tickTimer == nil {
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.perform(self.machine.tick(at: Self.now, optionHeld: self.hotkeys.leftOptionHeldNow()))
                    self.checkApproachingLimit()
                    self.updateTicking()
                }
            }
        } else if !machine.needsTicks, let t = tickTimer {
            t.invalidate()
            tickTimer = nil
        }
    }

    /// Cảnh báo một lần trước khi tự gửi vì hết giờ — giữ phím thường ở ~20s còn lại (giây 100/120,
    /// không đổi hành vi cũ); ghi khoá (hands-free, có thể dài hơn 120s — xem contract mục 7c) ở
    /// ~30s còn lại (`RecordingLimit.warnAtRemainingSeconds`).
    private func checkApproachingLimit() {
        let warnAt: TimeInterval = machine.isLocked ? TimeInterval(RecordingLimit.warnAtRemainingSeconds) : 20
        guard let remaining = machine.secondsRemaining(at: Self.now), remaining <= warnAt, !warnedApproachingLimit else { return }
        warnedApproachingLimit = true
        overlay.show(.notice("Còn khoảng \(Int(warnAt)) giây sẽ tự gửi"), thenRestore: currentListeningOverlay())
    }

    private func currentListeningOverlay() -> OverlayState {
        switch machine.phase {
        case .recordingLocked: return .listeningLocked(level: 0)
        case .recordingCommand: return .listeningCommand(level: 0)
        default: return .listening(level: 0)
        }
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .none: break
        case .startRecording: beginRecording()
        case .stopAndSend: finishRecording()
        case .startCommandRecording: beginCommandRecording()
        case .stopAndSendCommand: finishCommandRecording()
        case .cancel:
            commandSelectionTask?.cancel()
            commandSelectionTask = nil
            recorder.cancel()
            overlay.show(.notice(OverlayText.cancelled))
            refreshUI()
        case .busyTimedOut:
            inflight?.cancel()
            inflight = nil
            setError("Engine không phản hồi, đã bỏ yêu cầu", showOverlay: true)
        }
    }

    private func abortRecording(_ error: ClientError) {
        _ = machine.reset(optionHeld: hotkeys.leftOptionHeldNow())
        commandSelectionTask?.cancel()
        commandSelectionTask = nil
        recorder.cancel()
        setError(ErrorText.message(error), showOverlay: true)
        updateTicking()
    }

    private func beginRecording() {
        switch AudioRecorder.permission() {
        case .authorized: break
        case .notDetermined:
            PermissionKind.microphone.request()
            return abortRecording(.micDenied)
        default:
            return abortRecording(.micDenied)
        }
        guard engineState.isReady else {
            if let e = configError { return abortRecording(e) }
            if case .failed(let e) = engineState { return abortRecording(e) }
            return abortRecording(.engineNotRunning)
        }
        targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        do {
            try recorder.start(deviceUID: resolvedMicDeviceUIDForRecording())
        } catch let e as ClientError {
            return abortRecording(e)
        } catch {
            return abortRecording(.micUnavailable(error.localizedDescription))
        }
        recordingStartedAt = Self.now
        warnedApproachingLimit = false
        // Ghi khoá (hands-free) được phép dài hơn 120s nếu engine báo giới hạn lớn hơn, và CHỈ ghi
        // khoá mới chạy VAD tự dừng khi im lặng (xem contract mục 7b/7c) — giữ phím thường KHÔNG đổi.
        if machine.isLocked {
            machine.maxRecording = Double(RecordingLimit.resolve(engineMaxAudioSeconds: currentMaxAudioSeconds))
            vad = cachedSettings.silenceStopSeconds > 0 ? VoiceActivityDetector() : nil
        } else {
            machine.maxRecording = HotkeyStateMachine.defaultMaxRecording
            vad = nil
        }
        lastVadTickAt = nil
        lastAnnouncedVadCountdown = nil
        overlay.setLevel(0)
        overlay.show(machine.isLocked ? .listeningLocked(level: 0) : .listening(level: 0))
        refreshUI()
    }

    private func beginCommandRecording() {
        switch AudioRecorder.permission() {
        case .authorized: break
        case .notDetermined:
            PermissionKind.microphone.request()
            return abortRecording(.micDenied)
        default:
            return abortRecording(.micDenied)
        }
        guard engineState.isReady else {
            if let e = configError { return abortRecording(e) }
            if case .failed(let e) = engineState { return abortRecording(e) }
            return abortRecording(.engineNotRunning)
        }
        targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        do {
            try recorder.start(deviceUID: resolvedMicDeviceUIDForRecording())
        } catch let e as ClientError {
            return abortRecording(e)
        } catch {
            return abortRecording(.micUnavailable(error.localizedDescription))
        }
        recordingStartedAt = Self.now
        warnedApproachingLimit = false
        // Command Mode không dùng giới hạn/VAD mở rộng — đảm bảo không "ăn ké" cấu hình còn sót lại
        // từ lượt ghi khoá trước đó.
        machine.maxRecording = HotkeyStateMachine.defaultMaxRecording
        vad = nil
        overlay.setLevel(0)
        overlay.show(.listeningCommand(level: 0))
        refreshUI()
        // Lấy đoạn đang chọn NGAY LÚC BẮT ĐẦU, song song với ghi âm lệnh (xem contract/engine-api.md,
        // mục Command Mode, bước a) — chờ ở `finishCommandRecording` nếu chưa xong.
        let pb = pasteboard
        commandSelectionTask = Task {
            await SelectionCapture.capture(
                ax: { AXSelection.selectedText() },
                pasteboard: pb,
                sendCopy: { CopyKeystroke.send() },
                now: { Self.now },
                sleep: { try? await Task.sleep(for: $0) })
        }
    }

    /// Giới hạn ghi của engine hiện biết (`max_audio_seconds` ở `/healthz`, chưa có trong contract
    /// hiện tại ⇒ thường `nil` — xem `RecordingLimit.resolve`).
    private var currentMaxAudioSeconds: Int? {
        if case .running(_, let h) = engineState { return h.maxAudioSeconds }
        return nil
    }

    /// VAD năng lượng CHỈ áp dụng cho ghi khoá (hands-free, đúp ⌥) — KHÔNG áp dụng cho kiểu giữ
    /// phím thường (xem contract mục 7b). Tự dừng = feed `.leftOptionUp` logic, Y HỆT hiệu ứng khi
    /// người dùng bấm phím giữ một lần nữa để kết thúc ghi khoá.
    private func processVoiceActivity(level: Float) {
        guard machine.isLocked, vad != nil else { return }
        let now = Self.now
        let dt = lastVadTickAt.map { now - $0 } ?? 0.1
        lastVadTickAt = now
        vad?.process(level: level, chunkSeconds: dt)
        guard let v = vad else { return }
        let limit = Double(cachedSettings.silenceStopSeconds)
        if let remaining = v.secondsUntilStop(limitSeconds: limit) {
            let whole = Int(remaining.rounded(.up))
            if whole <= 5, whole != lastAnnouncedVadCountdown {
                lastAnnouncedVadCountdown = whole
                overlay.show(.notice("Im lặng — tự dừng sau \(whole) giây"), thenRestore: currentListeningOverlay())
            }
        } else {
            lastAnnouncedVadCountdown = nil
        }
        if v.shouldStop(afterSilenceSeconds: limit) {
            vad = nil
            perform(machine.handle(.leftOptionUp, at: now))
            updateTicking()
        }
    }

    private func micInterrupted(_ why: String) {
        guard machine.isRecording else { return }
        abortRecording(.micUnavailable(why))
    }

    private func finishRecording() {
        let pcm = recorder.stop()
        let m = mode
        retry.store(pcm: pcm, mode: m.rawValue, app: targetApp, at: Self.now)
        send(pcm: pcm, mode: m, app: targetApp)
    }

    /// Command Mode: dừng ghi lệnh, chờ đoạn đã chọn (nếu chưa xong), rồi
    /// `POST /v1/transcribe?mode=normal` lấy chữ lệnh, sau đó `POST /v1/command`.
    private func finishCommandRecording() {
        let pcm = recorder.stop()
        let app = targetApp
        let selectionTask = commandSelectionTask
        commandSelectionTask = nil
        overlay.show(.transcribing)
        refreshUI()
        let portResult = resolvedPort()
        inflight = Task { [session] in
            let selection = await selectionTask?.value
            let result: Result<CommandDeliveryResult, ClientError>
            switch portResult {
            case .failure(let e):
                result = .failure(e)
            case .success(let port):
                switch readToken() {
                case .failure(let e):
                    result = .failure(e)
                case .success(let token):
                    let transcribed = await Self.transcribe(session: session, port: port, token: token, pcm: pcm, mode: .normal, app: app)
                    switch transcribed {
                    case .failure(let e):
                        result = .failure(e)
                    case .success(let r):
                        let instruction = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if r.silence || instruction.isEmpty {
                            result = .success(CommandDeliveryResult(instruction: "", command: nil, audioMs: r.audioMs))
                        } else {
                            let cmdResult = await Self.command(session: session, port: port, token: token, instruction: instruction,
                                                               selection: selection ?? "", context: "", app: app)
                            switch cmdResult {
                            case .failure(let e): result = .failure(e)
                            case .success(let c): result = .success(CommandDeliveryResult(instruction: instruction, command: c, audioMs: r.audioMs))
                            }
                        }
                    }
                }
            }
            guard !Task.isCancelled else { return }
            await self.deliverCommand(result)
        }
    }

    func retryLast() {
        guard let e = retry.current(at: Self.now), machine.beginExternalJob(at: Self.now) else { return }
        updateTicking()
        send(pcm: e.pcm, mode: DictationMode(rawValue: e.mode) ?? .auto, app: e.app)
    }

    var canRetry: Bool {
        var r = retry
        return r.current(at: Self.now) != nil && machine.phase == .idle
    }

    /// "Chèn lại câu vừa rồi" (menu thanh trạng thái/Dock, phím tắt ⌥⌘V mặc định) — dùng CÙNG
    /// nguồn/đường chèn với dictation (xem `VFlowCore.LastSpokenText`). Im lặng bỏ qua nếu đang ghi
    /// âm/dịch (không chồng lên việc khác đang chạy).
    func reinsertLastSentence() {
        guard machine.phase == .idle else { return }
        let historyTop = (try? historyStore.list())?.entries.first?.text
        guard let text = LastSpokenText.resolve(historyEnabled: historyEnabled, historyTopText: historyTop, inMemoryText: lastSpokenTextMemory) else {
            overlay.show(.notice(LastSpokenText.noSentenceMessage))
            return
        }
        guard machine.beginExternalJob(at: Self.now) else { return }
        updateTicking()
        Task { @MainActor in
            let inserter = ClipboardInserter(pasteboard: pasteboard, sendPaste: { PasteKeystroke.send() },
                                             wait: { try? await Task.sleep(for: $0) },
                                             hasFocusedTextInput: Self.hasFocusedTextInputOrUnknown)
            let outcome = await inserter.insert(text)
            let overlayState = DictationDecision.overlay(after: outcome, planned: .done)
            if case .error(let m) = overlayState { lastError = m } else { lastError = nil }
            overlay.show(overlayState)
            machine.finished(optionHeld: hotkeys.leftOptionHeldNow())
            updateTicking()
            refreshUI()
        }
    }

    private func send(pcm: Data, mode: DictationMode, app: String?) {
        overlay.show(.transcribing)
        refreshUI()
        let portResult = resolvedPort()
        inflight = Task { [session] in
            let result: Result<TranscribeResult, ClientError>
            switch portResult {
            case .failure(let e):
                result = .failure(e)
            case .success(let port):
                switch readToken() {
                case .success(let token):
                    result = await Self.transcribe(session: session, port: port, token: token, pcm: pcm, mode: mode, app: app)
                case .failure(let e):
                    result = .failure(e)
                }
            }
            guard !Task.isCancelled else { return }
            await self.deliver(result)
        }
    }

    /// Cổng thật để gọi engine, hoặc lỗi — KHÔNG BAO GIỜ âm thầm dùng `ClientConfig.defaultPort`
    /// khi cấu hình chưa biết/lỗi (xem `EnginePortResolution`).
    private func resolvedPort() -> Result<Int, ClientError> {
        switch EnginePortResolution.resolve(spec: engineSpec, configError: configError) {
        case .port(let p): return .success(p)
        case .blocked(let e): return .failure(e)
        }
    }

    /// Token đọc từ `<VFLOW_HOME>/token` ở MỖI lần gửi (engine tự tạo khi chạy lần đầu).
    private func readToken() -> Result<String, ClientError> {
        let tokenPath = vflowHome + "/token"
        guard let contents = try? String(contentsOfFile: tokenPath, encoding: .utf8) else {
            return .failure(.tokenMissing(path: tokenPath))
        }
        guard let token = EngineAPI.parseToken(contents) else { return .failure(.tokenInvalid(path: tokenPath)) }
        return .success(token)
    }

    nonisolated static func transcribe(session: URLSession, port: Int, token: String, pcm: Data,
                                       mode: DictationMode, app: String?) async -> Result<TranscribeResult, ClientError> {
        let req = EngineAPI.transcribeRequest(port: port, token: token, pcm: pcm, mode: mode, app: app)
        do {
            let (data, resp) = try await session.data(for: req)
            return EngineAPI.parseTranscribe(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch let e as URLError where e.code == .cannotConnectToHost || e.code == .networkConnectionLost {
            return .failure(.engineNotRunning)
        } catch let e as URLError where e.code == .timedOut {
            return .failure(.engine(status: 0, code: "timeout", message: "hết thời gian chờ"))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    nonisolated static func command(session: URLSession, port: Int, token: String, instruction: String,
                                    selection: String, context: String, app: String?) async -> Result<CommandResult, ClientError> {
        let req = EngineAPI.commandRequest(port: port, token: token, instruction: instruction, selection: selection, context: context, app: app)
        do {
            let (data, resp) = try await session.data(for: req)
            return EngineAPI.parseCommand(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch let e as URLError where e.code == .cannotConnectToHost || e.code == .networkConnectionLost {
            return .failure(.engineNotRunning)
        } catch let e as URLError where e.code == .timedOut {
            return .failure(.engine(status: 0, code: "timeout", message: "hết thời gian chờ"))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// Chỉ tin kết quả dò ô nhập khi ĐÃ có quyền Trợ năng; thiếu quyền thì coi là "có" để nhường cho
    /// đường cũ `PasteKeystroke.send()` → `.pasteFailedTextLeftOnClipboard` báo đúng lý do (thiếu
    /// quyền), không lẫn với thông báo "Đã chép — bấm ⌘V" của trường hợp không có ô nhập.
    private static func hasFocusedTextInputOrUnknown() -> Bool {
        guard CGPreflightPostEventAccess() else { return true }
        return FocusedInputProbe.hasFocusedTextInput()
    }

    private func deliver(_ result: Result<TranscribeResult, ClientError>) async {
        inflight = nil
        let plan = DictationDecision.plan(for: result)
        if plan.clearRetry { retry.clear() }
        var overlayState = plan.overlay
        if let text = plan.insert {
            let inserter = ClipboardInserter(pasteboard: pasteboard, sendPaste: { PasteKeystroke.send() },
                                             wait: { try? await Task.sleep(for: $0) },
                                             hasFocusedTextInput: Self.hasFocusedTextInputOrUnknown)
            let outcome = await inserter.insert(text)
            overlayState = DictationDecision.overlay(after: outcome, planned: plan.overlay)
            let pasted = outcome == .pastedRestored || outcome == .pastedNotRestoredUserChanged
            if pasted, case .success(let r) = result, EnterAction.shouldSend(actions: r.actions, actionsEnabled: cachedSettings.actionsEnabled) {
                try? await Task.sleep(for: .milliseconds(150))
                if !ReturnKeystroke.send() { overlayState = .error(ErrorText.message(.enterKeystrokeFailed)) }
            }
        }
        if case .error(let m) = overlayState { lastError = m } else { lastError = nil }
        if let text = plan.insert { lastSpokenTextMemory = text }
        recordHistoryIfNeeded(result: result, insertedText: plan.insert)
        overlay.show(overlayState)
        machine.finished(optionHeld: hotkeys.leftOptionHeldNow())
        updateTicking()
        refreshUI()
    }

    /// Kết quả Command Mode: `instruction` rỗng ⇒ không nghe thấy gì (đã dừng trước khi gọi `/v1/command`).
    private struct CommandDeliveryResult {
        var instruction: String
        var command: CommandResult?
        var audioMs: Int?
    }

    private func deliverCommand(_ result: Result<CommandDeliveryResult, ClientError>) async {
        inflight = nil
        switch result {
        case .failure(let e):
            lastError = ErrorText.message(e)
            overlay.show(.error(lastError!))
        case .success(let r):
            if r.instruction.isEmpty || r.command == nil {
                overlay.show(.notice(OverlayText.heardNothing))
                lastError = nil
            } else {
                let cmd = r.command!
                let inserter = ClipboardInserter(pasteboard: pasteboard, sendPaste: { PasteKeystroke.send() },
                                                 wait: { try? await Task.sleep(for: $0) },
                                                 hasFocusedTextInput: Self.hasFocusedTextInputOrUnknown)
                let outcome = await inserter.insert(cmd.text)
                let overlayState = DictationDecision.overlay(after: outcome, planned: .done)
                if case .error(let m) = overlayState { lastError = m } else { lastError = nil }
                lastSpokenTextMemory = cmd.text
                overlay.show(overlayState)
                recordCommandHistory(instruction: r.instruction, command: cmd, audioMs: r.audioMs)
            }
        }
        machine.finished(optionHeld: hotkeys.leftOptionHeldNow())
        updateTicking()
        refreshUI()
    }

    /// CHỈ lưu lệnh và kết quả — TUYỆT ĐỐI không lưu đoạn đang chọn (xem contract/engine-api.md,
    /// mục Command Mode).
    private func recordCommandHistory(instruction: String, command: CommandResult, audioMs: Int?) {
        guard historyEnabled else { return }
        let entry = HistoryEntry(at: Date(), appBundleId: targetApp, mode: "command:\(command.kind)",
                                 model: "", textRaw: instruction, text: command.text, audioMs: audioMs, totalMs: nil)
        do { try historyStore.append(entry) } catch {
            if lastError == nil { lastError = "Không ghi được lịch sử: \(error)" }
        }
    }

    /// Kết quả lỗi/im lặng không bao giờ vào lịch sử (`insertedText == nil` lúc đó). CHỈ lưu văn
    /// bản (text_raw, text, mode, app, model, audio_ms, timings) — tuyệt đối không có âm thanh.
    private func recordHistoryIfNeeded(result: Result<TranscribeResult, ClientError>, insertedText: String?) {
        guard case .success(let r) = result, HistoryGate.shouldRecord(enabled: historyEnabled, insertedText: insertedText) else { return }
        let entry = HistoryEntry(at: Date(), appBundleId: targetApp, mode: r.mode, model: r.model,
                                 textRaw: r.textRaw, text: r.text, audioMs: r.audioMs, totalMs: r.totalMs)
        do { try historyStore.append(entry) } catch {
            if lastError == nil { lastError = "Không ghi được lịch sử: \(error)" }
        }
    }

    private func setError(_ message: String, showOverlay: Bool) {
        lastError = message
        if showOverlay { overlay.show(.error(message)) }
        refreshUI()
    }

    var phase: HotkeyPhase { machine.phase }

    // MARK: lịch sử

    func listHistory(query: String?) throws -> HistoryStore.ReadResult { try historyStore.list(query: query) }
    func deleteHistory(id: String) throws { try historyStore.delete(id: id) }
    func clearHistory() throws { try historyStore.clearAll() }

    // MARK: từ điển + gợi ý sửa (đọc-sửa-ghi qua `DictionaryOrchestration`)

    func fetchDictionary() async -> Result<[DictionaryEntry], ClientError> {
        switch resolvedPort() {
        case .failure(let e): return .failure(e)
        case .success(let port):
            switch readToken() {
            case .failure(let e): return .failure(e)
            case .success(let token): return await Self.requestDictionaryList(session: session, port: port, token: token)
            }
        }
    }

    func applyDictionaryChange(_ change: DictionaryChange) async -> Result<[DictionaryEntry], ClientError> {
        switch resolvedPort() {
        case .failure(let e): return .failure(e)
        case .success(let port):
            switch readToken() {
            case .failure(let e): return .failure(e)
            case .success(let token):
                let session = self.session // không bắt `self` (MainActor) vào closure @Sendable
                return await DictionaryOrchestration.applyChange(
                    change,
                    get: { await Self.requestDictionaryList(session: session, port: port, token: token) },
                    put: { entries in await Self.requestDictionaryPut(session: session, port: port, token: token, entries: entries) })
            }
        }
    }

    func acceptSuggestion(_ suggestion: CorrectionSuggestion) async -> Result<[DictionaryEntry], ClientError> {
        switch resolvedPort() {
        case .failure(let e): return .failure(e)
        case .success(let port):
            switch readToken() {
            case .failure(let e): return .failure(e)
            case .success(let token):
                let session = self.session
                return await DictionaryOrchestration.acceptSuggestion(
                    suggestion,
                    get: { await Self.requestDictionaryList(session: session, port: port, token: token) },
                    put: { entries in await Self.requestDictionaryPut(session: session, port: port, token: token, entries: entries) })
            }
        }
    }

    func fetchCorrectionSuggestions(before: String, after: String) async -> Result<[CorrectionSuggestion], ClientError> {
        switch resolvedPort() {
        case .failure(let e): return .failure(e)
        case .success(let port):
            switch readToken() {
            case .failure(let e): return .failure(e)
            case .success(let token):
                return await Self.requestCorrections(session: session, port: port, token: token, before: before, after: after)
            }
        }
    }

    nonisolated static func requestDictionaryList(session: URLSession, port: Int, token: String) async -> Result<[DictionaryEntry], ClientError> {
        do {
            let (data, resp) = try await session.data(for: EngineAPI.dictionaryGetRequest(port: port, token: token))
            return EngineAPI.parseDictionaryList(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    nonisolated static func requestDictionaryPut(session: URLSession, port: Int, token: String, entries: [DictionaryEntry]) async -> Result<[DictionaryEntry], ClientError> {
        do {
            let (data, resp) = try await session.data(for: EngineAPI.dictionaryPutRequest(port: port, token: token, entries: entries))
            return EngineAPI.parseDictionaryList(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    nonisolated static func requestCorrections(session: URLSession, port: Int, token: String, before: String, after: String) async -> Result<[CorrectionSuggestion], ClientError> {
        do {
            let (data, resp) = try await session.data(for: EngineAPI.correctionsRequest(port: port, token: token, before: before, after: after))
            return EngineAPI.parseCorrections(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: snippets (đọc-sửa-ghi qua `SnippetOrchestration`, giống từ điển)

    func fetchSnippets() async -> Result<[SnippetEntry], ClientError> {
        switch resolvedPort() {
        case .failure(let e): return .failure(e)
        case .success(let port):
            switch readToken() {
            case .failure(let e): return .failure(e)
            case .success(let token): return await Self.requestSnippetsList(session: session, port: port, token: token)
            }
        }
    }

    func applySnippetChange(_ change: SnippetChange) async -> Result<[SnippetEntry], ClientError> {
        switch resolvedPort() {
        case .failure(let e): return .failure(e)
        case .success(let port):
            switch readToken() {
            case .failure(let e): return .failure(e)
            case .success(let token):
                let session = self.session
                return await SnippetOrchestration.applyChange(
                    change,
                    get: { await Self.requestSnippetsList(session: session, port: port, token: token) },
                    put: { entries in await Self.requestSnippetsPut(session: session, port: port, token: token, entries: entries) })
            }
        }
    }

    nonisolated static func requestSnippetsList(session: URLSession, port: Int, token: String) async -> Result<[SnippetEntry], ClientError> {
        do {
            let (data, resp) = try await session.data(for: EngineAPI.snippetsGetRequest(port: port, token: token))
            return EngineAPI.parseSnippetList(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    nonisolated static func requestSnippetsPut(session: URLSession, port: Int, token: String, entries: [SnippetEntry]) async -> Result<[SnippetEntry], ClientError> {
        do {
            let (data, resp) = try await session.data(for: EngineAPI.snippetsPutRequest(port: port, token: token, entries: entries))
            return EngineAPI.parseSnippetList(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: cài đặt đám mây (GET/PUT /v1/settings)

    func fetchSettings() async -> Result<AppSettings, ClientError> {
        switch resolvedPort() {
        case .failure(let e): return .failure(e)
        case .success(let port):
            switch readToken() {
            case .failure(let e): return .failure(e)
            case .success(let token):
                let r = await Self.requestSettingsGet(session: session, port: port, token: token)
                if case .success(let s) = r { cachedSettings = s }
                return r
            }
        }
    }

    func applySettingsPatch(_ patch: SettingsPatch) async -> Result<AppSettings, ClientError> {
        switch resolvedPort() {
        case .failure(let e): return .failure(e)
        case .success(let port):
            switch readToken() {
            case .failure(let e): return .failure(e)
            case .success(let token):
                let r = await Self.requestSettingsPut(session: session, port: port, token: token, patch: patch)
                if case .success(let s) = r { cachedSettings = s }
                return r
            }
        }
    }

    nonisolated static func requestSettingsGet(session: URLSession, port: Int, token: String) async -> Result<AppSettings, ClientError> {
        do {
            let (data, resp) = try await session.data(for: EngineAPI.settingsGetRequest(port: port, token: token))
            return EngineAPI.parseSettings(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    nonisolated static func requestSettingsPut(session: URLSession, port: Int, token: String, patch: SettingsPatch) async -> Result<AppSettings, ClientError> {
        do {
            let (data, resp) = try await session.data(for: EngineAPI.settingsPutRequest(port: port, token: token, patch: patch))
            return EngineAPI.parseSettings(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: đăng nhập

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            setError("Không đổi được “Bật khi đăng nhập”: \(error.localizedDescription)", showOverlay: true)
        }
        refreshUI()
    }
}
