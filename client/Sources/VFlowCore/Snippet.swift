import Foundation

/// Một mục snippet (đoạn văn mẫu gọi bằng lời — xem contract/engine-api.md, mục "Snippets" và
/// `engine/post/snippets.js` `validateEntries`). Dữ liệu + kiểm hợp lệ thuần; đọc/ghi qua HTTP nằm
/// ở `EngineAPI` + lớp AppKit (orchestration, xem `SnippetOrchestration`).
public struct SnippetEntry: Equatable, Sendable {
    public var trigger: String
    public var text: String
    public var uses: Int
    public var lastUsed: String?

    public init(trigger: String, text: String, uses: Int = 0, lastUsed: String? = nil) {
        self.trigger = trigger
        self.text = text
        self.uses = uses
        self.lastUsed = lastUsed
    }
}

public enum SnippetChange: Sendable {
    case add(SnippetEntry)
    /// `originalTrigger` có thể khác `entry.trigger` (người dùng đổi trigger khi sửa).
    case update(originalTrigger: String, entry: SnippetEntry)
    case remove(trigger: String)
}

public struct SnippetValidationError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

/// Kiểm hợp lệ phía client, khớp luật engine (`engine/post/snippets.js`): tối đa 500 mục; `trigger`
/// 1–60 ký tự khác rỗng, không trùng sau khi chuẩn hoá (bỏ dấu/hoa thường/dấu câu); `text` 1–5000
/// ký tự khác rỗng.
public enum SnippetValidation {
    public static let maxEntries = 500
    public static let maxTrigger = 60
    public static let maxText = 5000

    public static func validate(_ entries: [SnippetEntry]) -> Result<Void, SnippetValidationError> {
        if entries.count > maxEntries {
            return .failure(.init("Quá nhiều mục: \(entries.count) > \(maxEntries)"))
        }
        var seenNorm = Set<String>()
        for (i, e) in entries.enumerated() {
            let trigger = e.trigger.trimmingCharacters(in: .whitespaces)
            if trigger.isEmpty || trigger.count > maxTrigger {
                return .failure(.init("Mục \(i + 1): trigger phải khác rỗng, tối đa \(maxTrigger) ký tự"))
            }
            let norm = VietnameseMatch.normalizeMatch(trigger)
            if norm.isEmpty {
                return .failure(.init("Mục \(i + 1): trigger phải có chữ"))
            }
            if seenNorm.contains(norm) {
                return .failure(.init("Mục \(i + 1): trigger \"\(trigger)\" trùng với một mục khác (sau khi bỏ dấu/hoa thường/dấu câu)"))
            }
            seenNorm.insert(norm)
            if e.text.isEmpty || e.text.count > maxText {
                return .failure(.init("Mục \"\(trigger)\": nội dung phải khác rỗng, tối đa \(maxText) ký tự"))
            }
            if e.uses < 0 {
                return .failure(.init("Mục \"\(trigger)\": uses phải ≥ 0"))
            }
        }
        return .success(())
    }
}

/// Áp một thay đổi (thêm/sửa/xoá) lên danh sách vừa đọc lại — đọc-sửa-ghi, giống `DictionaryPlanner`.
public enum SnippetPlanner {
    public static func apply(_ change: SnippetChange, to current: [SnippetEntry]) -> Result<[SnippetEntry], SnippetValidationError> {
        var next = current
        switch change {
        case .add(let e):
            next.append(e)
        case .update(let originalTrigger, let e):
            guard let idx = next.firstIndex(where: { $0.trigger == originalTrigger }) else {
                return .failure(.init("Không còn thấy mục \"\(originalTrigger)\" — có thể đã bị xoá nơi khác, tải lại snippets."))
            }
            next[idx] = e
        case .remove(let trigger):
            guard next.contains(where: { $0.trigger == trigger }) else {
                return .failure(.init("Không còn thấy mục \"\(trigger)\" — có thể đã bị xoá nơi khác, tải lại snippets."))
            }
            next.removeAll { $0.trigger == trigger }
        }
        switch SnippetValidation.validate(next) {
        case .success: return .success(next)
        case .failure(let e): return .failure(e)
        }
    }
}

/// Mẫu đọc-sửa-ghi chung cho `/v1/snippets`, giống `DictionaryOrchestration`.
public enum SnippetOrchestration {
    public static func applyChange(
        _ change: SnippetChange,
        get: @Sendable () async -> Result<[SnippetEntry], ClientError>,
        put: @Sendable ([SnippetEntry]) async -> Result<[SnippetEntry], ClientError>
    ) async -> Result<[SnippetEntry], ClientError> {
        switch await get() {
        case .failure(let e): return .failure(e)
        case .success(let current):
            switch SnippetPlanner.apply(change, to: current) {
            case .failure(let e): return .failure(.snippetInvalid(e.message))
            case .success(let next): return await put(next)
            }
        }
    }
}
