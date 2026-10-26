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
