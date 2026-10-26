import Foundation

/// Logic thuần cho tab "Thống kê" (V2): định dạng số kiểu Việt, lời chào theo ngưỡng, và lưới hoạt
/// động 16 tuần — tách khỏi SwiftUI để test được không cần chạy app thật (xem
/// `client/Tests/VFlowCoreTests/StatsPresentationTests.swift`).

/// Định dạng số nguyên kiểu vi_VN (dấu chấm ngăn nghìn) — KHÔNG dựa vào `Locale`/`NumberFormatter`
/// của hệ thống (dữ liệu ICU có thể khác nhau giữa máy) để kết quả xác định được, test được.
public enum VFlowNumberFormat {
    public static func grouped(_ n: Int) -> String {
        let negative = n < 0
        var digits = Array(String(abs(n)))
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        groups.insert(String(digits), at: 0)
        return (negative ? "-" : "") + groups.joined(separator: ".")
    }
}

/// Lời chào lớn đầu tab Thống kê — theo NGƯỠNG tổng số từ (toàn thời gian), không theo cửa sổ tuần.
public enum StatsGreeting {
    public static func text(totalWords: Int) -> String {
        switch totalWords {
        case 0:
            return "Chưa có câu nào. Giữ ⌥ trái và nói thử."
        case 1...99:
            return "Bạn đã nói \(VFlowNumberFormat.grouped(totalWords)) từ — đây là khởi đầu tốt."
        case 100...999:
            return "Bạn đã nói \(VFlowNumberFormat.grouped(totalWords)) từ — đang vào nhịp."
        case 1000...9999:
            return "Bạn đã nói \(VFlowNumberFormat.grouped(totalWords)) từ — thói quen đang hình thành."
        default:
            return "Bạn đã nói \(VFlowNumberFormat.grouped(totalWords)) từ — vflow đã thành công cụ hằng ngày."
        }
    }
}

/// Chữ hiện ở thẻ "WPM TRUNG BÌNH" — `nil` (chưa đủ ≥60s audio, xem contract) ⇒ "—" kèm gợi ý, KHÔNG
/// BAO GIỜ hiện số 0 giả.
public enum AvgWpmText {
    public static let placeholder = "—"
    public static let hint = "Cần ít nhất 1 phút giọng nói"

    public static func text(_ wpm: Int?) -> String {
        guard let wpm else { return placeholder }
        return VFlowNumberFormat.grouped(wpm)
    }
}

/// Một ô trong lưới hoạt động 16 tuần.
public struct HeatmapCell: Equatable, Sendable {
    /// 0 = cột trái nhất (xa nhất trong quá khứ) … `weeks - 1` = cột phải nhất (tuần hiện tại).
    public var weekIndex: Int
    /// 0 = Thứ Hai … 6 = Chủ nhật.
    public var weekday: Int
    public var date: String
    public var words: Int
    public var sentences: Int
    /// 0 = không nói gì, 1–4 = mức cường độ tăng dần (xem `ActivityIntensity`).
    public var level: Int
    public var isToday: Bool

    public init(weekIndex: Int, weekday: Int, date: String, words: Int, sentences: Int, level: Int, isToday: Bool) {
        self.weekIndex = weekIndex
        self.weekday = weekday
        self.date = date
        self.words = words
        self.sentences = sentences
        self.level = level
        self.isToday = isToday
    }

    /// "27/10/2026: 30 từ · 3 câu" — dùng cho tooltip VÀ nhãn VoiceOver.
    public var label: String {
        let parts = date.split(separator: "-")
        let ddmmyyyy = parts.count == 3 ? "\(parts[2])/\(parts[1])/\(parts[0])" : date
        return "\(ddmmyyyy): \(VFlowNumberFormat.grouped(words)) từ · \(VFlowNumberFormat.grouped(sentences)) câu"
    }
}

