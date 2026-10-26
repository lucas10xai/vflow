import Foundation

/// Gom các mục lịch sử theo ngày ("Hôm nay"/"Hôm qua"/ngày đầy đủ) cho Tab Lịch sử (U2 mục B) —
/// hàm thuần, test được không cần UserDefaults/tệp/UI thật.
public enum HistoryGrouping {
    public struct DayGroup: Equatable, Sendable {
        public var label: String
        public var entries: [HistoryEntry]
        public init(label: String, entries: [HistoryEntry]) {
            self.label = label
            self.entries = entries
        }
    }

    /// Nhóm `entries` theo NGÀY THEO ĐỊA PHƯƠNG (`calendar`) — giữ nguyên thứ tự tương đối trong
    /// mỗi nhóm (gọi SAU KHI đã sắp xếp, vd. `HistoryStore.list()` trả mới nhất trước) và thứ tự
    /// nhóm theo lần xuất hiện ĐẦU TIÊN của mỗi ngày trong `entries` (không tự sắp lại ngày — nếu
    /// đầu vào đã mới nhất-trước thì nhóm "Hôm nay" luôn ra trước "Hôm qua").
    public static func grouped(entries: [HistoryEntry], now: Date, calendar: Calendar = .current,
                                locale: Locale = Locale(identifier: "vi_VN")) -> [DayGroup] {
        var order: [Date] = []
        var byDay: [Date: [HistoryEntry]] = [:]
        for e in entries {
            let day = calendar.startOfDay(for: e.at)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(e)
        }
        return order.map { day in
            DayGroup(label: label(for: day, now: now, calendar: calendar, locale: locale), entries: byDay[day] ?? [])
        }
    }

    static func label(for day: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let today = calendar.startOfDay(for: now)
        if calendar.isDate(day, inSameDayAs: today) { return "Hôm nay" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Hôm qua"
        }
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .long
        return f.string(from: day)
    }
}
