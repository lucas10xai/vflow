import Foundation
import Testing
@testable import VFlowCore

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: TimeInterval = 0
    func now() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ d: TimeInterval) { lock.lock(); defer { lock.unlock() }; t += d }
}

private final class SelectionFakePasteboard: PasteboardStore {
    var items: [PasteboardItemSnapshot] = []
    var changeCount = 100
    var restoreCalls = 0

    func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(items: items) }
    func writeText(_ text: String, markerTypes: [String]) -> Int {
        changeCount += 1
        items = [PasteboardItemSnapshot([("public.utf8-plain-text", Data(text.utf8))])]
        return changeCount
    }
    func restore(_ s: PasteboardSnapshot) { restoreCalls += 1; changeCount += 1; items = s.items }
    func receiveCopiedText(_ text: String) {
        changeCount += 1
        items = [PasteboardItemSnapshot([("public.utf8-plain-text", Data(text.utf8))])]
    }
}

@MainActor
@Suite struct SelectionCaptureTests {
    @Test func axSelectionUsedDirectlyWithoutTouchingClipboard() async {
        let pb = SelectionFakePasteboard()
        pb.items = [PasteboardItemSnapshot([("public.utf8-plain-text", Data("clipboard cũ".utf8))])]
        var copyCalled = false
        let clock = FakeClock()
        let text = await SelectionCapture.capture(
            ax: { "đoạn đang chọn qua AX" }, pasteboard: pb,
            sendCopy: { copyCalled = true; return true },
            now: { clock.now() }, sleep: { _ in })
        #expect(text == "đoạn đang chọn qua AX")
        #expect(!copyCalled)
        #expect(pb.restoreCalls == 0)
    }

    @Test func emptyAXStringFallsBackToSyntheticCopy() async {
        let pb = SelectionFakePasteboard()
        var copyCalled = false
        let clock = FakeClock()
        _ = await SelectionCapture.capture(
            ax: { "" }, pasteboard: pb,
            sendCopy: { copyCalled = true; return true },
            now: { clock.now() }, sleep: { d in clock.advance(d.seconds) })
        #expect(copyCalled)
    }

    @Test func noAXDetectsClipboardChangeAndRestoresOriginal() async {
        let pb = SelectionFakePasteboard()
        pb.items = [PasteboardItemSnapshot([("public.utf8-plain-text", Data("clipboard cũ".utf8))])]
        let clock = FakeClock()
        var sleeps = 0
        let text = await SelectionCapture.capture(
            ax: { nil }, pasteboard: pb,
            sendCopy: { true },
            now: { clock.now() },
            sleep: { d in
                sleeps += 1
                clock.advance(d.seconds)
                if sleeps == 2 { pb.receiveCopiedText("đoạn đang chọn qua ⌘C") }
            })
        #expect(text == "đoạn đang chọn qua ⌘C")
        // Đã khôi phục clipboard nguyên gốc (không phải đoạn vừa ⌘C được).
        #expect(pb.items.first?.representations.first?.data == Data("clipboard cũ".utf8))
        #expect(pb.restoreCalls == 1)
    }

    /// ⌘C không đổi clipboard (không có gì đang chọn) ⇒ hết giờ, trả nil, KHÔNG đụng clipboard.
    @Test func noAXNoClipboardChangeTimesOutWithNil() async {
        let pb = SelectionFakePasteboard()
        pb.items = [PasteboardItemSnapshot([("public.utf8-plain-text", Data("clipboard cũ".utf8))])]
        let clock = FakeClock()
        let text = await SelectionCapture.capture(
            ax: { nil }, pasteboard: pb,
            sendCopy: { true },
            now: { clock.now() },
            sleep: { d in clock.advance(d.seconds) },
            pollInterval: .milliseconds(25), timeout: 0.1)
        #expect(text == nil)
        #expect(pb.restoreCalls == 0)
        #expect(pb.items.first?.representations.first?.data == Data("clipboard cũ".utf8))
    }

    @Test func synthethicCopyFailureReturnsNilImmediately() async {
        let pb = SelectionFakePasteboard()
        var slept = false
        let text = await SelectionCapture.capture(
            ax: { nil }, pasteboard: pb,
            sendCopy: { false },
            now: { 0 }, sleep: { _ in slept = true })
        #expect(text == nil)
        #expect(!slept)
    }

    /// Clipboard đổi giữa chừng do người dùng (không phải do ⌘C của chúng ta) vẫn được coi là đoạn
    /// chọn hợp lệ — không có cách phân biệt nguồn gốc đổi trong cửa sổ chờ ngắn này, và vẫn khôi
    /// phục đúng clipboard GỐC (trước khi bắt đầu Command Mode).
    @Test func clipboardChangedByUserDuringWaitIsTreatedAsSelectionAndOriginalIsStillRestored() async {
        let pb = SelectionFakePasteboard()
        pb.items = [PasteboardItemSnapshot([("public.utf8-plain-text", Data("clipboard gốc".utf8))])]
        let clock = FakeClock()
        let text = await SelectionCapture.capture(
            ax: { nil }, pasteboard: pb,
            sendCopy: { true },
            now: { clock.now() },
            sleep: { d in
                clock.advance(d.seconds)
                pb.receiveCopiedText("người dùng vừa sao chép thứ khác")
            })
        #expect(text == "người dùng vừa sao chép thứ khác")
        #expect(pb.items.first?.representations.first?.data == Data("clipboard gốc".utf8))
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let c = components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1e18
    }
}
