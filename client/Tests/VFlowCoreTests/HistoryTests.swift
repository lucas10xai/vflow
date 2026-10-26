import Foundation
import Testing
@testable import VFlowCore

@Suite struct HistoryStoreTests {
    func tempPath() -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-history-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.jsonl").path
    }

    func entry(_ text: String, at date: Date = Date()) -> HistoryEntry {
        HistoryEntry(at: date, appBundleId: "com.apple.Terminal", mode: "normal", model: "zipformer-vi-30m",
                    textRaw: text, text: text, audioMs: 1200, totalMs: 130)
    }

    @Test func appendThenListReturnsNewestFirst() throws {
        let store = HistoryStore(path: tempPath())
        let now = Date()
        try store.append(entry("một", at: now.addingTimeInterval(1)))
        try store.append(entry("hai", at: now.addingTimeInterval(2)))
        let r = try store.list()
        #expect(r.entries.map(\.text) == ["hai", "một"])
        #expect(r.corruptLines == 0)
    }

    @Test func permissionsAre0600AfterAppend() throws {
        let path = tempPath()
        let store = HistoryStore(path: path)
        try store.append(entry("x"))
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func capsAtMaxEntries() throws {
        let store = HistoryStore(path: tempPath(), maxEntries: 5)
        let now = Date()
        for i in 0..<8 { try store.append(entry("câu \(i)", at: now.addingTimeInterval(Double(i)))) }
        let r = try store.list()
        #expect(r.entries.count == 5)
        // Giữ 5 mục MỚI NHẤT (câu 3..câu 7), không phải 5 mục đầu.
        #expect(r.entries.map(\.text) == ["câu 7", "câu 6", "câu 5", "câu 4", "câu 3"])
    }

    @Test func prunesEntriesOlderThanMaxAgeDays() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let store = HistoryStore(path: tempPath(), maxAgeDays: 30, clock: { fixedNow })
        try store.append(entry("cũ quá hạn", at: fixedNow.addingTimeInterval(-31 * 86400)))
        try store.append(entry("còn mới", at: fixedNow.addingTimeInterval(-1 * 86400)))
        let r = try store.list()
        #expect(r.entries.map(\.text) == ["còn mới"])
    }

    /// Nhánh bắt lỗi thật: một dòng JSON hỏng xen giữa các dòng tốt không được làm sập `list()`,
    /// chỉ bị bỏ qua và đếm.
    @Test func corruptLineIsSkippedAndCountedNotCrashing() throws {
        let path = tempPath()
        let store = HistoryStore(path: path)
        try store.append(entry("trước"))
        let handle = try #require(FileHandle(forWritingAtPath: path))
        handle.seekToEndOfFile()
        handle.write("{không phải json hợp lệ\n".data(using: .utf8)!)
        handle.write("{\"id\":\"x\"}\n".data(using: .utf8)!) // thiếu trường bắt buộc
        handle.closeFile()
        try store.append(entry("sau"))
        let r = try store.list()
        #expect(r.entries.map(\.text).sorted() == ["sau", "trước"])
        #expect(r.corruptLines == 2)
    }

    @Test func searchFiltersByTextCaseAndDiacriticInsensitive() throws {
        let store = HistoryStore(path: tempPath())
        try store.append(entry("kiểm tra trạng thái git"))
        try store.append(entry("mở Notes"))
        let r = try store.list(query: "KIEM TRA")
        #expect(r.entries.map(\.text) == ["kiểm tra trạng thái git"])
    }

    @Test func deleteRemovesOnlyThatEntry() throws {
        let store = HistoryStore(path: tempPath())
        let now = Date()
        try store.append(entry("a", at: now.addingTimeInterval(1)))
        let bEntry = entry("b", at: now.addingTimeInterval(2))
        try store.append(bEntry)
        try store.delete(id: bEntry.id)
        let r = try store.list()
        #expect(r.entries.map(\.text) == ["a"])
    }

    @Test func clearAllEmptiesHistory() throws {
        let store = HistoryStore(path: tempPath())
        try store.append(entry("a"))
        try store.append(entry("b"))
        try store.clearAll()
        #expect(try store.list().entries.isEmpty)
    }

    @Test func concurrentAppendsDoNotCorruptLines() async throws {
        let store = HistoryStore(path: tempPath())
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask { _ = try? store.append(self.entry("đồng thời \(i)")) }
            }
        }
        let r = try store.list(query: nil)
        // Không cap mặc định (500) nên tất cả 30 phải còn, không dòng nào vỡ (corruptLines == 0).
        #expect(r.entries.count == 30)
        #expect(r.corruptLines == 0)
        #expect(Set(r.entries.map(\.id)).count == 30, "mỗi id phải còn nguyên, không dòng nào bị cắt nửa")
    }
}

@Suite struct HistoryGateTests {
    @Test func disabledNeverRecords() {
        #expect(!HistoryGate.shouldRecord(enabled: false, insertedText: "xin chào"))
    }

    @Test func emptyOrWhitespaceTextIsNeverRecorded() {
        #expect(!HistoryGate.shouldRecord(enabled: true, insertedText: ""))
        #expect(!HistoryGate.shouldRecord(enabled: true, insertedText: "   \n"))
        #expect(!HistoryGate.shouldRecord(enabled: true, insertedText: nil))
    }

    @Test func enabledWithRealTextRecords() {
        #expect(HistoryGate.shouldRecord(enabled: true, insertedText: "xin chào"))
    }
}

@Suite struct LastSpokenTextTests {
    @Test func usesHistoryWhenHistoryEnabled() {
        #expect(LastSpokenText.resolve(historyEnabled: true, historyTopText: "câu từ lịch sử", inMemoryText: "câu trong bộ nhớ") == "câu từ lịch sử")
    }

    @Test func usesInMemoryWhenHistoryDisabled() {
        #expect(LastSpokenText.resolve(historyEnabled: false, historyTopText: "câu từ lịch sử", inMemoryText: "câu trong bộ nhớ") == "câu trong bộ nhớ")
    }

    @Test func nilOrEmptyMeansNoSentence() {
        #expect(LastSpokenText.resolve(historyEnabled: true, historyTopText: nil, inMemoryText: "x") == nil)
        #expect(LastSpokenText.resolve(historyEnabled: true, historyTopText: "   ", inMemoryText: "x") == nil)
        #expect(LastSpokenText.resolve(historyEnabled: false, historyTopText: "x", inMemoryText: nil) == nil)
    }
}
