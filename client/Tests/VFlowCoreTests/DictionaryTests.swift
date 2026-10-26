import Foundation
import Testing
@testable import VFlowCore

/// Hộp đơn giản để gom trạng thái từ closure `@Sendable` trong test — các `await` dưới đây chạy
/// tuần tự (không thật sự đồng thời), nhưng trình biên dịch Swift 6 vẫn đòi kiểu Sendable.
private final class TestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: T) { lock.lock(); defer { lock.unlock() }; value = v }
    func append<E>(_ e: E) where T == [E] { lock.lock(); defer { lock.unlock() }; value.append(e) }
}

@Suite struct DictionaryValidationTests {
    @Test func validEntryPasses() {
        let e = DictionaryEntry(term: "deploy", spoken: ["đi plôi", "đì ploi"])
        #expect(DictionaryValidation.validate([e]).isSuccess)
    }

    @Test func emptyTermIsRejected() {
        let e = DictionaryEntry(term: "", spoken: ["x"])
        guard case .failure(let err) = DictionaryValidation.validate([e]) else { Issue.record("phải lỗi"); return }
        #expect(err.message.contains("thuật ngữ"))
    }

    @Test func duplicateTermIsRejected() {
        let a = DictionaryEntry(term: "deploy", spoken: ["đi plôi"])
        let b = DictionaryEntry(term: "deploy", spoken: ["đì ploi"])
        guard case .failure(let err) = DictionaryValidation.validate([a, b]) else { Issue.record("phải lỗi trùng term"); return }
        #expect(err.message.contains("trùng"))
    }

    @Test func spokenMustHaveAtLeastOneWordCharacter() {
        let e = DictionaryEntry(term: "deploy", spoken: ["...", "---"])
        guard case .failure(let err) = DictionaryValidation.validate([e]) else { Issue.record("spoken chỉ dấu câu phải lỗi"); return }
        #expect(err.message.contains("chữ"))
    }

    @Test func spokenCountMustBeOneToTwenty() {
        let empty = DictionaryEntry(term: "deploy", spoken: [])
        guard case .failure = DictionaryValidation.validate([empty]) else { Issue.record("spoken rỗng phải lỗi"); return }
        let tooMany = DictionaryEntry(term: "deploy", spoken: (1...21).map { "cách nói \($0)" })
        guard case .failure = DictionaryValidation.validate([tooMany]) else { Issue.record("spoken > 20 phải lỗi"); return }
    }

    @Test func kindMustBeTermOrReplace() {
        let e = DictionaryEntry(term: "deploy", spoken: ["x"], kind: "weird")
        guard case .failure(let err) = DictionaryValidation.validate([e]) else { Issue.record("kind lạ phải lỗi"); return }
        #expect(err.message.contains("kind"))
    }

    @Test func tooManyEntriesIsRejected() {
        let entries = (0..<(DictionaryValidation.maxEntries + 1)).map { DictionaryEntry(term: "t\($0)", spoken: ["x\($0)"]) }
        guard case .failure(let err) = DictionaryValidation.validate(entries) else { Issue.record("vượt 5000 mục phải lỗi"); return }
        #expect(err.message.contains("5000"))
    }

    @Test func termOver100CharsIsRejected() {
        let e = DictionaryEntry(term: String(repeating: "a", count: 101), spoken: ["x"])
        guard case .failure = DictionaryValidation.validate([e]) else { Issue.record("term > 100 ký tự phải lỗi"); return }
    }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { return true }; return false }
}

@Suite struct DictionaryPlannerTests {
    @Test func addAppendsEntry() throws {
        let current = [DictionaryEntry(term: "deploy", spoken: ["đi plôi"])]
        let next = try DictionaryPlanner.apply(.add(DictionaryEntry(term: "worktree", spoken: ["goọc chi"])), to: current).get()
        #expect(next.count == 2)
        #expect(next.map(\.term) == ["deploy", "worktree"])
    }

    @Test func addDuplicateTermIsRejected() {
        let current = [DictionaryEntry(term: "deploy", spoken: ["đi plôi"])]
        guard case .failure = DictionaryPlanner.apply(.add(DictionaryEntry(term: "deploy", spoken: ["khác"])), to: current) else {
            Issue.record("thêm term trùng phải lỗi"); return
        }
    }

    @Test func updateRenamesAndKeepsPosition() throws {
        let current = [DictionaryEntry(term: "deploy", spoken: ["đi plôi"], uses: 5)]
        let edited = DictionaryEntry(term: "deployment", spoken: ["đi plôi", "đi plôi mần"], uses: 5)
        let next = try DictionaryPlanner.apply(.update(originalTerm: "deploy", entry: edited), to: current).get()
        #expect(next == [edited])
    }

    /// Nhánh đọc-sửa-ghi: mục đã bị xoá nơi khác (engine đổi giữa chừng) ⇒ áp thay đổi lên bản
    /// MỚI NHẤT phải báo lỗi rõ ràng, không âm thầm tạo lại hoặc đè.
    @Test func updatingAnEntryRemovedConcurrentlyFails() {
        let staleGoneAlready: [DictionaryEntry] = [] // "đọc lại" thấy mục đã bị xoá
        guard case .failure(let err) = DictionaryPlanner.apply(.update(originalTerm: "deploy", entry: DictionaryEntry(term: "deploy", spoken: ["x"])), to: staleGoneAlready) else {
            Issue.record("sửa mục đã bị xoá nơi khác phải lỗi"); return
        }
        #expect(err.message.contains("deploy"))
    }

