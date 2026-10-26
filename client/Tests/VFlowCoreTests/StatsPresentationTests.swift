import Foundation
import Testing
@testable import VFlowCore

@Suite struct NumberFormatTests {
    @Test func groupsByThousandsWithDot() {
        #expect(VFlowNumberFormat.grouped(0) == "0")
        #expect(VFlowNumberFormat.grouped(5) == "5")
        #expect(VFlowNumberFormat.grouped(999) == "999")
        #expect(VFlowNumberFormat.grouped(1000) == "1.000")
        #expect(VFlowNumberFormat.grouped(12345) == "12.345")
        #expect(VFlowNumberFormat.grouped(1234567) == "1.234.567")
        #expect(VFlowNumberFormat.grouped(-1234) == "-1.234")
    }
}

@Suite struct StatsGreetingTests {
    @Test func thresholds() {
        #expect(StatsGreeting.text(totalWords: 0) == "Chưa có câu nào. Giữ ⌥ trái và nói thử.")
        #expect(StatsGreeting.text(totalWords: 1).contains("khởi đầu tốt"))
        #expect(StatsGreeting.text(totalWords: 99).contains("khởi đầu tốt"))
        #expect(StatsGreeting.text(totalWords: 100).contains("đang vào nhịp"))
        #expect(StatsGreeting.text(totalWords: 999).contains("đang vào nhịp"))
        #expect(StatsGreeting.text(totalWords: 1000).contains("thói quen đang hình thành"))
        #expect(StatsGreeting.text(totalWords: 9999).contains("thói quen đang hình thành"))
        #expect(StatsGreeting.text(totalWords: 10000).contains("công cụ hằng ngày"))
        // Số lớn vẫn định dạng đúng kiểu Việt trong câu chào (mục "số lớn" của acceptance).
        #expect(StatsGreeting.text(totalWords: 123456).contains("123.456"))
        #expect(StatsGreeting.text(totalWords: 1234).contains("1.234"))
    }
}

@Suite struct AvgWpmTextTests {
    @Test func nilIsDash() {
        #expect(AvgWpmText.text(nil) == "—")
        #expect(AvgWpmText.text(95) == "95")
        #expect(AvgWpmText.text(1200) == "1.200")
    }
}

@Suite struct ActivityIntensityTests {
    @Test func zeroWordsIsLevelZero() {
        #expect(ActivityIntensity.level(words: 0, activeWords: [10, 20, 30]) == 0)
    }

    @Test func allEqualIsHighestLevel() {
        #expect(ActivityIntensity.level(words: 50, activeWords: [50, 50, 50]) == 4)
    }

    @Test func singleActiveDayIsHighestLevel() {
        #expect(ActivityIntensity.level(words: 7, activeWords: [7]) == 4)
    }

    @Test func quartileBucketsAreMonotonic() {
        let active = Array(1...100) // 1..100, phân vị rõ
        var lastLevel = 0
        for w in [1, 25, 26, 50, 51, 75, 76, 100] {
            let l = ActivityIntensity.level(words: w, activeWords: active)
            #expect(l >= lastLevel, "mức phải không giảm khi số từ tăng (w=\(w))")
            lastLevel = l
        }
        #expect(ActivityIntensity.level(words: 1, activeWords: active) == 1)
        #expect(ActivityIntensity.level(words: 100, activeWords: active) == 4)
    }
}

