import Foundation

/// "Dạy từ bằng giọng" (V3, tab Từ điển): người dùng nói một thuật ngữ nhiều lần (3–5 lần qua
/// `POST /v1/teach`), mỗi lần engine trả một chữ "nghe ra" (`heard`, chữ thô chưa qua từ điển).
/// Logic ở đây CHỈ gom/chuẩn hoá các lần nghe khác nhau thành danh sách "cách nói" ứng viên để
/// thêm vào từ điển — không gọi mạng, không biết gì về `/v1/teach` (xem `EngineAPI.teachRequest`).
public enum TeachWordVariants {
    /// Số lần nói khuyến nghị tối thiểu / tối đa mỗi phiên dạy từ (sheet chặn ghi thêm khi đủ tối đa;
    /// bỏ dòng "Nghe ra" thì ghi lại được).
    public static let minAttempts = 3
    public static let maxAttempts = 5
    /// Mỗi lần ghi tối đa bấy nhiêu giây (engine `/v1/teach` cho tới 15 giây, sheet tự dừng sớm hơn).
    public static let maxSecondsPerAttempt = 10

    /// Một lần nghe đã đánh số, giữ nguyên văn gốc để hiện "Nghe ra: …" và còn xoá được riêng lẻ.
    public struct Heard: Equatable, Sendable, Identifiable {
        public var id: Int
        public var text: String
        public init(id: Int, text: String) {
            self.id = id
            self.text = text
        }
    }

