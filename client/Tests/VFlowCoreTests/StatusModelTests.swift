import Testing
@testable import VFlowCore

@Suite struct StatusModelTests {
    static let spec = EngineLaunchSpec(node: "/opt/homebrew/bin/node", script: "/repo/bin/vflow.js", repo: "/repo", port: 7611)
    static let readyHealth = Health(version: "0.1.0", models: [
        ModelStatus(id: "zipformer-vi-30m", kind: "local", loaded: true, reason: nil),
    ])
    static let notReadyHealth = Health(version: "0.1.0", models: [
        ModelStatus(id: "zipformer-vi-30m", kind: "local", loaded: false, reason: "not_downloaded"),
        ModelStatus(id: "phowhisper-large", kind: "remote", loaded: false, reason: "tunnel_down"),
    ])

    func permissions(micGranted: Bool = true, inputGranted: Bool = true, axGranted: Bool = true) -> [PermissionItem] {
        [PermissionItem(kind: .microphone, granted: micGranted),
         PermissionItem(kind: .inputMonitoring, granted: inputGranted),
         PermissionItem(kind: .accessibility, granted: axGranted)]
    }

    // MARK: quyền

    @Test func allGrantedHasNoMissingPermissions() {
        let m = StatusModel.build(engineState: .stopped, configError: nil, lastError: nil,
                                   permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(m.missingPermissions.isEmpty)
        #expect(m.permissions.count == 3)
    }

    @Test func missingPermissionIsReportedByKindNotLumpedTogether() {
        let m = StatusModel.build(engineState: .stopped, configError: nil, lastError: nil,
                                   permissions: permissions(inputGranted: false), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: false)
        #expect(m.missingPermissions == [PermissionItem(kind: .inputMonitoring, granted: false)])
        #expect(m.missingPermissions.first?.statusText == "Chưa cấp")
        #expect(m.permissions.first(where: { $0.kind == .microphone })?.statusText == "Đã cấp")
    }

    @Test func eachPermissionKindHasDistinctTitleWhyAndSettingsAnchor() {
        // Phá nhánh này (vd. hai case trả cùng anchor) phải làm test đỏ: chủ dự án sẽ mở nhầm trang Cài đặt.
        let anchors = Set(PermissionKind.allCases.map(\.settingsAnchor))
        let titles = Set(PermissionKind.allCases.map(\.title))
        #expect(anchors.count == PermissionKind.allCases.count)
        #expect(titles.count == PermissionKind.allCases.count)
        #expect(PermissionKind.accessibility.settingsAnchor == "Privacy_Accessibility")
        #expect(PermissionKind.inputMonitoring.settingsAnchor == "Privacy_ListenEvent")
        #expect(PermissionKind.microphone.settingsAnchor == "Privacy_Microphone")
    }

    // MARK: engine + model (lý do khi chưa tải)

    @Test func runningWithLoadedModelReportsReady() {
        let m = StatusModel.build(engineState: .running(owned: true, health: Self.readyHealth), configError: nil,
                                   lastError: nil, permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(m.engineSummary.contains("sẵn sàng"))
        #expect(!m.engineSummary.contains("CHƯA"))
        #expect(m.models == Self.readyHealth.models)
        #expect(!m.engineHasFailed)
    }

    @Test func runningWithoutLoadedModelKeepsEachModelsReasonVisible() {
        let m = StatusModel.build(engineState: .running(owned: true, health: Self.notReadyHealth), configError: nil,
                                   lastError: nil, permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(m.engineSummary.contains("CHƯA"))
        #expect(m.models.map(\.reason) == ["not_downloaded", "tunnel_down"])
        // Bất biến hợp đồng: loaded:false luôn kèm reason (không bao giờ im lặng).
        #expect(m.models.allSatisfy { $0.loaded || $0.reason != nil })
    }

    @Test func configErrorTakesPriorityOverEngineStateAndClearsModelList() {
        let m = StatusModel.build(engineState: .running(owned: true, health: Self.readyHealth),
                                   configError: .configInvalid("\"node\" không chạy được: /nope"), lastError: nil,
                                   permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(m.engineSummary.contains("/nope"))
        #expect(m.models.isEmpty)
    }

    @Test func failedEngineStateIsFlaggedForRestartButton() {
        let m = StatusModel.build(engineState: .failed(.engineGaveUp("engine thoát (mã 1)")), configError: nil,
                                   lastError: nil, permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(m.engineHasFailed)
        #expect(m.engineSummary.contains("ngừng khởi động lại"))
    }

    // MARK: engineReady/engineBlocked (hồi quy M4b/Phần 1 — tab Từ điển dựa vào hai cờ này để
    // phân biệt "đang chờ" / "sẵn sàng" / "lỗi thật", không gọi engine quá sớm và không treo chờ
    // vô thời hạn khi engine sẽ không bao giờ tự lên).

    @Test func startingIsWaitingNeitherReadyNorBlocked() {
        let m = StatusModel.build(engineState: .starting, configError: nil, lastError: nil,
                                   permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(!m.engineReady)
        #expect(!m.engineBlocked, "đang khởi động không phải là lỗi — tab Từ điển phải hiện 'đang chờ', không phải đỏ")
    }

    @Test func restartingIsStillWaitingNotBlocked() {
        let m = StatusModel.build(engineState: .restarting(attempt: 1, delay: .seconds(1)), configError: nil,
                                   lastError: nil, permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(!m.engineReady)
        #expect(!m.engineBlocked, "engine tự khởi động lại vẫn có thể lên được, không phải lỗi chặn")
    }

    @Test func runningIsReadyAndNotBlocked() {
        let m = StatusModel.build(engineState: .running(owned: true, health: Self.readyHealth), configError: nil,
                                   lastError: nil, permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(m.engineReady)
        #expect(!m.engineBlocked)
    }

    @Test func failedEngineIsBlockedNotReady() {
        let m = StatusModel.build(engineState: .failed(.engineGaveUp("x")), configError: nil, lastError: nil,
                                   permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(!m.engineReady)
        #expect(m.engineBlocked)
    }

    @Test func configErrorIsBlockedAndNeverCountsAsReady() {
        // Dù (trên thực tế không xảy ra) engineState trông như đang chạy, configError nghĩa là
        // không có cổng/engine thật để tin — không được coi là "sẵn sàng".
        let m = StatusModel.build(engineState: .running(owned: true, health: Self.readyHealth),
                                   configError: .configInvalid("chưa biết repo vflow"), lastError: nil,
                                   permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(!m.engineReady)
        #expect(m.engineBlocked)
    }

    // MARK: nút "Thử lại lần cuối"

    @Test func retryButtonEnabledOnlyWhenBufferHasAudio() {
        let withAudio = StatusModel.build(engineState: .stopped, configError: nil, lastError: nil,
                                           permissions: permissions(), mode: .auto, canRetryLast: true,
                                           launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        let withoutAudio = StatusModel.build(engineState: .stopped, configError: nil, lastError: nil,
                                              permissions: permissions(), mode: .auto, canRetryLast: false,
                                              launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(withAudio.canRetryLast)
        #expect(!withoutAudio.canRetryLast)
    }

    // MARK: cảnh báo xung đột

    @Test func conflictWarningMentionsAppNameAndTellsUserToQuitOne() {
        let apps = [ConflictApp(bundleId: "com.sonpiaz.haynoi", displayName: "Haynoi")]
        let warning = ConflictText.warning(for: apps)
        #expect(warning == "Haynoi đang chạy: cả hai sẽ phản ứng khi giữ ⌥ trái. Hãy thoát một trong hai.")
    }

    @Test func noConflictWarningWhenNoConflictingAppRunning() {
        #expect(ConflictText.warning(for: []) == nil)
    }

    @Test func modelFlowsThroughToConflictWarningField() {
        let m = StatusModel.build(engineState: .stopped, configError: nil, lastError: nil,
                                   permissions: permissions(), mode: .auto, canRetryLast: false,
                                   launchAtLogin: false,
                                   conflictWarning: "Haynoi đang chạy: cả hai sẽ phản ứng khi giữ ⌥ trái. Hãy thoát một trong hai.",
                                   hotkeysActive: true)
        #expect(m.conflictWarning?.contains("Haynoi") == true)
        let noConflict = StatusModel.build(engineState: .stopped, configError: nil, lastError: nil,
                                            permissions: permissions(), mode: .auto, canRetryLast: false,
                                            launchAtLogin: false, conflictWarning: nil, hotkeysActive: true)
        #expect(noConflict.conflictWarning == nil)
    }

    // MARK: công tắc mặc định

    @Test func showWindowOnLaunchDefaultsToTrueButHonorsStoredValue() {
        #expect(ShowWindowPreference.resolve(stored: nil) == true)
        #expect(ShowWindowPreference.defaultValue == true)
        #expect(ShowWindowPreference.resolve(stored: false) == false)
        #expect(ShowWindowPreference.resolve(stored: true) == true)
    }
}

/// `ConflictDetector` lọc danh sách mặc định (và danh sách tuỳ chỉnh) theo tiến trình đang chạy —
/// test bằng bộ cung cấp tiến trình giả, không đụng `NSWorkspace` thật.
@Suite struct ConflictDetectorTests {
    struct FakeRunningApps: RunningAppsProvider {
        let ids: Set<String>
        func runningBundleIDs() -> Set<String> { ids }
    }

    @Test func detectsDefaultHaynoiWhenRunning() {
        let d = ConflictDetector()
        let apps = d.detect(runningBundleIDs: FakeRunningApps(ids: ["com.sonpiaz.haynoi", "com.apple.Terminal"]).runningBundleIDs())
        #expect(apps == [ConflictApp(bundleId: "com.sonpiaz.haynoi", displayName: "Haynoi")])
    }

    @Test func noConflictWhenHaynoiNotRunning() {
        let d = ConflictDetector()
        let apps = d.detect(runningBundleIDs: FakeRunningApps(ids: ["com.apple.Terminal", "com.apple.Mail"]).runningBundleIDs())
        #expect(apps.isEmpty)
    }

    @Test func customCandidateListIsHonoredInOrder() {
        let custom = [ConflictApp(bundleId: "com.example.a", displayName: "A"),
                      ConflictApp(bundleId: "com.example.b", displayName: "B")]
        let d = ConflictDetector(candidates: custom)
        let apps = d.detect(runningBundleIDs: FakeRunningApps(ids: ["com.example.b"]).runningBundleIDs())
        #expect(apps == [ConflictApp(bundleId: "com.example.b", displayName: "B")])
    }

    @Test func emptyRunningSetNeverFalselyFlagsAConflict() {
        let d = ConflictDetector()
        #expect(d.detect(runningBundleIDs: []).isEmpty)
    }
}
