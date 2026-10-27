import Foundation

/// Một mục clipboard: mọi kiểu dữ liệu (UTI ⇒ byte) đúng thứ tự.
public struct PasteboardItemSnapshot: Equatable, Sendable {
    public var representations: [(type: String, data: Data)]
    public init(_ representations: [(type: String, data: Data)]) { self.representations = representations }
    public static func == (a: Self, b: Self) -> Bool {
        a.representations.count == b.representations.count
            && zip(a.representations, b.representations).allSatisfy { $0.type == $1.type && $0.data == $1.data }
    }
}

public struct PasteboardSnapshot: Equatable, Sendable {
    public var items: [PasteboardItemSnapshot]
    public init(items: [PasteboardItemSnapshot]) { self.items = items }
}

/// Trừu tượng NSPasteboard để test logic khôi phục.
public protocol PasteboardStore: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    /// Xoá và ghi chữ (kèm các kiểu đánh dấu); trả `changeCount` mới.
    func writeText(_ text: String, markerTypes: [String]) -> Int
    /// Xoá và ghi lại nguyên các mục cũ.
    func restore(_ snapshot: PasteboardSnapshot)
}

public enum PasteOutcome: Equatable, Sendable {
    /// Đã dán và khôi phục clipboard cũ.
    case pastedRestored
    /// Đã dán; người dùng sao chép thứ khác trong lúc chờ ⇒ không đè.
    case pastedNotRestoredUserChanged
    /// Không tổng hợp được ⌘V (thiếu quyền Trợ năng) ⇒ chữ để lại trên clipboard. ĐÂY LÀ LÝ DO DUY NHẤT
    /// để không dán: việc "không dò được ô nhập" (Accessibility của nhiều app không chuẩn) KHÔNG BAO GIỜ
    /// được dùng làm lý do bỏ dán — đó từng là hồi quy khiến người dùng phải tự bấm ⌘V.
    case pasteFailedTextLeftOnClipboard
    /// Văn bản rỗng ⇒ không đụng clipboard.
    case nothingToPaste
}

/// Chọn app cần kích hoạt lại TRƯỚC khi dán (thuần, test được). Chỉ "đòi lại" focus khi chính vflow
/// (hoặc không app nào) đang ở trước — khi đó ⌘V chắc chắn rơi vào cửa sổ vflow thay vì app người dùng
/// đang đọc chính tả vào. Nếu người dùng chủ động chuyển sang một app KHÁC trong lúc dịch thì tôn trọng
/// (dán vào đó), không giật focus về lại.
public enum PasteTargetPolicy {
    public static func bundleIdToReactivate(target: String?, frontmost: String?, ownBundleId: String?) -> String? {
        guard let target, !target.isEmpty, target != ownBundleId else { return nil }
        guard frontmost != target else { return nil }
        if frontmost == nil { return target }
        return frontmost == ownBundleId ? target : nil
    }
}

/// Chèn chữ bằng clipboard + ⌘V rồi khôi phục clipboard cũ. MẶC ĐỊNH LUÔN DÁN: chỉ có hai kết quả thật
/// — dán được (khôi phục clipboard cũ) hoặc không gửi được ⌘V vì thiếu quyền (giữ chữ trên clipboard).
@MainActor
public struct ClipboardInserter {
    /// Kiểu đánh dấu để trình quản lý clipboard bỏ qua (nspasteboard.org).
    public static let markerTypes = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
    /// Thời gian chờ ứng dụng đích đọc clipboard sau ⌘V.
    public static let defaultRestoreDelay: Duration = .milliseconds(350)
    /// Chờ ngắn giữa lúc ghi clipboard và lúc gửi ⌘V để pasteboard server kịp công bố nội dung mới cho app
    /// đích (Chrome/Electron đôi khi dán nội dung cũ nếu ⌘V tới sát lúc ghi). 25 ms: không nhận ra được.
    public static let defaultPasteSettleDelay: Duration = .milliseconds(25)

    public let pasteboard: PasteboardStore
    public let restoreDelay: Duration
    public let pasteSettleDelay: Duration
    /// Tổng hợp ⌘V; trả false nếu không gửi được.
    public let sendPaste: () -> Bool
    public let wait: (Duration) async -> Void
    /// Chạy sau khi đã ghi clipboard, trước ⌘V — chỗ để đưa app đích trở lại phía trước nếu vflow đang
    /// chiếm focus (xem `PasteTargetPolicy`). Mặc định không làm gì.
    public let beforePaste: () async -> Void

    public init(pasteboard: PasteboardStore,
                restoreDelay: Duration = defaultRestoreDelay,
                pasteSettleDelay: Duration = defaultPasteSettleDelay,
                sendPaste: @escaping () -> Bool,
                wait: @escaping (Duration) async -> Void,
                beforePaste: @escaping () async -> Void = {}) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
        self.pasteSettleDelay = pasteSettleDelay
        self.sendPaste = sendPaste
        self.wait = wait
        self.beforePaste = beforePaste
    }

    public func insert(_ text: String) async -> PasteOutcome {
        guard !text.isEmpty else { return .nothingToPaste }
        let saved = pasteboard.snapshot()
        let ours = pasteboard.writeText(text, markerTypes: Self.markerTypes)
        await beforePaste()
        await wait(pasteSettleDelay)
        guard sendPaste() else { return .pasteFailedTextLeftOnClipboard }
        await wait(restoreDelay)
        guard pasteboard.changeCount == ours else { return .pastedNotRestoredUserChanged }
        pasteboard.restore(saved)
        return .pastedRestored
    }
}
