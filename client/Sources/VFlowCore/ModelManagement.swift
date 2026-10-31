import Foundation

/// Thông tin TĨNH về một model đã biết — dùng để hiện "đánh đổi thật" ở màn hình chọn model (Cài đặt ›
/// Nâng cao). Số liệu lấy từ `eval/reports/2026-10-30-multilingual.md` (đo bằng giọng TỔNG HỢP, KHÔNG
/// phải giọng người dùng thật — mọi nơi hiện các số này PHẢI kèm `measuredCaveat`) và từ
/// `engine/stt/registry.js` (tên/giấy phép/nguồn — client không đọc file đó qua mạng, chỉ chép lại sự
/// thật ĐÃ CÔNG BỐ, giống cách `ModelDownloadInfo` làm từ trước cho riêng `zipformer-vi-30m`). Model
/// KHÔNG có trong danh sách này (vd. một id mới engine thêm sau) hiện bằng dữ liệu sống từ
/// `/v1/models` (ngôn ngữ, đã tải/chưa) + nhãn "chưa có thông tin đánh đổi" — KHÔNG bịa số.
public struct ModelCatalogEntry: Equatable, Sendable {
    public var title: String
    public var licenseName: String
    public var licenseSummary: String
    public var licenseURL: String?
    public var homepageURL: String?
    public var downloadSizeText: String
    /// Một dòng đánh đổi ngắn, vd "Chỉ tiếng Việt · nhanh nhất · 33 MB · chỉ dùng cá nhân".
    public var tradeoffLine: String
    /// Cảnh báo nguồn số đo — LUÔN hiện cạnh `tradeoffLine` ở UI.
    public var measuredCaveat: String

    public init(title: String, licenseName: String, licenseSummary: String, licenseURL: String?,
                homepageURL: String?, downloadSizeText: String, tradeoffLine: String, measuredCaveat: String) {
        self.title = title
        self.licenseName = licenseName
        self.licenseSummary = licenseSummary
        self.licenseURL = licenseURL
        self.homepageURL = homepageURL
        self.downloadSizeText = downloadSizeText
        self.tradeoffLine = tradeoffLine
        self.measuredCaveat = measuredCaveat
    }
}

