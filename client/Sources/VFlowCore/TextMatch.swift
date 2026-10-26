import Foundation

/// Chuẩn hoá tiếng Việt để so khớp — tương ứng `fold()`/`normalizeMatch()` ở `engine/post/text.js`
/// (bỏ dấu thanh, hoa→thường, giữ â/ă/ê/ô/ơ/ư/đ; bỏ dấu câu, gộp khoảng trắng). Dùng để kiểm trùng
/// trigger snippets phía client TRƯỚC khi gửi engine — engine vẫn là nơi quyết định cuối cùng.
public enum VietnameseMatch {
    /// Dấu thanh ở dạng NFD: huyền, sắc, ngã, hỏi, nặng (U+0300,0301,0303,0309,0323).
    private static let toneMarks: Set<UInt32> = [0x0300, 0x0301, 0x0303, 0x0309, 0x0323]

    public static func fold(_ s: String) -> String {
        let decomposed = s.decomposedStringWithCanonicalMapping
        var scalars = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars where !toneMarks.contains(scalar.value) {
            scalars.append(scalar)
        }
        return String(scalars).precomposedStringWithCanonicalMapping.lowercased()
    }

    public static func normalizeMatch(_ s: String) -> String {
        let folded = fold(s)
        var out = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            out.append(CharacterSet.punctuationCharacters.contains(scalar) ? " " : scalar)
        }
        return String(out).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
