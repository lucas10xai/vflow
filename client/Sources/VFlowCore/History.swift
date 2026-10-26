import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Một câu đã đọc chính tả. CHỈ văn bản — tuyệt đối không có âm thanh (xem contract/engine-api.md,
/// bất biến 1: âm thanh không bao giờ ghi xuống đĩa).
public struct HistoryEntry: Equatable, Sendable, Identifiable {
    public var id: String
    public var at: Date
    public var appBundleId: String?
    public var mode: String
    public var model: String
    public var textRaw: String
    public var text: String
    public var audioMs: Int?
    public var totalMs: Int?

    public init(id: String = HistoryEntry.newId(), at: Date, appBundleId: String? = nil, mode: String,
                model: String, textRaw: String, text: String, audioMs: Int? = nil, totalMs: Int? = nil) {
        self.id = id
        self.at = at
        self.appBundleId = appBundleId
        self.mode = mode
        self.model = model
        self.textRaw = textRaw
        self.text = text
        self.audioMs = audioMs
        self.totalMs = totalMs
    }

    public static func newId() -> String { "h_" + UUID().uuidString.lowercased() }
}

public enum HistoryError: Error, Equatable, Sendable {
    case io(String)
}

/// Lưu lịch sử đọc chính tả vào `<VFLOW_HOME>/history.jsonl` (quyền 0600). Mỗi dòng một mục JSON.
/// Giữ tối đa `maxEntries` mục và `maxAgeDays` ngày (tự dọn mỗi lần ghi); dòng hỏng bị bỏ qua và
/// đếm, không làm sập. An toàn khi nhiều lệnh `append` chạy đồng thời trong cùng tiến trình (khoá
/// trong `HistoryStore`); việc ghi đè khi dọn luôn qua tệp tạm + rename nguyên tử.
public final class HistoryStore: @unchecked Sendable {
    public struct ReadResult: Equatable, Sendable {
        public var entries: [HistoryEntry]
        public var corruptLines: Int
    }

    public let path: String
    public let maxEntries: Int
    public let maxAgeDays: Int
    private let clock: @Sendable () -> Date
    private let lock = NSLock()

    public init(path: String, maxEntries: Int = 500, maxAgeDays: Int = 30, clock: @escaping @Sendable () -> Date = Date.init) {
        self.path = path
        self.maxEntries = maxEntries
        self.maxAgeDays = maxAgeDays
        self.clock = clock
    }

    /// Thêm một mục: ghi nối (một lệnh `write` duy nhất, nguyên tử ở mức hệ điều hành cho dòng
    /// ngắn). Chỉ dọn (tệp tạm + rename) khi tệp đã vượt `maxEntries` dòng thô — dòng hỏng/quá
    /// hạn vẫn được BÁO (đếm/lọc) ở mọi lần `list()`, chỉ bị xoá khỏi đĩa khi thật sự cần co lại.
    @discardableResult
    public func append(_ entry: HistoryEntry) throws -> ReadResult {
        lock.lock(); defer { lock.unlock() }
        try Self.ensureDirectory(for: path)
        try Self.appendLineAtomically(Self.encode(entry) + "\n", to: path)
        let kept = try readAllLocked()
        let rawLines = (FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) } ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true).count
        if rawLines > maxEntries {
            try Self.rewrite(kept.entries, path: path)
        }
        return kept
    }

    /// Đọc toàn bộ (đã lọc tuổi + giới hạn số mục + lọc tìm kiếm), mới nhất trước.
    public func list(query: String? = nil) throws -> ReadResult {
        lock.lock(); defer { lock.unlock() }
        var r = try readAllLocked()
        if let q = query, !q.trimmingCharacters(in: .whitespaces).isEmpty {
            let needle = q.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            r.entries = r.entries.filter {
                $0.text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(needle)
                    || $0.textRaw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(needle)
            }
        }
        return r
    }

    @discardableResult
    public func delete(id: String) throws -> ReadResult {
        lock.lock(); defer { lock.unlock() }
        let r = try readAllLocked()
        let kept = r.entries.filter { $0.id != id }
        try Self.rewrite(kept, path: path)
        return ReadResult(entries: kept, corruptLines: r.corruptLines)
    }

    public func clearAll() throws {
        lock.lock(); defer { lock.unlock() }
        try Self.rewrite([], path: path)
    }

    // MARK: đọc + lọc (gọi trong khi đã giữ khoá)

    private func readAllLocked() throws -> ReadResult {
        guard let data = FileManager.default.contents(atPath: path) else {
            return ReadResult(entries: [], corruptLines: 0)
        }
        let text = String(decoding: data, as: UTF8.self)
        var entries: [HistoryEntry] = []
        var corrupt = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let e = Self.decode(line) { entries.append(e) } else { corrupt += 1 }
        }
        let cutoff = clock().addingTimeInterval(-Double(maxAgeDays) * 86400)
        entries = entries.filter { $0.at >= cutoff }
        entries.sort { $0.at > $1.at }
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        return ReadResult(entries: entries, corruptLines: corrupt)
    }

    // MARK: I/O cấp thấp

    private static func ensureDirectory(for path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        } catch {
            throw HistoryError.io(error.localizedDescription)
        }
    }

    /// Một lệnh `write(2)` duy nhất với `O_APPEND`: nguyên tử ở mức hệ điều hành cho một dòng
    /// JSONL ngắn, dù nhiều tiến trình/luồng cùng ghi.
    private static func appendLineAtomically(_ line: String, to path: String) throws {
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { throw HistoryError.io(String(cString: strerror(errno))) }
        defer { close(fd) }
        let bytes = Array(line.utf8)
        var off = 0
        while off < bytes.count {
            let n = bytes.withUnsafeBufferPointer { buf -> Int in
                guard let base = buf.baseAddress else { return 0 }
                return Darwin.write(fd, base.advanced(by: off), buf.count - off)
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw HistoryError.io(String(cString: strerror(errno)))
            }
            off += n
        }
    }

    /// Ghi đè toàn bộ tệp qua tệp tạm + rename nguyên tử (`Data.write(options:.atomic)`), quyền 0600.
    private static func rewrite(_ entries: [HistoryEntry], path: String) throws {
        try ensureDirectory(for: path)
        let body = entries.map(encode).joined(separator: "\n") + (entries.isEmpty ? "" : "\n")
        do {
            try Data(body.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch {
            throw HistoryError.io(error.localizedDescription)
        }
    }

    /// Một bộ định dạng mới mỗi lần gọi: `ISO8601DateFormatter` không đảm bảo an toàn khi dùng
    /// đồng thời từ nhiều luồng, và `encode`/`decode` có thể được gọi từ nhiều `Task` cùng lúc.
    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    static func encode(_ e: HistoryEntry) -> String {
        let iso = makeISOFormatter()
        var obj: [String: Any] = [
            "id": e.id, "at": iso.string(from: e.at), "mode": e.mode, "model": e.model,
            "text_raw": e.textRaw, "text": e.text,
        ]
        if let a = e.appBundleId { obj["app"] = a }
        if let a = e.audioMs { obj["audio_ms"] = a }
        if let t = e.totalMs { obj["total_ms"] = t }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// `nil` ⇒ dòng hỏng (JSON sai, thiếu trường bắt buộc, hoặc "at" không phải ISO8601).
    static func decode(_ line: String) -> HistoryEntry? {
        let iso = makeISOFormatter()
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String, !id.isEmpty,
              let atStr = obj["at"] as? String, let at = iso.date(from: atStr),
              let mode = obj["mode"] as? String, !mode.isEmpty,
              let model = obj["model"] as? String,
              let textRaw = obj["text_raw"] as? String,
              let text = obj["text"] as? String
        else { return nil }
        return HistoryEntry(id: id, at: at, appBundleId: obj["app"] as? String, mode: mode, model: model,
                            textRaw: textRaw, text: text, audioMs: obj["audio_ms"] as? Int, totalMs: obj["total_ms"] as? Int)
    }
}

/// Câu dùng cho "Chèn lại câu vừa rồi" (menu thanh trạng thái/Dock, phím tắt ⌥⌘V mặc định) — thuần,
/// test được. Lịch sử bật ⇒ lấy từ lịch sử (đúng mục mới nhất, kể cả sau khi khởi động lại app);
/// lịch sử tắt ⇒ chỉ dùng bộ nhớ trong phiên chạy hiện tại (không ghi đĩa, mất khi thoát app).
public enum LastSpokenText {
    public static func resolve(historyEnabled: Bool, historyTopText: String?, inMemoryText: String?) -> String? {
        let candidate = historyEnabled ? historyTopText : inMemoryText
        guard let c = candidate, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return c
    }

    public static let noSentenceMessage = "Chưa có câu nào"
}

/// Quyết định có ghi một lần đọc chính tả vào lịch sử hay không — thuần, test được không cần tệp.
public enum HistoryGate {
    /// `enabled`: công tắc "Lưu lịch sử". Kết quả lỗi/im lặng/rỗng không bao giờ vào lịch sử
    /// (chỉ gọi khi đã có `text` thật sự được dùng, vd. đã chèn hoặc còn trên clipboard).
    public static func shouldRecord(enabled: Bool, insertedText: String?) -> Bool {
        guard enabled, let t = insertedText else { return false }
        return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