public enum ModelCatalog {
    public static let entries: [String: ModelCatalogEntry] = [
        "zipformer-vi-30m": ModelCatalogEntry(
            title: "Zipformer-30M-RNNT-6000h (sherpa-onnx, int8)",
            licenseName: "CC-BY-NC-ND-4.0",
            licenseSummary: "Chỉ dùng cá nhân, phi thương mại; không phát hành lại bản sửa đổi.",
            licenseURL: "https://creativecommons.org/licenses/by-nc-nd/4.0/",
            homepageURL: "https://huggingface.co/hynt/Zipformer-30M-RNNT-6000h",
            downloadSizeText: "33 MB trên đĩa (≈26 MB tải về)",
            tradeoffLine: "Chỉ tiếng Việt · nhanh nhất (~0,1 s mỗi câu) · ~270 MB bộ nhớ · 33 MB · chỉ dùng cá nhân",
            measuredCaveat: "Đo bằng giọng tổng hợp (macOS \u{201C}say\u{201D}), chưa phải giọng người dùng thật."),
        "whisper-tiny-multilingual": ModelCatalogEntry(
            title: "Whisper tiny đa ngôn ngữ (sherpa-onnx, CPU)",
            licenseName: "MIT",
            licenseSummary: "Giấy phép MIT (OpenAI Whisper) — dùng thương mại được.",
            licenseURL: "https://github.com/openai/whisper/blob/main/LICENSE",
            homepageURL: "https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/tiny.html",
            downloadSizeText: "~111 MB",
            tradeoffLine: "Việt + nhiều ngôn ngữ · nhẹ nhưng đo thử KÉM hơn cả model tiếng Việt thuần ở câu xen tiếng Anh (dễ nhận nhầm sang ngôn ngữ khác) · ~111 MB · giấy phép MIT",
            measuredCaveat: "Đo bằng giọng tổng hợp (macOS \u{201C}say\u{201D}): WER sau xử lý 46,6% trên bộ 36 câu trộn — cao hơn cả model tiếng Việt thuần (40,75%). Chưa đo bằng giọng người dùng thật."),
        // Id THẬT trong `engine/stt/registry.js` là "whisper-small-multilingual" (thêm 2026-10-31,
        // SAU báo cáo đo 2026-10-30 vốn gọi tắt "whisper-small") — khớp id này, KHÔNG dùng "whisper-small"
        // trần, nếu không màn hình chọn model sẽ không gắn được chữ đánh đổi cho đúng model đang tải.
        "whisper-small-multilingual": ModelCatalogEntry(
            title: "Whisper small đa ngôn ngữ (sherpa-onnx, CPU)",
            licenseName: "MIT",
            licenseSummary: "Giấy phép MIT (OpenAI Whisper) — dùng thương mại được.",
            licenseURL: "https://github.com/openai/whisper/blob/main/LICENSE",
            homepageURL: "https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/small.html",
            downloadSizeText: "610 MB",
            tradeoffLine: "Việt + Anh · chậm hơn (~1,2 s cho câu 10 giây) · cần ~1 GB bộ nhớ · 610 MB · giấy phép MIT",
            measuredCaveat: "Đo bằng giọng tổng hợp (macOS \u{201C}say\u{201D}): WER tiếng Việt thuần 9,6%, tiếng Anh thuần 2,5%, Việt xen Anh 50,0%. Chưa đo bằng giọng người dùng thật."),
        "whisper-base-multilingual": ModelCatalogEntry(
            title: "Whisper base đa ngôn ngữ (sherpa-onnx, CPU)",
            licenseName: "MIT",
            licenseSummary: "Giấy phép MIT (OpenAI Whisper) — dùng thương mại được.",
            licenseURL: "https://github.com/openai/whisper/blob/main/LICENSE",
            homepageURL: "https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/base.html",
            downloadSizeText: "198 MB",
            tradeoffLine: "Việt + Anh · nhẹ hơn small nhưng kém hơn ở câu Việt xen Anh (WER thô ~76% nhóm xen ngôn ngữ ngắn) · ~580 MB bộ nhớ · 198 MB · giấy phép MIT",
            measuredCaveat: "Đo bằng giọng tổng hợp (macOS \u{201C}say\u{201D}): WER tiếng Việt thuần 17,3%, tiếng Anh thuần 2,5% — số đo THÔ qua sherpa-onnx trực tiếp, chưa qua từ điển/hậu xử lý của engine. Chưa đo bằng giọng người dùng thật."),
    ]

    public static func entry(for id: String) -> ModelCatalogEntry? { entries[id] }
}

/// Trạng thái sẵn-có của MỘT model, suy từ `loaded`/`reason` do `/healthz`|`/v1/models` trả
/// (contract/engine-api.md mục GET /healthz) — KHÔNG đoán khi gặp `reason` lạ.
public enum ModelAvailability: Equatable, Sendable {
    /// Đã nạp vào bộ nhớ engine, dùng được ngay.
    case loaded
    /// Model cục bộ: tệp đã tải đủ (`reason:"not_loaded"`) nhưng chưa nạp — nạp lúc dùng lần đầu.
    case downloadedNotLoaded
    /// Chưa tải (`not_downloaded`) hoặc bị chặn tải vì thiếu checksum đã xác minh (`checksum_unverified`).
    case notDownloaded(reason: String)
    /// Có tệp (hoặc từng có) nhưng lần nạp gần nhất lỗi (lý do khác các mã đã biết ở trên).
    case loadFailed(reason: String)
    /// Model từ xa (`kind != "local"`, vd PhoWhisper qua SSH tunnel) — không có khái niệm "tải".
    case remoteUnavailable(reason: String)

    /// `true` ⇒ có tệp model trên đĩa (dùng để quyết định hiện nút "Xoá" thay vì "Tải").
    public var isDownloaded: Bool {
        switch self {
        case .loaded, .downloadedNotLoaded, .loadFailed: true
        case .notDownloaded, .remoteUnavailable: false
        }
    }