    /// Chuẩn hoá một lần nghe để SO SÁNH/gộp (không dùng để HIỂN THỊ): chuẩn hoá Unicode NFC (gộp
    /// các lần nghe giống nhau nhưng tổ hợp dấu khác dạng — vd "tiếng" NFC vs "tiếng" NFD vẫn gộp
    /// được), hạ chữ thường, rút gọn khoảng trắng, bỏ khoảng trắng hai đầu.
    public static func normalize(_ s: String) -> String {
        let folded = s.precomposedStringWithCanonicalMapping.lowercased()
        // `split(whereSeparator:)` xử lý cả space, tab, newline và whitespace Unicode; dùng
        // `split(separator: " ")` sẽ để lọt các biến thể nhìn giống nhau nhưng khác khoảng trắng.
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Gom danh sách "nghe ra" thô thành cách nói ỨNG VIÊN để tiền chọn trong sheet: bỏ chuỗi rỗng
    /// (sau chuẩn hoá) và quá dài (> `DictionaryValidation.maxLen`, cùng giới hạn với `spoken` ở từ
    /// điển), bỏ trùng (giữ bản xuất hiện ĐẦU TIÊN để thứ tự ổn định cho người dùng), bỏ cách nói
    /// trùng CHÍNH từ đúng (`correctTerm`, không cần dạy lại cái engine đã nghe đúng). Trả về danh
    /// sách văn bản gốc (không hạ thường) của đại diện đầu tiên mỗi nhóm trùng — giữ cách viết người
    /// dùng dễ nhận ra nhất.
    public static func candidates(from heard: [String], correctTerm: String) -> [String] {
        let normalizedCorrect = normalize(correctTerm)
        var seen = Set<String>()
        var result: [String] = []
        for raw in heard {
            let trimmedOriginal = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(trimmedOriginal)
            guard !key.isEmpty, key.count <= DictionaryValidation.maxLen, key != normalizedCorrect,
                  hasWordCharacter(key) else { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmedOriginal)
        }
        return result
    }

    /// `DictionaryValidation` từ chối cách nói không có chữ/số nào (vd. engine nghe ra "..."): lọc
    /// sớm ở đây để một dòng như vậy không làm hỏng cả lần Lưu.
    static func hasWordCharacter(_ s: String) -> Bool {
        s.rangeOfCharacter(from: .letters.union(.decimalDigits)) != nil
    }

    /// Lỗi của ô "Từ đúng" (`nil` = hợp lệ) — CÙNG luật với sheet thêm từ điển
    /// (`DictionaryFormValidation`: không rỗng, ≤ `maxLen` ký tự). Rỗng cũng là lỗi vì không có gì
    /// để dạy; `existing: []` vì dạy từ ĐÃ CÓ là gộp thêm cách nói, không phải trùng.
    public static func termError(_ term: String) -> String? {
        if term.trimmingCharacters(in: .whitespaces).isEmpty { return "Chưa nhập từ đúng cần dạy." }
        return DictionaryFormValidation.error(term: term, spokenLines: ["a"], existing: [], originalTerm: nil)
    }

    /// Chữ "nghe ra" dùng được từ một phản hồi `/v1/teach`; `nil` ⇒ engine không nghe ra gì (im lặng
    /// hoặc chỉ ký hiệu) — sheet báo lỗi thật, KHÔNG thêm dòng rỗng vào danh sách.
    public static func acceptHeard(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, hasWordCharacter(t) else { return nil }
        return t
    }

    /// Cách nói sẽ lưu = ứng viên TRỪ những cái người dùng đã bỏ chọn (`deselected` giữ khoá đã chuẩn
    /// hoá). Lưu tập BỎ CHỌN thay vì tập ĐÃ CHỌN để lần nghe mới thêm vào không vô tình chọn lại cái
    /// người dùng đã bỏ.
    public static func selected(candidates: [String], deselected: Set<String>) -> [String] {
        candidates.filter { !deselected.contains(normalize($0)) }
    }

    /// Thêm/gộp `term` (cách nói = `selectedVariants`, đã người dùng xác nhận chọn) vào danh sách từ
    /// điển ĐÃ ĐỌC LẠI gần nhất — tái dùng NGUYÊN `DictionaryPlanner`/`DictionaryValidation` (không
    /// viết luật riêng, nên không bao giờ lệch luật engine): đã có mục `term` ⇒ gộp thêm biến thể
    /// MỚI (bỏ trùng với cách nói đã có, giữ thứ tự); tổng vượt `maxSpoken` ⇒ LỖI rõ ràng (không âm
    /// thầm bỏ bớt cách nói người dùng đã chọn rồi báo "đã lưu"); chưa có ⇒ tạo mục mới kind "term".
    public static func apply(term: String, selectedVariants: [String], to current: [DictionaryEntry]) -> Result<[DictionaryEntry], DictionaryValidationError> {
        let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
        guard !trimmedTerm.isEmpty else { return .failure(.init("Chưa nhập thuật ngữ")) }
        guard !selectedVariants.isEmpty else { return .failure(.init("Chưa chọn cách nói nào để lưu")) }
        var next = current
        let normalizedTerm = normalize(trimmedTerm)
        if let idx = next.firstIndex(where: { normalize($0.term) == normalizedTerm }) {
            var spoken = next[idx].spoken
            var seen = Set(spoken.map(normalize))
            for v in selectedVariants {
                let key = normalize(v)
                guard !key.isEmpty, !seen.contains(key) else { continue }
                spoken.append(v)
                seen.insert(key)
            }
            if spoken.count > DictionaryValidation.maxSpoken {
                return .failure(.init("\"\(next[idx].term)\" chỉ chứa tối đa \(DictionaryValidation.maxSpoken) cách nói — bỏ chọn bớt hoặc xoá bớt cách nói cũ trong từ điển rồi lưu lại."))
            }
            next[idx].spoken = spoken
        } else {
            var seen = Set<String>()
            let unique = selectedVariants.filter { v in
                let key = normalize(v)
                return !key.isEmpty && seen.insert(key).inserted
            }
            next.append(DictionaryEntry(term: trimmedTerm, spoken: unique))
        }
        switch DictionaryValidation.validate(next) {
        case .success: return .success(next)
        case .failure(let e): return .failure(e)
        }
    }
}
