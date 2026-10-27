import Foundation

/// Hệ thống thiết kế dùng chung (U1): màu nhấn thương hiệu, kiểm tương phản WCAG, và các hàm thuần
/// quyết định nội dung hiện ở Tổng quan/Cài đặt/Chào mừng — tách khỏi SwiftUI/AppKit để test được
/// không cần chạy trên máy thật. Lớp AppKit/SwiftUI (`client/Sources/VFlow/Theme.swift`) chỉ bọc
/// lại các hằng số/hàm này thành `Color`/`View`.
public enum BrandColor {
    /// Màu nhấn thương hiệu vflow, dạng hex không có dấu `#` (RRGGBB).
    public static let accentHex = "ED6300"
}

/// Kiểm tương phản WCAG 2.x (công thức luminance tương đối sRGB) — chọn chữ đen hoặc trắng để đạt
/// AA (≥4.5:1 cho chữ thường) trên một nền màu cho trước.
public enum ContrastText: Sendable {
    public enum Choice: Equatable, Sendable { case black, white }

    /// Ngưỡng AA cho chữ cỡ thường (WCAG 2.1, 1.4.3).
    public static let aaThreshold = 4.5

    /// `hex`: 6 ký tự RRGGBB, không phân biệt hoa/thường, có hoặc không dấu `#`. `nil` nếu không
    /// đọc được (không bao giờ âm thầm trả mặc định sai).
    public static func relativeLuminance(hex: String) -> Double? {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let value = UInt32(h, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return relativeLuminance(r: r, g: g, b: b)
    }

    public static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// Tỉ lệ tương phản giữa hai độ sáng tương đối (luôn ≥1, không quan tâm thứ tự tham số).
    public static func contrastRatio(_ l1: Double, _ l2: Double) -> Double {
        let lighter = max(l1, l2), darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Chọn chữ đen hoặc trắng để tương phản TỐT HƠN trên nền `backgroundHex`; `nil` nếu hex không
    /// đọc được.
    public static func textColor(onBackgroundHex backgroundHex: String) -> Choice? {
        guard let bgLuma = relativeLuminance(hex: backgroundHex) else { return nil }
        let contrastWithBlack = contrastRatio(bgLuma, 0)
        let contrastWithWhite = contrastRatio(bgLuma, 1)
        return contrastWithBlack >= contrastWithWhite ? .black : .white
    }

    /// `true` nếu chữ `choice` trên nền `backgroundHex` đạt ngưỡng AA (≥4.5:1).
    public static func meetsAA(choice: Choice, onBackgroundHex backgroundHex: String) -> Bool {
        guard let bgLuma = relativeLuminance(hex: backgroundHex) else { return false }
        let textLuma = choice == .black ? 0.0 : 1.0
        return contrastRatio(bgLuma, textLuma) >= aaThreshold
    }
}

/// Nhãn "Trong máy"/"Gửi chữ qua 9Router" cho mỗi chế độ — lấy TRỰC TIẾP từ
/// `DictationMode.sendsTextToCloud` (nguồn mô tả duy nhất, contract/engine-api.md), không viết lại
/// tay danh sách chế độ nào gửi đám mây.
public enum ModeCloudLabel {
    public static let local = "Trong máy"
    public static let cloud = "Gửi chữ qua 9Router"

    public static func text(_ mode: DictationMode) -> String {
        mode.sendsTextToCloud ? cloud : local
    }
}

/// Ánh xạ mã lý do (`ModelStatus.reason`, vd. `not_downloaded`) sang chữ thân thiện tiếng Việt cho
/// mục "Hệ thống" ở Tổng quan — mã lạ hiện NGUYÊN mã trong ngoặc, không bao giờ im lặng/bỏ qua.
public enum ModelReasonText {
    public static func friendly(_ code: String) -> String {
        switch code {
        case "not_downloaded": return "Chưa tải về"
        case "missing_token": return "Chưa có khoá truy cập"
        case "tunnel_down": return "Chưa kết nối"
        case "loading": return "Đang tải"
        case "loaded": return "Sẵn sàng"
        default: return "(\(code))"
        }
    }
}

/// Tiến trình cấp quyền "n/3" cho thẻ Quyền ở Tổng quan.
public enum PermissionsProgress {
    public static func counts(_ items: [PermissionItem]) -> (granted: Int, total: Int) {
        (items.filter(\.granted).count, items.count)
    }

    /// "Đã cấp n/tổng".
    public static func text(_ items: [PermissionItem]) -> String {
        let (granted, total) = counts(items)
        return "Đã cấp \(granted)/\(total)"
    }

    public static func allGranted(_ items: [PermissionItem]) -> Bool {
        !items.isEmpty && items.allSatisfy(\.granted)
    }
}

/// Quyết định có tự hiện cửa sổ/tờ Chào mừng lần đầu khi mở app hay không — thuần, test được
/// không cần UserDefaults thật. Luôn mở lại được thủ công từ menu Trợ giúp bất kể kết quả này.
public enum WelcomeDecision {
    /// Hiện khi CHƯA từng xem HOẶC chưa cấp đủ quyền (để dẫn dắt lại) — không chặn người dùng đã
    /// cấp đủ quyền VÀ đã từng xem.
    public static func shouldAutoShow(hasSeenWelcome: Bool, permissions: [PermissionItem]) -> Bool {
        !hasSeenWelcome || !PermissionsProgress.allGranted(permissions)
    }
}

/// Trạng thái thẻ lớn đầu trang Tổng quan — một nguồn quyết định duy nhất để thẻ, menu thanh trạng
/// thái và tooltip biểu tượng thanh menu không bao giờ nói khác nhau về "có vấn đề hay không".
public enum HeroStatus: Equatable, Sendable {
    case ready
    case startingEngine
    /// Còn `count` quyền (trong 3) chưa cấp.
    case missingPermissions(count: Int)
    case problem(message: String)
}

public enum HeroStatusDecision {
    /// Thứ tự ưu tiên: thiếu quyền (chặn mọi thứ) > engine bị chặn/lỗi > engine đang khởi động >
    /// lỗi gần nhất còn hiện > sẵn sàng.
    public static func decide(_ model: StatusModel) -> HeroStatus {
        let missing = model.missingPermissions.count
        if missing > 0 { return .missingPermissions(count: missing) }
        if model.engineBlocked { return .problem(message: model.engineSummary) }
        if !model.engineReady { return .startingEngine }
        if let e = model.lastError { return .problem(message: e) }
        return .ready
    }
}

/// Tổng hợp "Hôm nay" (số câu, số từ, thời gian nói) từ lịch sử — hàm thuần, không đọc tệp. Lịch
/// sử tắt ⇒ `.disabled` (không bao giờ hiện số 0 giả, dù không có mục nào trong ngày cũng là
/// `.data(0,0,0)` chứ không phải `.disabled`, để phân biệt rõ "chưa nói gì" với "đang tắt lịch sử").
public enum TodaySummary: Equatable, Sendable {
    case disabled
    case data(sentences: Int, words: Int, speakingMs: Int)
}

public enum TodayStats {
    public static func summarize(entries: [HistoryEntry], historyEnabled: Bool, now: Date,
                                  calendar: Calendar = .current) -> TodaySummary {
        guard historyEnabled else { return .disabled }
        let todayEntries = entries.filter { calendar.isDate($0.at, inSameDayAs: now) }
        let sentences = todayEntries.count
        let words = todayEntries.reduce(0) { $0 + wordCount($1.text) }
        let speakingMs = todayEntries.reduce(0) { $0 + ($1.audioMs ?? 0) }
        return .data(sentences: sentences, words: words, speakingMs: speakingMs)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// Viên "Hôm nay" trên thanh công cụ cửa sổ chính — số từ đã nói trong NGÀY HIỆN TẠI theo
/// `GET /v1/stats` (`days[date == today].words`). Chỉ hiện khi có số THẬT lớn hơn 0: chưa tải được
/// thống kê (`nil`), thống kê đang tắt, hôm nay chưa có dòng nào hoặc 0 từ ⇒ ẨN (`nil`) — không bao
/// giờ hiện "0 từ" giả cho trường hợp "không biết".
public enum TodayPill {
    public static func words(from stats: StatsSummary?) -> Int? {
        guard let stats, stats.enabled else { return nil }
        guard let day = stats.days.first(where: { $0.date == stats.today }), day.words > 0 else { return nil }
        return day.words
    }

    /// Chữ trên viên, số kiểu vi_VN (dấu chấm ngăn nghìn), vd. "Hôm nay: 1.234 từ". `nil` = ẩn viên.
    public static func text(from stats: StatsSummary?) -> String? {
        guard let n = words(from: stats) else { return nil }
        return "Hôm nay: \(VFlowNumberFormat.grouped(n)) từ"
    }
}

public extension BrandColor {
    /// Cam đậm dùng cho CHỮ cảnh báo/nhấn trên nền SÁNG (cam hệ thống #FF9500 chỉ đạt ~2,2:1 trên nền
    /// trắng, không đạt AA). Ở giao diện tối dùng cam hệ thống (đủ sáng trên nền tối) — xem
    /// `Theme.warningText`.
    static let warningTextOnLightHex = "A84F00"
}