    @Test func removeDropsEntry() throws {
        let current = [DictionaryEntry(term: "deploy", spoken: ["x"]), DictionaryEntry(term: "worktree", spoken: ["y"])]
        let next = try DictionaryPlanner.apply(.remove(term: "deploy"), to: current).get()
        #expect(next.map(\.term) == ["worktree"])
    }

    @Test func removingMissingTermFails() {
        guard case .failure = DictionaryPlanner.apply(.remove(term: "ghost"), to: []) else {
            Issue.record("xoá mục không tồn tại phải lỗi"); return
        }
    }

    @Test func mergeSuggestionIntoExistingTermAppendsVariant() throws {
        let current = [DictionaryEntry(term: "deploy", spoken: ["đi plôi"])]
        let next = try DictionaryPlanner.mergeSuggestion(CorrectionSuggestion(term: "deploy", spoken: ["đì ploi"]), into: current).get()
        #expect(next == [DictionaryEntry(term: "deploy", spoken: ["đi plôi", "đì ploi"])])
    }

    @Test func mergeSuggestionSkipsExactDuplicateVariant() throws {
        let current = [DictionaryEntry(term: "deploy", spoken: ["đi plôi"])]
        let next = try DictionaryPlanner.mergeSuggestion(CorrectionSuggestion(term: "deploy", spoken: ["đi plôi"]), into: current).get()
        #expect(next[0].spoken == ["đi plôi"])
    }

    @Test func mergeSuggestionForNewTermCreatesEntry() throws {
        let next = try DictionaryPlanner.mergeSuggestion(CorrectionSuggestion(term: "worktree", spoken: ["goọc chi"]), into: []).get()
        #expect(next == [DictionaryEntry(term: "worktree", spoken: ["goọc chi"])])
    }

    @Test func mergeSuggestionCapsAtTwentyVariants() throws {
        let existing = DictionaryEntry(term: "deploy", spoken: (1...20).map { "biến thể \($0)" })
        let next = try DictionaryPlanner.mergeSuggestion(CorrectionSuggestion(term: "deploy", spoken: ["biến thể mới"]), into: [existing]).get()
        #expect(next[0].spoken.count == 20)
        #expect(next[0].spoken.last == "biến thể mới")
    }
}

@Suite struct DictionaryOrchestrationTests {
    @Test func readModifyWriteSendsFreshlyReadListToPut() async {
        let putCalls = TestBox<[[DictionaryEntry]]>([])
        let result = await DictionaryOrchestration.applyChange(
            .add(DictionaryEntry(term: "worktree", spoken: ["goọc chi"])),
            get: { .success([DictionaryEntry(term: "deploy", spoken: ["đi plôi"])]) },
            put: { entries in putCalls.append(entries); return .success(entries) })
        guard case .success(let next) = result else { Issue.record("phải thành công"); return }
        #expect(next.map(\.term) == ["deploy", "worktree"])
        #expect(putCalls.get().count == 1)
    }

    /// Nhánh chính của đọc-sửa-ghi: engine đổi giữa lúc người dùng mở hộp sửa và lúc bấm Lưu
    /// (mục bị người khác xoá) ⇒ KHÔNG được gọi PUT (không đè), phải báo lỗi rõ.
    @Test func engineChangedBetweenReadAndWriteAbortsWithoutPut() async {
        let putCalled = TestBox(false)
        let result = await DictionaryOrchestration.applyChange(
            .update(originalTerm: "deploy", entry: DictionaryEntry(term: "deploy", spoken: ["mới"])),
            get: { .success([]) }, // đọc lại ngay trước khi ghi: mục đã mất
            put: { entries in putCalled.set(true); return .success(entries) })
        guard case .failure(.dictionaryInvalid(let m)) = result else { Issue.record("phải lỗi dictionaryInvalid"); return }
        #expect(m.contains("deploy"))
        #expect(!putCalled.get(), "không được ghi đè khi đã phát hiện xung đột")
    }

    @Test func engineBadRequestIsForwardedNotSwallowed() async {
        let result = await DictionaryOrchestration.applyChange(
            .add(DictionaryEntry(term: "worktree", spoken: ["goọc chi"])),
            get: { .success([]) },
            put: { _ in .failure(.engine(status: 400, code: "bad_request", message: "entries[0].term bị trùng")) })
        guard case .failure(.engine(400, "bad_request", let msg)) = result else { Issue.record("phải forward lỗi engine"); return }
        #expect(msg.contains("trùng"))
    }

    @Test func getFailureShortCircuitsBeforePut() async {
        let putCalled = TestBox(false)
        let result = await DictionaryOrchestration.applyChange(
            .add(DictionaryEntry(term: "worktree", spoken: ["x"])),
            get: { .failure(.engineNotRunning) },
            put: { _ in putCalled.set(true); return .success([]) })
        guard case .failure(.engineNotRunning) = result else { Issue.record("phải lỗi engineNotRunning"); return }
        #expect(!putCalled.get())
    }

    @Test func acceptSuggestionMergesThenPuts() async {
        let result = await DictionaryOrchestration.acceptSuggestion(
            CorrectionSuggestion(term: "deploy", spoken: ["đì ploi"]),
            get: { .success([DictionaryEntry(term: "deploy", spoken: ["đi plôi"])]) },
            put: { .success($0) })
        guard case .success(let next) = result else { Issue.record("phải thành công"); return }
        #expect(next[0].spoken == ["đi plôi", "đì ploi"])
    }
}