@Suite struct ActivityHeatmapTests {
    /// 16 tuần kết thúc ở tuần chứa `today`, đủ 7×16 ô — không có ô nào vượt biên.
    @Test func gridDimensionsMatchWeeksAndSevenWeekdays() {
        let grid = ActivityHeatmap.grid(days: [], today: "2026-10-27", weeks: 16)
        #expect(grid.count == 7)
        for row in grid { #expect(row.count == 16) }
    }

    @Test func todayLandsInRightmostColumnWithCorrectWeekday() {
        // 2026-10-27 là thứ Ba (kiểm bằng lịch Gregorian) ⇒ hàng weekday=1 (0=Thứ Hai).
        let days = [DayStat(date: "2026-10-27", words: 10, count: 1, audioMs: 1000)]
        let grid = ActivityHeatmap.grid(days: days, today: "2026-10-27", weeks: 16)
        var found: (weekday: Int, weekIndex: Int)?
        for weekday in 0..<7 {
            for weekIndex in 0..<16 {
                if grid[weekday][weekIndex]?.date == "2026-10-27" { found = (weekday, weekIndex) }
            }
        }
        let f = try! #require(found)
        #expect(f.weekIndex == 15, "tuần hiện tại phải ở cột phải nhất")
        #expect(grid[f.weekday][f.weekIndex]?.isToday == true)
    }

    @Test func futureDaysAreNotDrawn() {
        // Chỉ cung cấp hôm nay, không cung cấp các ngày tương lai trong tuần hiện tại (đúng hành vi
        // engine) ⇒ các ô đó phải là nil, không phải level 0 "có dữ liệu".
        let days = [DayStat(date: "2026-10-27", words: 5, count: 1, audioMs: 500)] // thứ Ba
        let grid = ActivityHeatmap.grid(days: days, today: "2026-10-27", weeks: 16)
        // Thứ Tư/Năm/Sáu/Bảy/CN của tuần hiện tại (sau hôm nay) không có trong days[] ⇒ không vẽ.
        for weekday in 2..<7 {
            #expect(grid[weekday][15] == nil, "ngày tương lai (weekday=\(weekday)) không được vẽ")
        }
    }

    @Test func monthBoundaryWeekSpansTwoMonths() {
        // Tuần 26/10–01/11/2026 (Thứ Hai 26/10 → Chủ nhật 01/11) vượt biên tháng.
        let cal = ActivityHeatmap.utcGregorian
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
        let days = (0..<7).map { offset -> DayStat in
            let date = cal.date(byAdding: .day, value: offset, to: monday)!
            return DayStat(date: f.string(from: date), words: offset == 6 ? 0 : 10, count: offset == 6 ? 0 : 1, audioMs: 0)
        }
        let grid = ActivityHeatmap.grid(days: days, today: "2026-11-01", weeks: 16)
        // 26/10 (Thứ Hai) và 01/11 (Chủ nhật) phải cùng cột (tuần hiện tại, cột 15).
        let mon = grid[0][15]
        let sun = grid[6][15]
        #expect(mon?.date == "2026-10-26")
        #expect(sun?.date == "2026-11-01")
    }

    @Test func yearBoundaryWeekSpansTwoYears() {
        // Thứ Hai 29/12/2025 → Chủ nhật 04/01/2026 — vượt biên năm, vẫn phải cùng cột.
        let days = [
            DayStat(date: "2025-12-29", words: 3, count: 1, audioMs: 0),
            DayStat(date: "2026-01-04", words: 4, count: 1, audioMs: 0),
        ]
        let grid = ActivityHeatmap.grid(days: days, today: "2026-01-04", weeks: 16)
        var col29: Int?; var col04: Int?
        for weekIndex in 0..<16 {
            if grid[0][weekIndex]?.date == "2025-12-29" { col29 = weekIndex }
            if grid[6][weekIndex]?.date == "2026-01-04" { col04 = weekIndex }
        }
        #expect(col29 != nil && col29 == col04, "hai đầu tuần vượt năm phải cùng cột")
        #expect(col04 == 15)
    }

    @Test func partialFirstWeekStillAnchorsTodayToRightmostColumn() {
        // "since" chỉ có 3 ngày gần đây (tuần đầu của cửa sổ thiếu ngày) — không ảnh hưởng việc hôm
        // nay vẫn neo đúng cột phải nhất.
        let days = [
            DayStat(date: "2026-10-25", words: 1, count: 1, audioMs: 0),
            DayStat(date: "2026-10-26", words: 2, count: 1, audioMs: 0),
            DayStat(date: "2026-10-27", words: 3, count: 1, audioMs: 0),
        ]
        let grid = ActivityHeatmap.grid(days: days, today: "2026-10-27", weeks: 16)
        var found: Int?
        for weekday in 0..<7 where grid[weekday][15]?.date == "2026-10-27" { found = weekday }
        #expect(found != nil)
    }

    @Test func emptyDaysProducesAllNilGrid() {
        let grid = ActivityHeatmap.grid(days: [], today: "2026-10-27", weeks: 16)
        for row in grid { for cell in row { #expect(cell == nil) } }
    }

    @Test func cellLabelFormatsVietnameseDateWordsAndSentences() {
        let days = [DayStat(date: "2026-10-27", words: 30, count: 3, audioMs: 0)]
        let grid = ActivityHeatmap.grid(days: days, today: "2026-10-27", weeks: 16)
        var cell: HeatmapCell?
        for weekday in 0..<7 where grid[weekday][15] != nil { cell = grid[weekday][15] }
        #expect(cell?.label == "27/10/2026: 30 từ · 3 câu")
    }
}
