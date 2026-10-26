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
        var waited = false
        let ins = ClipboardInserter(pasteboard: pb, sendPaste: { false }, wait: { _ in waited = true })
        #expect(await ins.insert("xin chào") == .pasteFailedTextLeftOnClipboard)
        #expect(pb.items.first?.representations.first?.data == Data("xin chào".utf8))
        #expect(!waited && pb.restoreCalls == 0)
    }

    @Test func noFocusedInputKeepsTextWithoutPastingOrRestoring() async {
        let pb = FakePasteboard()
        pb.items = original
        var pasted = false
        let ins = ClipboardInserter(pasteboard: pb, sendPaste: { pasted = true; return true }, wait: { _ in },
                                    hasFocusedTextInput: { false })
        #expect(await ins.insert("xin chào") == .noFocusedInputTextKeptOnClipboard)
        #expect(!pasted)
        #expect(pb.restoreCalls == 0)
        #expect(pb.items.first?.representations.first?.data == Data("xin chào".utf8))
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
        let ins = ClipboardInserter(pasteboard: pb, restoreDelay: .milliseconds(350), sendPaste: { true },
                                    wait: { delays.append($0); #expect(pb.restoreCalls == 0) })
        _ = await ins.insert("abc")
        #expect(delays == [.milliseconds(350)])
    }
}