/// Mức cường độ 1–4 theo PHÂN VỊ của các ngày CÓ nói (`words > 0`) trong cùng cửa sổ — khi mọi ngày
/// hoạt động có số từ bằng nhau (kể cả chỉ một ngày duy nhất) thì không có phân vị có nghĩa, trả về
/// mức CAO NHẤT cho tất cả (theo yêu cầu, tránh suy biến chia 0).
public enum ActivityIntensity {
    public static func level(words: Int, activeWords: [Int]) -> Int {
        guard words > 0 else { return 0 }
        guard let minV = activeWords.min(), let maxV = activeWords.max(), minV != maxV else { return 4 }
        let sorted = activeWords.sorted()
        func quantile(_ p: Double) -> Double {
            guard sorted.count > 1 else { return Double(sorted[0]) }
            let idx = p * Double(sorted.count - 1)
            let lo = Int(idx.rounded(.down)), hi = Int(idx.rounded(.up))
            let frac = idx - Double(lo)
            return Double(sorted[lo]) + (Double(sorted[hi]) - Double(sorted[lo])) * frac
        }
        let w = Double(words)
        if w <= quantile(0.25) { return 1 }
        if w <= quantile(0.5) { return 2 }
        if w <= quantile(0.75) { return 3 }
        return 4
    }
}

/// Dựng lưới 7×`weeks` (thứ × tuần, tuần bắt đầu Thứ Hai) từ `days[]` (`GET /v1/stats`) — ô vắng
/// mặt (không có trong `days[]`) LUÔN là ngày tương lai (hợp đồng đảm bảo `days[]` đủ mọi ngày QUA
/// khứ/hôm nay trong cửa sổ, chỉ bỏ ngày tương lai) ⇒ không vẽ, trả `nil` ở vị trí đó.
public enum ActivityHeatmap {
    /// `grid[weekday][weekIndex]`, `weekday` 0…6 (Thứ Hai…Chủ nhật), `weekIndex` 0…`weeks-1`.
    public static func grid(days: [DayStat], today: String, weeks: Int,
                            calendar: Calendar = ActivityHeatmap.utcGregorian) -> [[HeatmapCell?]] {
        guard weeks > 0, let todayDate = parseDate(today, calendar: calendar) else {
            return Array(repeating: Array(repeating: nil, count: max(weeks, 0)), count: 7)
        }
        let todayMonday = mondayOfWeek(containing: todayDate, calendar: calendar)
        let activeWords = days.filter { $0.words > 0 }.map(\.words)
        var result: [[HeatmapCell?]] = Array(repeating: Array(repeating: nil, count: weeks), count: 7)
        for day in days {
            guard let d = parseDate(day.date, calendar: calendar) else { continue }
            let weekday = mondayStartWeekday(of: d, calendar: calendar)
            let monday = mondayOfWeek(containing: d, calendar: calendar)
            // Số ngày giữa hai Thứ Hai (luôn chia hết cho 7) — ổn định qua ranh giới tháng/năm, không
            // dùng `weekOfYear` của lịch (lệch ở các tuần đầu/cuối năm).
            guard let daysBetween = calendar.dateComponents([.day], from: monday, to: todayMonday).day else { continue }
            let offsetFromCurrent = daysBetween / 7
            let weekIndex = weeks - 1 - offsetFromCurrent
            guard weekIndex >= 0, weekIndex < weeks else { continue }
            let level = ActivityIntensity.level(words: day.words, activeWords: activeWords)
            result[weekday][weekIndex] = HeatmapCell(weekIndex: weekIndex, weekday: weekday, date: day.date,
                                                      words: day.words, sentences: day.count, level: level,
                                                      isToday: day.date == today)
        }
        return result
    }

    /// Nhãn hàng (Thứ Hai → Chủ nhật) — view hiện đủ hoặc chỉ T2/T4/T6/CN khi chật.
    public static let weekdayLabelsFull = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
    public static let weekdayLabelsSparse = ["T2", nil, "T4", nil, "T6", nil, "CN"]

    public static var utcGregorian: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    static func parseDate(_ s: String, calendar: Calendar) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }

    /// 0 = Thứ Hai … 6 = Chủ nhật, từ `Calendar.component(.weekday)` (1=Chủ nhật…7=Thứ Bảy).
    static func mondayStartWeekday(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func mondayOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let offset = mondayStartWeekday(of: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: -offset, to: date) ?? date
    }
}
