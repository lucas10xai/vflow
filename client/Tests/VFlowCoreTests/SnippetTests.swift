import Foundation
import Testing
@testable import VFlowCore

private extension Result {
    var isSuccess: Bool { if case .success = self { return true }; return false }
}

/// Hộp đơn giản để gom trạng thái từ closure `@Sendable` trong test (xem `DictionaryTests.swift`).
private final class TestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: T) { lock.lock(); defer { lock.unlock() }; value = v }
}

@Suite struct SnippetValidationTests {
    @Test func validEntryPasses() {
        let e = SnippetEntry(trigger: "link lịch hẹn", text: "https://cal.example/x")
        #expect(SnippetValidation.validate([e]).isSuccess)
    }

    @Test func emptyTriggerIsRejected() {
        let e = SnippetEntry(trigger: "", text: "x")
        guard case .failure(let err) = SnippetValidation.validate([e]) else { Issue.record("phải lỗi"); return }
        #expect(err.message.contains("trigger"))
    }

    @Test func emptyTextIsRejected() {
        let e = SnippetEntry(trigger: "x", text: "")
        guard case .failure = SnippetValidation.validate([e]) else { Issue.record("text rỗng phải lỗi"); return }
    }

    @Test func triggerOver60CharsIsRejected() {
        let e = SnippetEntry(trigger: String(repeating: "a", count: 61), text: "x")
        guard case .failure = SnippetValidation.validate([e]) else { Issue.record("trigger > 60 ký tự phải lỗi"); return }
    }

    @Test func textOver5000CharsIsRejected() {
        let e = SnippetEntry(trigger: "x", text: String(repeating: "a", count: 5001))
        guard case .failure = SnippetValidation.validate([e]) else { Issue.record("text > 5000 ký tự phải lỗi"); return }
    }

    /// Trùng sau khi bỏ dấu THANH + hoa→thường — giống luật engine (`normalizeMatch`/`fold`, chỉ bỏ
    /// dấu thanh huyền/sắc/hỏi/ngã/nặng, GIỮ nguyên â/ă/ê/ô/ơ/ư/đ — nên dùng từ không có các chữ đó).
    @Test func duplicateAfterFoldingDiacriticsAndCaseIsRejected() {
        let a = SnippetEntry(trigger: "Chào Bạn", text: "x") // à = a+huyền, ạ = a+nặng ⇒ bỏ dấu thanh
        let b = SnippetEntry(trigger: "chao ban", text: "y")
        guard case .failure(let err) = SnippetValidation.validate([a, b]) else { Issue.record("phải lỗi trùng sau khi gấp dấu"); return }
        #expect(err.message.contains("trùng"))
    }

    @Test func duplicateAfterPunctuationDifferenceIsRejected() {
        let a = SnippetEntry(trigger: "link, lịch hẹn!", text: "x")
        let b = SnippetEntry(trigger: "link lịch hẹn", text: "y")
        guard case .failure = SnippetValidation.validate([a, b]) else { Issue.record("phải lỗi trùng sau khi bỏ dấu câu"); return }
    }

    @Test func distinctTriggersAreAllowed() {
        let a = SnippetEntry(trigger: "link lịch hẹn", text: "x")
        let b = SnippetEntry(trigger: "địa chỉ văn phòng", text: "y")
        #expect(SnippetValidation.validate([a, b]).isSuccess)
    }

    @Test func tooManyEntriesIsRejected() {
        let entries = (0..<501).map { SnippetEntry(trigger: "trigger \($0)", text: "x") }
        guard case .failure = SnippetValidation.validate(entries) else { Issue.record("quá 500 mục phải lỗi"); return }
    }

    @Test func negativeUsesIsRejected() {
        let e = SnippetEntry(trigger: "x", text: "y", uses: -1)
        guard case .failure = SnippetValidation.validate([e]) else { Issue.record("uses âm phải lỗi"); return }
    }
}

@Suite struct SnippetPlannerTests {
    @Test func addAppendsEntry() {
        let current = [SnippetEntry(trigger: "a", text: "1")]
        guard case .success(let next) = SnippetPlanner.apply(.add(SnippetEntry(trigger: "b", text: "2")), to: current) else {
            Issue.record("phải thành công"); return
        }
        #expect(next.count == 2)
    }

    @Test func addDuplicateTriggerIsRejected() {
        let current = [SnippetEntry(trigger: "link lịch hẹn", text: "1")]
        let result = SnippetPlanner.apply(.add(SnippetEntry(trigger: "Link Lịch Hẹn", text: "2")), to: current)
        guard case .failure = result else { Issue.record("phải lỗi trùng"); return }
    }