    /// Nhãn trạng thái tiếng Việt cho UI.
    public var statusText: String {
        switch self {
        case .loaded: "Sẵn sàng"
        case .downloadedNotLoaded: "Đã tải, chưa nạp"
        case .notDownloaded(let reason): reason == "checksum_unverified" ? "Chưa tải — chưa có mã băm đã xác minh" : "Chưa tải"
        case .loadFailed(let reason): "Lỗi nạp (\(reason))"
        case .remoteUnavailable(let reason): "Không kết nối được (\(reason))"
        }
    }
}

public enum ModelAvailabilityResolver {
    public static func resolve(kind: String, loaded: Bool, reason: String?) -> ModelAvailability {
        guard kind == "local" else { return .remoteUnavailable(reason: reason ?? "không rõ lý do") }
        if loaded { return .loaded }
        switch reason {
        case "not_loaded": return .downloadedNotLoaded
        case "not_downloaded", "checksum_unverified": return .notDownloaded(reason: reason ?? "not_downloaded")
        default: return .loadFailed(reason: reason ?? "không rõ lý do")
        }
    }
}

/// Một dòng trong màn hình chọn model — gộp dữ liệu SỐNG (`/v1/models`) với thông tin TĨNH
/// (`ModelCatalog`) và lựa chọn hiện tại của người dùng (client-local, xem `AppController.selectedModelID`).
public struct ModelPickerRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var availability: ModelAvailability
    public var languages: [String]
    public var autoDetect: Bool
    public var catalog: ModelCatalogEntry?
    /// Người dùng đã CHỌN THẲNG model này (khác với "đang nạp trong bộ nhớ engine", xem `isInUse`).
    public var isSelected: Bool

    public init(id: String, kind: String, availability: ModelAvailability, languages: [String],
                autoDetect: Bool, catalog: ModelCatalogEntry?, isSelected: Bool) {
        self.id = id
        self.kind = kind
        self.availability = availability
        self.languages = languages
        self.autoDetect = autoDetect
        self.catalog = catalog
        self.isSelected = isSelected
    }

    /// "Đang dùng" theo nghĩa rộng cho mục đích KHOÁ XOÁ: người dùng đã chọn thẳng, HOẶC engine đang
    /// giữ model này trong bộ nhớ (có thể do dùng trước khi có lựa chọn tường minh) — xoá tệp dưới một
    /// model đang nạp là rủi ro không cần thiết.
    public var isInUse: Bool { isSelected || availability == .loaded }
}

public enum ModelPickerBuilder {
    /// `models`: nguyên trạng `/v1/models`/`/healthz`. `selectedID`: lựa chọn hiện tại của client
    /// (`nil` = chưa chọn thẳng, đang dùng mặc định của engine).
    public static func rows(models: [ModelStatus], selectedID: String?) -> [ModelPickerRow] {
        models.map { m in
            ModelPickerRow(
                id: m.id, kind: m.kind,
                availability: ModelAvailabilityResolver.resolve(kind: m.kind, loaded: m.loaded, reason: m.reason),
                languages: m.languages ?? ["vi"], autoDetect: m.autoDetect ?? false,
                catalog: ModelCatalog.entry(for: m.id),
                isSelected: selectedID != nil && selectedID == m.id)
        }
    }

    /// Xoá được KHI VÀ CHỈ KHI: có tệp trên đĩa, KHÔNG phải model đang dùng (xem `isInUse`).
    public static func canDelete(_ row: ModelPickerRow) -> Bool {
        row.availability.isDownloaded && !row.isInUse
    }

    /// Tải được KHI VÀ CHỈ KHI: model cục bộ, chưa có tệp, và không bị chặn vì thiếu checksum.
    public static func canDownload(_ row: ModelPickerRow) -> Bool {
        if case .notDownloaded(let reason) = row.availability, row.kind == "local" { return reason != "checksum_unverified" }
        return false
    }
}

/// Xoá model đã tải — vận hành thuần trên hệ tệp (KHÔNG có endpoint HTTP xoá model trong hợp đồng;
/// `vflow models pull` cũng chỉ TẢI, xem contract/engine-api.md mục "Model cục bộ"). Dùng chung FS giả
/// với `ModelBootstrap` để test không đụng đĩa thật.
public enum ModelDeletion {
    public enum Error: Swift.Error, Equatable, Sendable {
        case inUse
        case notFound
        case failed(String)
    }

