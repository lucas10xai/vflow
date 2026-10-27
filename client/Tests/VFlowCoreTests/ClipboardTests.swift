import Foundation
import Testing
@testable import VFlowCore

final class FakePasteboard: PasteboardStore {
    var items: [PasteboardItemSnapshot] = []
    var changeCount = 100
    var restoreCalls = 0

    func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(items: items) }
    func writeText(_ text: String, markerTypes: [String]) -> Int {
        changeCount += 1
        items = [PasteboardItemSnapshot([("public.utf8-plain-text", Data(text.utf8))] + markerTypes.map { ($0, Data()) })]
        return changeCount
    }
    func restore(_ s: PasteboardSnapshot) {
        restoreCalls += 1
        changeCount += 1
        items = s.items
    }
    /// Người dùng sao chép thứ khác.
    func userCopies(_ text: String) {
        changeCount += 1
        items = [PasteboardItemSnapshot([("public.utf8-plain-text", Data(text.utf8))])]
    }
}

@MainActor
@Suite struct ClipboardInserterTests {
    let original = [
        PasteboardItemSnapshot([("public.rtf", Data("{\\rtf1 x}".utf8)), ("public.utf8-plain-text", Data("x".utf8))]),
        PasteboardItemSnapshot([("public.png", Data([0x89, 0x50, 0x4E, 0x47]))]),
    ]

    @Test func pastesThenRestoresEveryTypeOfEveryItem() async {
        let pb = FakePasteboard()
        pb.items = original
        var seenDuringPaste: [PasteboardItemSnapshot] = []
        let ins = ClipboardInserter(pasteboard: pb, sendPaste: { seenDuringPaste = pb.items; return true }, wait: { _ in })
        #expect(await ins.insert("xin chào") == .pastedRestored)
        #expect(pb.items == original)
        let types = seenDuringPaste.first?.representations.map(\.type) ?? []
        #expect(types.contains("org.nspasteboard.ConcealedType"))
        #expect(types.contains("org.nspasteboard.TransientType"))
        #expect(seenDuringPaste.first?.representations.first?.data == Data("xin chào".utf8))
    }

    @Test func doesNotOverwriteWhenUserCopiedMeanwhile() async {
        let pb = FakePasteboard()
        pb.items = original
        let ins = ClipboardInserter(pasteboard: pb, sendPaste: { true }, wait: { _ in pb.userCopies("của người dùng") })
        #expect(await ins.insert("xin chào") == .pastedNotRestoredUserChanged)
        #expect(pb.restoreCalls == 0)
        #expect(pb.items.first?.representations.first?.data == Data("của người dùng".utf8))
    }

    @Test func pasteFailureLeavesTextOnClipboard() async {
        let pb = FakePasteboard()
        pb.items = original
        var delays: [Duration] = []
        let ins = ClipboardInserter(pasteboard: pb, restoreDelay: .milliseconds(350), pasteSettleDelay: .milliseconds(25),
                                    sendPaste: { false }, wait: { delays.append($0) })
        #expect(await ins.insert("xin chào") == .pasteFailedTextLeftOnClipboard)
        #expect(pb.items.first?.representations.first?.data == Data("xin chào".utf8))
        #expect(!delays.contains(.milliseconds(350)) && pb.restoreCalls == 0)
    }

    /// HỒI QUY đã xảy ra: bộ chèn từng có cổng "dò ô nhập qua Accessibility" — không dò được (Zalo,
    /// Chrome/Electron, AX chậm…) ⇒ KHÔNG dán, bắt người dùng bấm ⌘V. Nay không còn cổng nào: với mọi
    /// chữ không rỗng, `sendPaste` được gọi đúng một lần và kết quả là đã dán + khôi phục clipboard.
    @Test func alwaysSendsPasteExactlyOnceWithNoGate() async {
        let pb = FakePasteboard()
        pb.items = original
        var pasteCalls = 0
        let ins = ClipboardInserter(pasteboard: pb, sendPaste: { pasteCalls += 1; return true }, wait: { _ in })
        #expect(await ins.insert("xin chào") == .pastedRestored)
        #expect(pasteCalls == 1)
        #expect(pb.items == original)
    }

    /// Lý do DUY NHẤT để không dán: `sendPaste` trả false (thiếu quyền Trợ năng). Chữ ở lại clipboard,
    /// clipboard cũ không bị khôi phục đè lên.
    @Test func onlySendPasteFailureKeepsTextAndReportsPermissionProblem() async {
        let pb = FakePasteboard()
        pb.items = original
        let ins = ClipboardInserter(pasteboard: pb, sendPaste: { false }, wait: { _ in })
        let outcome = await ins.insert("xin chào")
        #expect(outcome == .pasteFailedTextLeftOnClipboard)
        #expect(pb.restoreCalls == 0)
        guard case .error(let m) = DictationDecision.overlay(after: outcome, planned: .done) else {
            Issue.record("phải báo lỗi thiếu quyền"); return
        }
        #expect(m.contains("Trợ năng"))
    }

    @Test func writesClipboardThenRunsBeforePasteThenSettlesThenPastes() async {
        let pb = FakePasteboard()
        var log: [String] = []
        let ins = ClipboardInserter(
            pasteboard: pb, restoreDelay: .milliseconds(350), pasteSettleDelay: .milliseconds(25),
            sendPaste: { log.append("paste:\(String(decoding: pb.items.first?.representations.first?.data ?? Data(), as: UTF8.self))"); return true },
            wait: { log.append("wait:\($0)") },
            beforePaste: { log.append("before") })
        _ = await ins.insert("abc")
        #expect(log == ["before", "wait:\(Duration.milliseconds(25))", "paste:abc", "wait:\(Duration.milliseconds(350))"],
                "app đích phải có thời gian nhận clipboard mới TRƯỚC ⌘V, và clipboard cũ chỉ được trả sau khi đã dán")
    }

    @Test func emptyTextNeverRunsBeforePasteOrPaste() async {
        let pb = FakePasteboard()
        var touched = false
        let ins = ClipboardInserter(pasteboard: pb, sendPaste: { touched = true; return true }, wait: { _ in touched = true },
                                    beforePaste: { touched = true })
        #expect(await ins.insert("") == .nothingToPaste)
        #expect(!touched)
    }

    @Test func emptyTextTouchesNothing() async {
        let pb = FakePasteboard()
        pb.items = original
        var pasted = false
        let ins = ClipboardInserter(pasteboard: pb, sendPaste: { pasted = true; return true }, wait: { _ in })
        #expect(await ins.insert("") == .nothingToPaste)
        #expect(pb.changeCount == 100 && !pasted)
    }

    @Test func emptyOriginalClipboardIsRestoredEmpty() async {
        let pb = FakePasteboard()
        let ins = ClipboardInserter(pasteboard: pb, sendPaste: { true }, wait: { _ in })
        #expect(await ins.insert("abc") == .pastedRestored)
        #expect(pb.items.isEmpty)
    }

    @Test func waitsBeforeRestoring() async {
        let pb = FakePasteboard()
        var delays: [Duration] = []
        let ins = ClipboardInserter(pasteboard: pb, restoreDelay: .milliseconds(350), pasteSettleDelay: .milliseconds(25),
                                    sendPaste: { true },
                                    wait: { delays.append($0); #expect(pb.restoreCalls == 0) })
        _ = await ins.insert("abc")
        #expect(delays == [.milliseconds(25), .milliseconds(350)])
    }
}
