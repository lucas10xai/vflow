import Foundation
import Testing
@testable import VFlowCore

@Suite struct HistoryGroupingTests {
    static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func entry(_ at: Date, text: String = "x") -> HistoryEntry {
        HistoryEntry(at: at, mode: "normal", model: "m", textRaw: text, text: text)
    }

    @Test func emptyEntriesGivesNoGroups() {
        #expect(HistoryGrouping.grouped(entries: [], now: Date()).isEmpty)
    }

    @Test func todayIsLabeledHomNay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let groups = HistoryGrouping.grouped(entries: [Self.entry(now)], now: now, calendar: Self.utc)
        #expect(groups.count == 1)
        #expect(groups[0].label == "Hôm nay")
    }

    @Test func yesterdayIsLabeledHomQua() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = now.addingTimeInterval(-86400)
        let groups = HistoryGrouping.grouped(entries: [Self.entry(yesterday)], now: now, calendar: Self.utc)
        #expect(groups.count == 1)
        #expect(groups[0].label == "Hôm qua")
    }

    /// Phá nhánh: một mục vào 23:59:59 và một mục vào 00:00:01 NGÀY KẾ TIẾP (cùng múi giờ) phải
    /// rơi vào HAI nhóm khác nhau — nếu lỡ dùng khoảng cách 24h cố định thay vì "cùng ngày theo
    /// lịch", hai mục cách nhau 2 giây này sẽ bị gộp sai vào MỘT nhóm.
    @Test func midnightBoundarySplitsIntoTwoGroups() {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 1; c.hour = 23; c.minute = 59; c.second = 59
        let justBeforeMidnight = Self.utc.date(from: c)!
        c.day = 2; c.hour = 0; c.minute = 0; c.second = 1
        let justAfterMidnight = Self.utc.date(from: c)!
        let now = justAfterMidnight

        let groups = HistoryGrouping.grouped(entries: [Self.entry(justAfterMidnight), Self.entry(justBeforeMidnight)], now: now, calendar: Self.utc)
        #expect(groups.count == 2)
        #expect(groups[0].label == "Hôm nay")
        #expect(groups[1].label == "Hôm qua")
    }

    @Test func entriesOnSameDayStayInOneGroupPreservingOrder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Self.entry(now, text: "a")
        let b = Self.entry(now.addingTimeInterval(-60), text: "b")
        let groups = HistoryGrouping.grouped(entries: [a, b], now: now, calendar: Self.utc)
        #expect(groups.count == 1)
        #expect(groups[0].entries.map { $0.text } == ["a", "b"])
    }

    @Test func olderDayUsesFullDateNotRelativeLabel() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let longAgo = now.addingTimeInterval(-86400 * 10)
        let groups = HistoryGrouping.grouped(entries: [Self.entry(longAgo)], now: now, calendar: Self.utc)
        #expect(groups[0].label != "Hôm nay")
        #expect(groups[0].label != "Hôm qua")
        #expect(!groups[0].label.isEmpty)
    }

    @Test func groupOrderFollowsFirstAppearanceInInput() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = Self.entry(now, text: "today")
        let yesterday = Self.entry(now.addingTimeInterval(-86400), text: "yesterday")
        let groups = HistoryGrouping.grouped(entries: [today, yesterday], now: now, calendar: Self.utc)
        #expect(groups.map { $0.label } == ["Hôm nay", "Hôm qua"])
    }
}