    @Test func updateRenamesAndKeepsPosition() {
        let current = [SnippetEntry(trigger: "a", text: "1"), SnippetEntry(trigger: "b", text: "2")]
        guard case .success(let next) = SnippetPlanner.apply(.update(originalTrigger: "a", entry: SnippetEntry(trigger: "a2", text: "1b")), to: current) else {
            Issue.record("phải thành công"); return
        }
        #expect(next[0].trigger == "a2" && next[0].text == "1b")
    }

    @Test func updatingMissingTriggerFails() {
        let current = [SnippetEntry(trigger: "a", text: "1")]
        let result = SnippetPlanner.apply(.update(originalTrigger: "ghost", entry: SnippetEntry(trigger: "x", text: "y")), to: current)
        guard case .failure = result else { Issue.record("phải lỗi không còn thấy mục"); return }
    }

    @Test func removeDropsEntry() {
        let current = [SnippetEntry(trigger: "a", text: "1"), SnippetEntry(trigger: "b", text: "2")]
        guard case .success(let next) = SnippetPlanner.apply(.remove(trigger: "a"), to: current) else { Issue.record("phải thành công"); return }
        #expect(next.count == 1 && next[0].trigger == "b")
    }

    @Test func removingMissingTriggerFails() {
        let result = SnippetPlanner.apply(.remove(trigger: "ghost"), to: [])
        guard case .failure = result else { Issue.record("phải lỗi không còn thấy mục"); return }
    }
}

@Suite struct SnippetOrchestrationTests {
    @Test func readModifyWriteSendsFreshlyReadListToPut() async {
        let putArg = TestBox<[SnippetEntry]?>(nil)
        let result = await SnippetOrchestration.applyChange(
            .add(SnippetEntry(trigger: "b", text: "2")),
            get: { .success([SnippetEntry(trigger: "a", text: "1")]) },
            put: { entries in putArg.set(entries); return .success(entries) })
        #expect(result.isSuccess)
        #expect(putArg.get()?.count == 2)
    }

    @Test func getFailureShortCircuitsBeforePut() async {
        let putCalled = TestBox(false)
        let result = await SnippetOrchestration.applyChange(
            .add(SnippetEntry(trigger: "a", text: "1")),
            get: { .failure(.engineNotRunning) },
            put: { _ in putCalled.set(true); return .success([]) })
        guard case .failure(.engineNotRunning) = result else { Issue.record("phải truyền lỗi get"); return }
        #expect(!putCalled.get())
    }

    @Test func clientValidationFailureNeverCallsPut() async {
        let putCalled = TestBox(false)
        let result = await SnippetOrchestration.applyChange(
            .add(SnippetEntry(trigger: "link lịch hẹn", text: "1")),
            get: { .success([SnippetEntry(trigger: "Link Lịch Hẹn", text: "2")]) },
            put: { _ in putCalled.set(true); return .success([]) })
        guard case .failure(.snippetInvalid) = result else { Issue.record("phải lỗi snippetInvalid"); return }
        #expect(!putCalled.get())
    }
}

@Suite struct SnippetRequestTests {
    @Test func putRequestEncodesEntriesMatchingEngineSchema() {
        let entries = [SnippetEntry(trigger: "a", text: "b", uses: 3, lastUsed: "2026-01-01T00:00:00Z")]
        let req = EngineAPI.snippetsPutRequest(port: 7611, token: "t", entries: entries)
        let obj = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let rawEntries = obj["entries"] as! [[String: Any]]
        #expect(rawEntries[0]["trigger"] as? String == "a")
        #expect(rawEntries[0]["uses"] as? Int == 3)
        #expect(rawEntries[0]["last_used"] as? String == "2026-01-01T00:00:00Z")
    }

    @Test func listParsingRoundTrips() {
        let body = Data("{\"entries\":[{\"trigger\":\"a\",\"text\":\"b\",\"uses\":1,\"last_used\":null}]}".utf8)
        guard case .success(let entries) = EngineAPI.parseSnippetList(status: 200, data: body) else { Issue.record("phải đọc được"); return }
        #expect(entries == [SnippetEntry(trigger: "a", text: "b", uses: 1, lastUsed: nil)])
    }

    @Test func listParsingSurfacesEngineErrorNotSwallowed() {
        let body = Data("{\"error\":{\"code\":\"bad_request\",\"message\":\"trigger trùng\"}}".utf8)
        guard case .failure(.engine(let status, let code, let message)) = EngineAPI.parseSnippetList(status: 400, data: body) else {
            Issue.record("phải lỗi engine"); return
        }
        #expect(status == 400 && code == "bad_request" && message == "trigger trùng")
    }
}
