import Foundation
import Testing
@testable import VFlowCore

/// Xoá mục lịch sử / xoá tất cả / mục hết hạn ⇒ gọi phía trên PHẢI biết `audio_id` nào cần
/// `DELETE /v1/audio/<id>` (best-effort, lỗi mạng không chặn xoá mục). Lớp lưu trữ phải luôn xoá mục
/// thành công và trao đủ id — kể cả khi không có engine.
@Suite struct AudioHistoryEvictionTests {
    private func tempPath() -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-evict-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.jsonl").path
    }

    private func entry(_ text: String, at date: Date, audioId: String? = nil) -> HistoryEntry {
        HistoryEntry(at: date, appBundleId: "com.apple.Terminal", mode: "normal", model: "m", textRaw: text, text: text,
                     audioMs: 1000, totalMs: 100, audioId: audioId)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func deleteSucceedsAndHandsBackAudioIdWithoutAnyNetwork() throws {
        let store = HistoryStore(path: tempPath(), clock: { [now] in now })
        let e = entry("x", at: now, audioId: "au_x")
        try store.append(e)
        let removed = try store.delete(id: e.id)
        #expect(removed?.audioId == "au_x", "gọi phía trên cần id này để dọn âm thanh")
        #expect(try store.list().entries.isEmpty, "mục phải mất khỏi lịch sử dù việc xoá âm thanh chưa/không thành")
    }

    @Test func clearAllHandsBackEveryAudioIdIncludingExpiredEntriesStillOnDisk() throws {
        let store = HistoryStore(path: tempPath(), maxAgeDays: 30, clock: { [now] in now })
        try store.append(entry("mới", at: now.addingTimeInterval(-86400), audioId: "au_new"))
        try store.append(entry("quá hạn", at: now.addingTimeInterval(-40 * 86400), audioId: "au_old"))
        let removed = try store.clearAll()
        #expect(Set(removed.compactMap(\.audioId)) == ["au_new", "au_old"])
    }

    @Test func expiredEntryWithAudioIsReportedExactlyOnceByList() throws {
        let store = HistoryStore(path: tempPath(), maxAgeDays: 30, clock: { [now] in now })
        try store.append(entry("quá hạn", at: now.addingTimeInterval(-31 * 86400), audioId: "au_old"))
        try store.append(entry("còn mới", at: now.addingTimeInterval(-86400), audioId: "au_new"))
        let first = try store.list()
        #expect(first.entries.map(\.text) == ["còn mới"])
        #expect(first.evicted.compactMap(\.audioId) == ["au_old"])
        let second = try store.list()
        #expect(second.evicted.isEmpty, "mỗi mục chỉ báo MỘT lần")
        #expect(second.entries.map(\.audioId) == ["au_new"])
    }

    @Test func expiredEntryWithoutAudioIsNeverReported() throws {
        let store = HistoryStore(path: tempPath(), maxAgeDays: 30, clock: { [now] in now })
        try store.append(entry("cũ", at: now.addingTimeInterval(-90 * 86400)))
        #expect(try store.list().evicted.isEmpty)
    }

    @Test func entriesPushedOutByMaxEntriesAreReported() throws {
        let store = HistoryStore(path: tempPath(), maxEntries: 2, clock: { [now] in now })
        for i in 0..<4 {
            try store.append(entry("câu \(i)", at: now.addingTimeInterval(Double(i)), audioId: "au_\(i)"))
        }
        let r = try store.list()
        #expect(r.entries.map(\.audioId) == ["au_3", "au_2"])
        #expect(Set(r.evicted.compactMap(\.audioId)) == ["au_0", "au_1"])
    }

    /// Xoá một mục làm tệp bị ghi đè — mục QUÁ HẠN bị cuốn theo vẫn phải được báo để dọn âm thanh.
    @Test func deletingOneEntryStillReportsExpiredNeighboursAudio() throws {
        let store = HistoryStore(path: tempPath(), maxAgeDays: 30, clock: { [now] in now })
        try store.append(entry("quá hạn", at: now.addingTimeInterval(-40 * 86400), audioId: "au_old"))
        let keep = entry("bị xoá", at: now.addingTimeInterval(-3600), audioId: "au_del")
        try store.append(keep)
        try store.delete(id: keep.id)
        let r = try store.list()
        #expect(r.evicted.compactMap(\.audioId) == ["au_old"])
    }

    @Test func clearAudioIdKeepsSentenceAndLeavesOtherEntriesAlone() throws {
        let store = HistoryStore(path: tempPath(), clock: { [now] in now })
        let a = entry("a", at: now.addingTimeInterval(-10), audioId: "au_a")
        let b = entry("b", at: now.addingTimeInterval(-5), audioId: "au_b")
        try store.append(a)
        try store.append(b)
        try store.clearAudioId(id: a.id)
        let r = try store.list()
        #expect(r.entries.map(\.text) == ["b", "a"])
        #expect(r.entries.map(\.audioId) == ["au_b", nil])
    }
}
