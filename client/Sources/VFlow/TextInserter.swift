import AppKit
import ApplicationServices
import VFlowCore

/// NSPasteboard thật, giữ mọi kiểu dữ liệu của mọi mục.
final class SystemPasteboard: PasteboardStore {
    private let pb = NSPasteboard.general

    var changeCount: Int { pb.changeCount }

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: (pb.pasteboardItems ?? []).map { item in
            PasteboardItemSnapshot(item.types.compactMap { t in item.data(forType: t).map { (t.rawValue, $0) } })
        })
    }

    func writeText(_ text: String, markerTypes: [String]) -> Int {
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for m in markerTypes { item.setData(Data(), forType: NSPasteboard.PasteboardType(m)) }
        pb.writeObjects([item])
        return pb.changeCount
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        pb.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { s -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for r in s.representations { item.setData(r.data, forType: NSPasteboard.PasteboardType(r.type)) }
            return item
        }
        pb.writeObjects(items)
    }
}

enum PasteKeystroke {
    /// Quyền gửi sự kiện tổng hợp (System Settings › Trợ năng).
    static func allowed() -> Bool { CGPreflightPostEventAccess() }

    /// ⌘V tổng hợp (mã phím ảo 9 = vị trí phím V trên bố cục ANSI).
    static func send() -> Bool {
        guard allowed() else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// ⌘C tổng hợp dùng để lấy đoạn đang chọn khi không có Accessibility (xem `SelectionCapture`).
enum CopyKeystroke {
    /// Mã phím ảo 8 = vị trí phím C trên bố cục ANSI.
    static func send() -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// Phím Return tổng hợp, gửi sau khi dán nếu `post.actions` chứa `"enter"` (xem `EnterAction`).
enum ReturnKeystroke {
    /// Mã phím ảo 36 = Return.
    static func send() -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false) else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// Dò xem phần tử đang được focus (qua Accessibility) có phải nơi có thể nhập chữ không — dùng để
/// tránh dán "vô mục tiêu" khi không có ô nhập nào đang focus (xem contract/engine-api.md, mục dán).
/// Cố ý CHỈ chặn các vai trò CHẮC CHẮN không phải ô nhập (nút, cửa sổ, menu, bảng…), không chặn vai
/// trò lạ/không đọc được — nhiều ứng dụng (Terminal, trình duyệt…) có AX không chuẩn nhưng vẫn nhận
/// ⌘V bình thường; chặn nhầm sẽ làm mất chữ đã đọc chính tả, tệ hơn là không chặn.
enum FocusedInputProbe {
    private static let definitelyNotTextInput: Set<String> = [
        "AXWindow", "AXApplication", "AXButton", "AXStaticText", "AXMenuBar", "AXMenuBarItem",
        "AXMenu", "AXMenuItem", "AXCheckBox", "AXRadioButton", "AXImage", "AXToolbar", "AXScrollBar",
        "AXTable", "AXOutline", "AXRow", "AXColumn", "AXSlider", "AXTabGroup", "AXDisclosureTriangle",
        "AXSplitGroup", "AXSplitter", "AXDockItem", "AXApplicationDockItem", "AXPopUpButton",
        "AXColorWell", "AXProgressIndicator", "AXUnknown",
    ]

    /// `false` chỉ khi hoàn toàn không có phần tử nào đang focus (AX thất bại) hoặc vai trò đọc
    /// được rõ ràng không phải ô nhập; đọc vai trò lỗi/lạ ⇒ coi là CÓ (an toàn, không chặn nhầm).
    static func hasFocusedTextInput() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }
        let axElement = focused as! AXUIElement
        var roleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return true }
        return !definitelyNotTextInput.contains(role)
    }
}

/// Đọc `kAXSelectedTextAttribute` của phần tử đang focus ở ứng dụng khác (Command Mode, bước a).
/// `nil` ⇒ không có AX hoặc không có đoạn chọn — gọi `CopyKeystroke` để thử tiếp (xem `SelectionCapture`).
enum AXSelection {
    static func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        let axElement = focused as! AXUIElement
        var selectedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
              let text = selectedRef as? String else { return nil }
        return text
    }
}
