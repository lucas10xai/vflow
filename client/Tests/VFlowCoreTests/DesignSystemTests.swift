import Foundation
import Testing
@testable import VFlowCore

@Suite struct DesignSystemTests {

    // MARK: ContrastText

    @Test func blackOnWhiteWinsContrast() {
        #expect(ContrastText.textColor(onBackgroundHex: "FFFFFF") == .black)
    }

    @Test func whiteOnBlackWinsContrast() {
        #expect(ContrastText.textColor(onBackgroundHex: "000000") == .white)
    }

    @Test func brandAccentPickedTextMeetsAA() {
        guard let choice = ContrastText.textColor(onBackgroundHex: BrandColor.accentHex) else {
            Issue.record("không đọc được hex thương hiệu"); return
        }
        #expect(ContrastText.meetsAA(choice: choice, onBackgroundHex: BrandColor.accentHex),
                 "chữ \(choice) trên nền #\(BrandColor.accentHex) phải đạt AA (≥4.5:1)")
    }

    @Test func invalidHexReturnsNilNotSilentDefault() {
        #expect(ContrastText.textColor(onBackgroundHex: "not-a-color") == nil)
        #expect(ContrastText.relativeLuminance(hex: "ZZZZZZ") == nil)
        #expect(ContrastText.relativeLuminance(hex: "ABC") == nil)
    }

    @Test func contrastRatioSymmetricAndAtLeastOne() {
        let a = ContrastText.relativeLuminance(hex: "ED6300")!
        let b = ContrastText.relativeLuminance(hex: "FFFFFF")!
        #expect(ContrastText.contrastRatio(a, b) == ContrastText.contrastRatio(b, a))
        #expect(ContrastText.contrastRatio(a, b) >= 1)
    }

    // MARK: ModeCloudLabel — khớp contract/engine-api.md (tidy, email gửi đám mây; còn lại trong máy)

    @Test func modeCloudLabelMatchesContractForEachMode() {
        let expectedCloud: Set<DictationMode> = [.tidy, .email]
        for m in DictationMode.allCases {
            let expected = expectedCloud.contains(m) ? ModeCloudLabel.cloud : ModeCloudLabel.local
            #expect(ModeCloudLabel.text(m) == expected, "chế độ \(m) phải có nhãn \"\(expected)\"")
        }
    }

    @Test func modeCloudLabelDerivedFromContractFlagNotHardcoded() {
        // Phá nhánh: nếu hàm hardcode sai một chế độ, test này bắt được vì so sánh trực tiếp với
        // `sendsTextToCloud` (nguồn thật), không lặp lại danh sách tay ở trên.
        for m in DictationMode.allCases {
            let expected = m.sendsTextToCloud ? ModeCloudLabel.cloud : ModeCloudLabel.local
            #expect(ModeCloudLabel.text(m) == expected)
        }
    }

    // MARK: ModelReasonText

    @Test func modelReasonTextKnownCodes() {
        #expect(ModelReasonText.friendly("not_downloaded") == "Chưa tải về")
        #expect(ModelReasonText.friendly("missing_token") == "Chưa có khoá truy cập")
        #expect(ModelReasonText.friendly("tunnel_down") == "Chưa kết nối")
        #expect(ModelReasonText.friendly("loading") == "Đang tải")
        #expect(ModelReasonText.friendly("loaded") == "Sẵn sàng")
    }

    @Test func modelReasonTextUnknownCodeShowsRawCodeNeverSilent() {
        let out = ModelReasonText.friendly("some_future_reason")
        #expect(out == "(some_future_reason)")
        #expect(!out.isEmpty)
    }

    // MARK: PermissionsProgress

    @Test func permissionsProgressCounts() {
        let none = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: false) }
        #expect(PermissionsProgress.text(none) == "Đã cấp 0/3")
        #expect(!PermissionsProgress.allGranted(none))

        var two = none
        two[0].granted = true
        two[1].granted = true
        #expect(PermissionsProgress.text(two) == "Đã cấp 2/3")
        #expect(!PermissionsProgress.allGranted(two))

        let all = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) }
        #expect(PermissionsProgress.text(all) == "Đã cấp 3/3")
        #expect(PermissionsProgress.allGranted(all))
    }

    // MARK: WelcomeDecision

    @Test func welcomeHiddenWhenSeenAndFullyGranted() {
        let all = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) }
        #expect(!WelcomeDecision.shouldAutoShow(hasSeenWelcome: true, permissions: all))
    }

    @Test func welcomeShownWhenNeverSeenEvenIfFullyGranted() {
        let all = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) }
        #expect(WelcomeDecision.shouldAutoShow(hasSeenWelcome: false, permissions: all))
    }

    /// Phá nhánh quan trọng nhất: đã xem rồi (hasSeenWelcome=true) nhưng THIẾU quyền ⇒ vẫn phải
    /// hiện lại (OR, không phải AND) — nếu cài sai thành AND thì test này đỏ.
    @Test func welcomeShownWhenSeenButMissingPermissions() {
        var items = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) }
        items[0].granted = false
        #expect(WelcomeDecision.shouldAutoShow(hasSeenWelcome: true, permissions: items))
    }

    // MARK: HeroStatusDecision

    private func baseModel(permissions: [PermissionItem], engineReady: Bool, engineBlocked: Bool,
                            lastError: String?) -> StatusModel {
        StatusModel(engineSummary: "tóm tắt", models: [], permissions: permissions, mode: .auto,
                   lastError: lastError, canRetryLast: false, launchAtLogin: false, conflictWarning: nil,
                   hotkeysActive: true, engineHasFailed: engineBlocked, engineReady: engineReady,
                   engineBlocked: engineBlocked)
    }

    @Test func heroReadyWhenNothingWrong() {
        let all = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) }
        let m = baseModel(permissions: all, engineReady: true, engineBlocked: false, lastError: nil)
        #expect(HeroStatusDecision.decide(m) == .ready)
    }

    @Test func heroMissingPermissionsTakesPriorityOverEverythingElse() {
        var items = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) }
        items[0].granted = false
        // Engine cũng lỗi + có lastError — vẫn phải báo thiếu quyền trước (ưu tiên cao nhất).
        let m = baseModel(permissions: items, engineReady: false, engineBlocked: true, lastError: "lỗi khác")
        #expect(HeroStatusDecision.decide(m) == .missingPermissions(count: 1))
    }

    @Test func heroStartingEngineWhenNotReadyAndNotBlocked() {
        let all = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) }
        let m = baseModel(permissions: all, engineReady: false, engineBlocked: false, lastError: nil)
        #expect(HeroStatusDecision.decide(m) == .startingEngine)
    }

    @Test func heroProblemWhenEngineBlocked() {
        let all = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) }
        let m = baseModel(permissions: all, engineReady: false, engineBlocked: true, lastError: nil)
        #expect(HeroStatusDecision.decide(m) == .problem(message: "tóm tắt"))
    }

    @Test func heroProblemWhenLastErrorPresentAndEngineOtherwiseFine() {
        let all = PermissionKind.allCases.map { PermissionItem(kind: $0, granted: true) }
        let m = baseModel(permissions: all, engineReady: true, engineBlocked: false, lastError: "dán lỗi")
        #expect(HeroStatusDecision.decide(m) == .problem(message: "dán lỗi"))
    }

    // MARK: TodayStats

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test func todayStatsDisabledWhenHistoryOff() {
        let now = Date()
        let entries = [HistoryEntry(at: now, mode: "normal", model: "m", textRaw: "a", text: "một hai ba")]
        #expect(TodayStats.summarize(entries: entries, historyEnabled: false, now: now) == .disabled)
    }

    @Test func todayStatsZeroWhenNoEntriesTodayButHistoryOn() {
        let now = Date()
        #expect(TodayStats.summarize(entries: [], historyEnabled: true, now: now)
                == .data(sentences: 0, words: 0, speakingMs: 0))
    }

    @Test func todayStatsCountsWordsAndAudioForTodayOnly() {
        let cal = utcCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
        let todayA = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 8))!
        let todayB = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
        let entries = [
            HistoryEntry(at: todayA, mode: "normal", model: "m", textRaw: "", text: "một hai ba", audioMs: 1000),
            HistoryEntry(at: todayB, mode: "command:edit", model: "", textRaw: "lệnh", text: "bốn năm", audioMs: 500),
        ]
        let result = TodayStats.summarize(entries: entries, historyEnabled: true, now: now, calendar: cal)
        #expect(result == .data(sentences: 2, words: 5, speakingMs: 1500))
    }

    /// Phá nhánh: một mục từ NGÀY KHÁC không được lẫn vào tổng "Hôm nay", dù nhiều hơn mục hôm nay.
    @Test func todayStatsExcludesEntriesFromOtherDays() {
        let cal = utcCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 8))!
        let entries = [
            HistoryEntry(at: yesterday, mode: "normal", model: "m", textRaw: "", text: "một hai ba bốn năm sáu", audioMs: 9000),
            HistoryEntry(at: today, mode: "normal", model: "m", textRaw: "", text: "một", audioMs: 100),
        ]
        let result = TodayStats.summarize(entries: entries, historyEnabled: true, now: now, calendar: cal)
        #expect(result == .data(sentences: 1, words: 1, speakingMs: 100))
    }

    @Test func todayStatsHandlesEmptyTextAsZeroWords() {
        let now = Date()
        let entries = [HistoryEntry(at: now, mode: "normal", model: "m", textRaw: "", text: "")]
        let result = TodayStats.summarize(entries: entries, historyEnabled: true, now: now)
        #expect(result == .data(sentences: 1, words: 0, speakingMs: 0))
    }
}
