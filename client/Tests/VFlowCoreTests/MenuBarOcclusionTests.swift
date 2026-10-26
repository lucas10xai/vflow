import Foundation
import Testing
@testable import VFlowCore

@Suite struct MenuBarOcclusionTests {
    typealias Rect = MenuBarOcclusion.Rect

    // Số đo thật đã ghi nhận trên máy chủ dự án (xem yêu cầu mục 4): notch x=918–1138, biểu tượng
    // vflow ở x≈1118 (rộng ~20) — nằm dưới notch, không thấy được.
    @Test func measuredNotchScenarioIsOccluded() {
        let screen = Rect(minX: 0, maxX: 2056)
        let left = Rect(minX: 0, maxX: 918)
        let right = Rect(minX: 1138, maxX: 2056)
        let item = Rect(minX: 1108, maxX: 1128)
        #expect(MenuBarOcclusion.isOccluded(itemFrame: item, screenFrame: screen, auxiliaryLeft: left, auxiliaryRight: right))
    }

    @Test func iconWellInsideLeftAuxiliaryAreaIsNotOccluded() {
        let screen = Rect(minX: 0, maxX: 2056)
        let left = Rect(minX: 0, maxX: 918)
        let right = Rect(minX: 1138, maxX: 2056)
        let item = Rect(minX: 850, maxX: 870)
        #expect(!MenuBarOcclusion.isOccluded(itemFrame: item, screenFrame: screen, auxiliaryLeft: left, auxiliaryRight: right))
    }

    @Test func iconInsideRightAuxiliaryAreaIsNotOccluded() {
        let screen = Rect(minX: 0, maxX: 2056)
        let left = Rect(minX: 0, maxX: 918)
        let right = Rect(minX: 1138, maxX: 2056)
        let item = Rect(minX: 1500, maxX: 1520)
        #expect(!MenuBarOcclusion.isOccluded(itemFrame: item, screenFrame: screen, auxiliaryLeft: left, auxiliaryRight: right))
    }

    @Test func noNotchMeansAnyPositionInScreenIsFine() {
        let screen = Rect(minX: 0, maxX: 1440)
        let item = Rect(minX: 700, maxX: 720)
        #expect(!MenuBarOcclusion.isOccluded(itemFrame: item, screenFrame: screen, auxiliaryLeft: nil, auxiliaryRight: nil))
    }

    @Test func zeroWidthItemIsOccludedEvenWithoutNotchInfo() {
        let screen = Rect(minX: 0, maxX: 1440)
        let item = Rect(minX: 700, maxX: 700)
        #expect(MenuBarOcclusion.isOccluded(itemFrame: item, screenFrame: screen, auxiliaryLeft: nil, auxiliaryRight: nil))
    }

    @Test func offScreenItemIsOccluded() {
        let screen = Rect(minX: 0, maxX: 1440)
        let item = Rect(minX: 1500, maxX: 1520)
        #expect(MenuBarOcclusion.isOccluded(itemFrame: item, screenFrame: screen, auxiliaryLeft: nil, auxiliaryRight: nil))
    }

    @Test func unknownFrameIsNeverReportedAsOccluded() {
        let screen = Rect(minX: 0, maxX: 1440)
        #expect(!MenuBarOcclusion.isOccluded(itemFrame: nil, screenFrame: screen, auxiliaryLeft: nil, auxiliaryRight: nil))
    }
}

@Suite struct MenuBarOcclusionReminderTests {
    @Test func showsWhenOccludedAndNotDismissedToday() {
        #expect(MenuBarOcclusionReminder.shouldShow(isOccluded: true, todayKey: "2026-10-27", dismissedOnDayKey: nil))
        #expect(MenuBarOcclusionReminder.shouldShow(isOccluded: true, todayKey: "2026-10-27", dismissedOnDayKey: "2026-10-26"))
    }

    @Test func hiddenWhenDismissedToday() {
        #expect(!MenuBarOcclusionReminder.shouldShow(isOccluded: true, todayKey: "2026-10-27", dismissedOnDayKey: "2026-10-27"))
    }

    @Test func hiddenWhenNotOccluded() {
        #expect(!MenuBarOcclusionReminder.shouldShow(isOccluded: false, todayKey: "2026-10-27", dismissedOnDayKey: nil))
    }

    @Test func dayKeyIsStableWithinSameDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let morning = DateComponents(calendar: cal, year: 2026, month: 10, day: 27, hour: 7).date!
        let night = DateComponents(calendar: cal, year: 2026, month: 10, day: 27, hour: 23).date!
        #expect(MenuBarOcclusionReminder.dayKey(for: morning, calendar: cal) == MenuBarOcclusionReminder.dayKey(for: night, calendar: cal))
        #expect(MenuBarOcclusionReminder.dayKey(for: morning, calendar: cal) == "2026-10-27")
    }

    @Test func dayKeyDiffersAcrossMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let day1 = DateComponents(calendar: cal, year: 2026, month: 10, day: 27, hour: 23, minute: 59).date!
        let day2 = DateComponents(calendar: cal, year: 2026, month: 10, day: 28, hour: 0, minute: 1).date!
        #expect(MenuBarOcclusionReminder.dayKey(for: day1, calendar: cal) != MenuBarOcclusionReminder.dayKey(for: day2, calendar: cal))
    }
}
