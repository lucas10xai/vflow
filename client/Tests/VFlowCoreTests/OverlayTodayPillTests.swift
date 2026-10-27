import Foundation
import Testing
@testable import VFlowCore

@Suite struct TodayPillTests {
    func stats(enabled: Bool = true, today: String = "2026-10-27", days: [DayStat], totalWords: Int = 99999) -> StatsSummary {
        StatsSummary(enabled: enabled, since: nil, weeks: 16, weekStart: "2026-10-26", today: today,
                     totalWords: totalWords, totalCount: 10, totalAudioMs: 1000, avgWpm: nil,
                     currentStreak: 1, bestStreak: 1, days: days, topApps: [])
    }

    @Test func notLoadedStatsHidePillInsteadOfShowingZero() {
        #expect(TodayPill.text(from: nil) == nil)
    }

    @Test func disabledStatsHidePillEvenIfDaysCarryNumbers() {
        let s = stats(enabled: false, days: [DayStat(date: "2026-10-27", words: 500, count: 3, audioMs: 1000)])
        #expect(TodayPill.text(from: s) == nil)
    }

    @Test func zeroWordsTodayHidesPill() {
        let s = stats(days: [DayStat(date: "2026-10-27", words: 0, count: 0, audioMs: 0)])
        #expect(TodayPill.text(from: s) == nil)
    }

    @Test func noRowForTodayHidesPillEvenWhenOtherDaysHaveWords() {
        let s = stats(days: [DayStat(date: "2026-10-26", words: 800, count: 5, audioMs: 1000)])
        #expect(TodayPill.text(from: s) == nil)
    }

    @Test func usesTodayRowNotTotalOrYesterday() {
        let s = stats(days: [DayStat(date: "2026-10-26", words: 800, count: 5, audioMs: 1000),
                             DayStat(date: "2026-10-27", words: 42, count: 2, audioMs: 1000)])
        #expect(TodayPill.text(from: s) == "Hôm nay: 42 từ")
    }

    @Test func largeNumbersUseViVNDotThousandsSeparator() {
        let s = stats(days: [DayStat(date: "2026-10-27", words: 1234, count: 9, audioMs: 1000)])
        #expect(TodayPill.text(from: s) == "Hôm nay: 1.234 từ")
        let big = stats(days: [DayStat(date: "2026-10-27", words: 1_234_567, count: 9, audioMs: 1000)])
        #expect(TodayPill.text(from: big) == "Hôm nay: 1.234.567 từ")
    }
}
