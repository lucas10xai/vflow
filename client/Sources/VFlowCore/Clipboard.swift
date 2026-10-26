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
    /// Không tổng hợp được ⌘V (thiếu quyền) ⇒ chữ để lại trên clipboard.
    case pasteFailedTextLeftOnClipboard
    /// Văn bản rỗng ⇒ không đụng clipboard.
    case nothingToPaste
}

/// Chèn chữ bằng clipboard + ⌘V rồi khôi phục clipboard cũ.
@MainActor
public struct ClipboardInserter {
    /// Kiểu đánh dấu để trình quản lý clipboard bỏ qua (nspasteboard.org).
    public static let markerTypes = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
    /// Thời gian chờ ứng dụng đích đọc clipboard sau ⌘V.
    public static let defaultRestoreDelay: Duration = .milliseconds(350)

    public let pasteboard: PasteboardStore
    public let restoreDelay: Duration
    /// Tổng hợp ⌘V; trả false nếu không gửi được.
    public let sendPaste: () -> Bool
    public let wait: (Duration) async -> Void

    public init(pasteboard: PasteboardStore,
                restoreDelay: Duration = defaultRestoreDelay,
                sendPaste: @escaping () -> Bool,
                wait: @escaping (Duration) async -> Void) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
        self.sendPaste = sendPaste
        self.wait = wait
    }

    public func insert(_ text: String) async -> PasteOutcome {
        guard !text.isEmpty else { return .nothingToPaste }
        let saved = pasteboard.snapshot()
        let ours = pasteboard.writeText(text, markerTypes: Self.markerTypes)
        guard sendPaste() else { return .pasteFailedTextLeftOnClipboard }
        await wait(restoreDelay)
        guard pasteboard.changeCount == ours else { return .pastedNotRestoredUserChanged }
        pasteboard.restore(saved)
        return .pastedRestored
    }
}