    /// Kiểm TRƯỚC khi xoá — cùng luật với `ModelPickerBuilder.canDelete`, nhưng nhận trực tiếp id +
    /// id đang dùng/đang nạp (dùng ở lớp gọi HTTP/FS, không cần dựng cả `ModelPickerRow`).
    public static func guardDelete(id: String, selectedID: String?, loadedIDs: Set<String>) -> Error? {
        if selectedID == id || loadedIDs.contains(id) { return .inUse }
        return nil
    }

    public static func delete(modelsDir: String, id: String, fs: ModelBootstrap.FS) -> Result<Void, Error> {
        let dir = modelsDir + "/" + id
        guard fs.fileExists(dir) else { return .failure(.notFound) }
        do {
            try fs.removeItem(dir)
        } catch {
            return .failure(.failed("\(error)"))
        }
        return .success(())
    }
}

/// Điều phối tải: CHỈ một model được tải cùng lúc (yêu cầu nhiệm vụ "điều phối tải một lần một") —
/// hàm thuần để test, lớp gọi (ViewModel) giữ `activeID` làm nguồn sự thật.
public enum ModelDownloadCoordination {
    /// `true` ⇒ được phép bắt đầu tải `requestedID` (không có tải nào khác đang chạy, hoặc đang tải
    /// ĐÚNG model này — vd bấm lại sau khi lỗi).
    public static func canStart(activeID: String?, requestedID: String) -> Bool {
        activeID == nil || activeID == requestedID
    }
}

/// Cảnh báo trung thực khi model đang dùng là Whisper (contract mục đo đa ngôn ngữ, báo cáo
/// `eval/reports/2026-10-30-multilingual.md`): từ điển phiên âm sửa đúng 2/36 câu thử với model hiện
/// tại (zipformer) nhưng 0/36 với Whisper — lỗi của Whisper ở các câu đó không CÙNG DẠNG phiên âm gần
/// mà từ điển được thiết kế để bắt (nhận nhầm ngôn ngữ/lặp vô nghĩa). Pane engine (F1) đang cải thiện.
public enum DictionaryEffectivenessCaveat {
    public static func appliesTo(modelID: String?) -> Bool {
        guard let modelID else { return false }
        return modelID.hasPrefix("whisper")
    }

    public static let text = "Từ điển cá nhân (phiên âm) có thể kém hiệu quả hơn với model Whisper — đo thử cho thấy từ điển sửa đúng 2/36 câu với model hiện tại nhưng 0/36 với Whisper (đang được cải thiện)."
}

public enum ModelDeletionText {
    public static func message(_ error: ModelDeletion.Error) -> String {
        switch error {
        case .inUse: return "Không xoá được — đây là model đang dùng. Đổi sang model khác trước rồi xoá."
        case .notFound: return "Model này chưa có tệp trên đĩa (có thể đã bị xoá từ nơi khác)."
        case .failed(let detail): return "Không xoá được model: \(detail)"
        }
    }
}

/// Khả năng ngôn ngữ của model NGƯỜI DÙNG ĐANG DÙNG (contract mục "Tuỳ chọn ngôn ngữ nói"). Trước khi
/// có màn hình chọn model, suy từ "model đầu tiên đã nạp" (`Health.languages/autoDetect`) là đủ vì CHỈ
/// một model từng được nạp trong một phiên. Từ khi người dùng chọn thẳng model (có thể nhiều model
/// cùng nạp trong engine — `ensure()` không giải phóng model cũ), phải tra THEO ĐÚNG id đã chọn, không
/// phải "model đầu tiên nạp được" (có thể là model CŨ còn sót trong bộ nhớ) — nếu không, khoá/mở tuỳ
/// chọn ngôn ngữ sẽ sai sau khi đổi model.
public enum EngineLanguageResolution {
    public static func resolve(models: [ModelStatus], selectedID: String?,
                               fallbackLanguages: [String]?, fallbackAutoDetect: Bool?) -> (languages: [String]?, autoDetect: Bool?) {
        if let id = selectedID, let m = models.first(where: { $0.id == id }) {
            return (m.languages, m.autoDetect)
        }
        return (fallbackLanguages, fallbackAutoDetect)
    }
}
