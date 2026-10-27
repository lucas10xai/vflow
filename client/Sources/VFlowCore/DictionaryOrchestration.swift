import Foundation

/// Mẫu đọc-sửa-ghi chung cho `/v1/dictionary`: đọc lại ngay trước khi ghi để không đè thay đổi
/// khác (của engine hoặc một cửa sổ vflow khác). `get`/`put` được tiêm vào để test được không cần
/// mạng thật; lớp AppKit truyền closure gọi `EngineAPI` + `URLSession` thật.
public enum DictionaryOrchestration {
    public static func applyChange(
        _ change: DictionaryChange,
        get: @Sendable () async -> Result<[DictionaryEntry], ClientError>,
        put: @Sendable ([DictionaryEntry]) async -> Result<[DictionaryEntry], ClientError>
    ) async -> Result<[DictionaryEntry], ClientError> {
        switch await get() {
        case .failure(let e): return .failure(e)
        case .success(let current):
            switch DictionaryPlanner.apply(change, to: current) {
            case .failure(let e): return .failure(.dictionaryInvalid(e.message))
            case .success(let next): return await put(next)
            }
        }
    }

    public static func acceptSuggestion(
        _ suggestion: CorrectionSuggestion,
        get: @Sendable () async -> Result<[DictionaryEntry], ClientError>,
        put: @Sendable ([DictionaryEntry]) async -> Result<[DictionaryEntry], ClientError>
    ) async -> Result<[DictionaryEntry], ClientError> {
        switch await get() {
        case .failure(let e): return .failure(e)
        case .success(let current):
            switch DictionaryPlanner.mergeSuggestion(suggestion, into: current) {
            case .failure(let e): return .failure(.dictionaryInvalid(e.message))
            case .success(let next): return await put(next)
            }
        }
    }

    /// "Dạy từ bằng giọng" (V3, tab Từ điển): đọc-sửa-ghi giống `applyChange`, nhưng dùng
    /// `TeachWordVariants.apply` (gộp biến thể vào mục có sẵn, hoặc tạo mục mới) thay vì
    /// `DictionaryPlanner` — xem `TeachWordSheet`.
    public static func applyTeachWord(
        term: String, selectedVariants: [String],
        get: @Sendable () async -> Result<[DictionaryEntry], ClientError>,
        put: @Sendable ([DictionaryEntry]) async -> Result<[DictionaryEntry], ClientError>
    ) async -> Result<[DictionaryEntry], ClientError> {
        switch await get() {
        case .failure(let e): return .failure(e)
        case .success(let current):
            switch TeachWordVariants.apply(term: term, selectedVariants: selectedVariants, to: current) {
            case .failure(let e): return .failure(.dictionaryInvalid(e.message))
            case .success(let next): return await put(next)
            }
        }
    }
}
