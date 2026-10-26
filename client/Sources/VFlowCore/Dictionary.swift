import Foundation

/// Một mục từ điển cá nhân (xem contract/engine-api.md, mục "Từ điển cá nhân" và
/// `engine/post/dictionary.js` `validateEntries`). Lớp này chỉ là dữ liệu + kiểm hợp lệ thuần;
/// việc đọc/ghi qua HTTP nằm ở `EngineAPI` + lớp AppKit (orchestration, không test được thuần).
public struct DictionaryEntry: Equatable, Sendable {
    public var term: String
    public var spoken: [String]
    public var kind: String // "term" | "replace"
    public var caseExact: Bool
    public var uses: Int
    public var lastUsed: String?

    public init(term: String, spoken: [String], kind: String = "term", caseExact: Bool = false,
                uses: Int = 0, lastUsed: String? = nil) {
        self.term = term
        self.spoken = spoken
        self.kind = kind
        self.caseExact = caseExact
        self.uses = uses
        self.lastUsed = lastUsed
    }
}

/// Gợi ý từ `POST /v1/corrections` — chỉ gợi ý, người dùng xác nhận mới ghi.
public struct CorrectionSuggestion: Equatable, Sendable {
    public var term: String
    public var spoken: [String]
    public init(term: String, spoken: [String]) { self.term = term; self.spoken = spoken }
}

/// Thay đổi người dùng muốn áp lên từ điển, áp lên danh sách ĐỌC LẠI gần nhất (đọc-sửa-ghi).
public enum DictionaryChange: Sendable {
    case add(DictionaryEntry)
    /// `originalTerm` có thể khác `entry.term` (người dùng đổi tên thuật ngữ khi sửa).
    case update(originalTerm: String, entry: DictionaryEntry)
    case remove(term: String)
}

public struct DictionaryValidationError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

/// Kiểm hợp lệ phía client, khớp luật engine (`engine/post/dictionary.js`): tối đa 5000 mục;
/// `term` không rỗng ≤100 ký tự, không trùng; `spoken` 1–20 chuỗi không rỗng ≤100 ký tự, mỗi chuỗi
/// phải có ít nhất một chữ/số (không chỉ dấu câu); `kind` là "term" hoặc "replace".
public enum DictionaryValidation {
    public static let maxEntries = 5000
    public static let maxSpoken = 20
    public static let maxLen = 100

    public static func validate(_ entries: [DictionaryEntry]) -> Result<Void, DictionaryValidationError> {
        if entries.count > maxEntries {
            return .failure(.init("Quá nhiều mục: \(entries.count) > \(maxEntries)"))
        }
        var seen = Set<String>()
        for (i, e) in entries.enumerated() {
            let term = e.term.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces)
            if term.isEmpty || term.count > maxLen {
                return .failure(.init("Mục \(i + 1): tên thuật ngữ phải khác rỗng, tối đa \(maxLen) ký tự"))
            }
            if seen.contains(term) {
                return .failure(.init("Mục \(i + 1): tên thuật ngữ \"\(term)\" bị trùng"))
            }
            seen.insert(term)
            if e.spoken.isEmpty || e.spoken.count > maxSpoken {
                return .failure(.init("Mục \"\(term)\": cách nói phải có 1–\(maxSpoken) mục"))
            }
            for s in e.spoken {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                let hasWordChar = trimmed.rangeOfCharacter(from: .letters.union(.decimalDigits)) != nil
                if trimmed.isEmpty || trimmed.count > maxLen || !hasWordChar {
                    return .failure(.init("Mục \"\(term)\": mỗi cách nói phải có chữ, khác rỗng, tối đa \(maxLen) ký tự"))
                }
            }
            if e.kind != "term" && e.kind != "replace" {
                return .failure(.init("Mục \"\(term)\": kind phải là \"term\" hoặc \"replace\""))
            }
            if e.uses < 0 {
                return .failure(.init("Mục \"\(term)\": uses phải ≥ 0"))
            }
        }
        return .success(())
    }
}

/// Áp một thay đổi (thêm/sửa/xoá) hoặc một gợi ý sửa lên danh sách vừa đọc lại — đọc-sửa-ghi:
/// luôn gọi sau khi `GET /v1/dictionary` mới nhất để không đè thay đổi của người khác/engine.
public enum DictionaryPlanner {
    public static func apply(_ change: DictionaryChange, to current: [DictionaryEntry]) -> Result<[DictionaryEntry], DictionaryValidationError> {
        var next = current
        switch change {
        case .add(let e):
            next.append(e)
        case .update(let originalTerm, let e):
            guard let idx = next.firstIndex(where: { $0.term == originalTerm }) else {
                return .failure(.init("Không còn thấy mục \"\(originalTerm)\" — có thể đã bị xoá nơi khác, tải lại từ điển."))
            }
            next[idx] = e
        case .remove(let term):
            guard next.contains(where: { $0.term == term }) else {
                return .failure(.init("Không còn thấy mục \"\(term)\" — có thể đã bị xoá nơi khác, tải lại từ điển."))
            }
            next.removeAll { $0.term == term }
        }
        switch DictionaryValidation.validate(next) {
        case .success: return .success(next)
        case .failure(let e): return .failure(e)
        }
    }

    /// Chấp nhận một gợi ý: có mục cùng `term` ⇒ gộp biến thể nói mới (bỏ trùng, tối đa
    /// `maxSpoken`); chưa có ⇒ tạo mục mới kind "term".
    public static func mergeSuggestion(_ suggestion: CorrectionSuggestion, into current: [DictionaryEntry]) -> Result<[DictionaryEntry], DictionaryValidationError> {
        var next = current
        if let idx = next.firstIndex(where: { $0.term == suggestion.term }) {
            var spoken = next[idx].spoken
            for s in suggestion.spoken where !spoken.contains(s) { spoken.append(s) }
            if spoken.count > DictionaryValidation.maxSpoken {
                spoken = Array(spoken.suffix(DictionaryValidation.maxSpoken))
            }
            next[idx].spoken = spoken
        } else {
            next.append(DictionaryEntry(term: suggestion.term, spoken: suggestion.spoken))
        }
        switch DictionaryValidation.validate(next) {
        case .success: return .success(next)
        case .failure(let e): return .failure(e)
        }
    }
}
