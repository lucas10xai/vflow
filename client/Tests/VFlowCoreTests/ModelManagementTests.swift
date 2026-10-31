import Foundation
import Testing
@testable import VFlowCore

// F2: màn hình chọn model (Cài đặt › Nâng cao) — giải mã danh sách model, khoá/mở tuỳ chọn ngôn ngữ
// theo model đang dùng, không cho xoá model đang dùng, điều phối tải một lần một, chữ đánh đổi đúng
// theo dữ liệu model. Dùng Swift Testing (@Suite/@Test/#expect), KHÔNG đụng đĩa thật ngoài thư mục tạm.

private func json(_ s: String) -> Data { Data(s.utf8) }

@Suite struct ModelListDecodingTests {
    @Test func giảiMãDanhSáchModelĐầyĐủTrường() throws {
        let body = json(#"""
        {"models":[
          {"id":"zipformer-vi-30m","kind":"local","loaded":true,"languages":["vi"],"auto_detect":false},
          {"id":"whisper-tiny-multilingual","kind":"local","loaded":false,"reason":"not_downloaded","languages":["vi","en"],"auto_detect":true},
          {"id":"phowhisper-large","kind":"remote","loaded":false,"reason":"tunnel_down"}
        ]}
        """#)
        let models = try EngineAPI.parseModelList(status: 200, data: body).get()
        #expect(models.count == 3)
        #expect(models[0].loaded && models[0].languages == ["vi"])
        #expect(models[1].reason == "not_downloaded")
        #expect(models[2].kind == "remote")
    }

    /// Model LẠ (thiếu `languages`/`auto_detect`, chưa biết tới) vẫn giải mã được — KHÔNG được làm hỏng
    /// cả danh sách vì một mục thiếu trường tuỳ chọn.
    @Test func modelLạThiếuTrườngTuỳChọnVẫnGiảiMãĐược() throws {
        let body = json(#"{"models":[{"id":"model-tuong-lai","kind":"local","loaded":false,"reason":"not_downloaded"}]}"#)
        let models = try EngineAPI.parseModelList(status: 200, data: body).get()
        #expect(models.count == 1)
        #expect(models[0].languages == nil && models[0].autoDetect == nil)
    }

    /// Mục THIẾU `id` (hỏng) bị bỏ qua, không làm hỏng các mục còn lại (cùng luật `parseHealth`).
    @Test func mụcThiếuIdBịBỏQua() throws {
        let body = json(#"{"models":[{"kind":"local","loaded":true},{"id":"ok","kind":"local","loaded":true}]}"#)
        let models = try EngineAPI.parseModelList(status: 200, data: body).get()
        #expect(models.count == 1 && models[0].id == "ok")
    }

    @Test func thiếuTrườngModelsLàLỗi() {
        let r = EngineAPI.parseModelList(status: 200, data: json("{}"))
        guard case .failure(.badResponse) = r else { Issue.record("phải là badResponse"); return }
    }

    @Test func lỗi401ThànhClientErrorEngine() {
        let r = EngineAPI.parseModelList(status: 401, data: json(#"{"error":{"code":"unauthorized","message":"Thiếu token."}}"#))
        guard case .failure(.engine(401, "unauthorized", _)) = r else { Issue.record("phải là lỗi unauthorized"); return }
    }

    @Test func requestĐúngURLVàToken() {
        let r = EngineAPI.modelsRequest(port: 7611, token: "abc")
        #expect(r.url?.absoluteString == "http://127.0.0.1:7611/v1/models")
        #expect(r.httpMethod == "GET")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }
}

@Suite struct ModelAvailabilityTests {
    @Test func đãNạpLàLoaded() {
        #expect(ModelAvailabilityResolver.resolve(kind: "local", loaded: true, reason: nil) == .loaded)
    }

    @Test func đãTảiChưaNạp() {
        #expect(ModelAvailabilityResolver.resolve(kind: "local", loaded: false, reason: "not_loaded") == .downloadedNotLoaded)
    }

    @Test func chưaTảiVàBịChặnChecksum() {
        #expect(ModelAvailabilityResolver.resolve(kind: "local", loaded: false, reason: "not_downloaded") == .notDownloaded(reason: "not_downloaded"))
        #expect(ModelAvailabilityResolver.resolve(kind: "local", loaded: false, reason: "checksum_unverified") == .notDownloaded(reason: "checksum_unverified"))
    }

    @Test func lýDoLạLàLoadFailedKhôngPhảiChưaTải() {
        // "load_failed"/lý do lạ ⇒ CÓ tệp trên đĩa nhưng nạp lỗi — KHÁC "chưa tải" (không gợi ý tải lại
        // vô ích, không giả vờ là chưa có tệp).
        let a = ModelAvailabilityResolver.resolve(kind: "local", loaded: false, reason: "load_failed")
        #expect(a == .loadFailed(reason: "load_failed"))
        #expect(a.isDownloaded)
    }

    @Test func modelTừXaKhôngCóKháiNiệmTải() {
        let a = ModelAvailabilityResolver.resolve(kind: "remote", loaded: false, reason: "tunnel_down")
        #expect(a == .remoteUnavailable(reason: "tunnel_down"))
        #expect(!a.isDownloaded)
    }

    @Test func downloadedTrueChỉKhiCóTệp() {
        #expect(ModelAvailability.loaded.isDownloaded)
        #expect(ModelAvailability.downloadedNotLoaded.isDownloaded)
        #expect(!ModelAvailability.notDownloaded(reason: "x").isDownloaded)
        #expect(!ModelAvailability.remoteUnavailable(reason: "x").isDownloaded)
    }
}

@Suite struct ModelPickerRowTests {
    private func status(_ id: String, kind: String = "local", loaded: Bool, reason: String? = nil,
                        languages: [String]? = ["vi"], autoDetect: Bool? = false) -> ModelStatus {
        ModelStatus(id: id, kind: kind, loaded: loaded, reason: reason, languages: languages, autoDetect: autoDetect)
    }

    @Test func rowsGắnCatalogTheoId() {
        let rows = ModelPickerBuilder.rows(models: [status("zipformer-vi-30m", loaded: true)], selectedID: nil)
        #expect(rows[0].catalog?.title.contains("Zipformer") == true)
        #expect(!rows[0].isSelected)
    }

    @Test func modelLạKhôngCóCatalogVẫnRaRow() {
        let rows = ModelPickerBuilder.rows(models: [status("model-tuong-lai", loaded: false, reason: "not_downloaded")], selectedID: nil)
        #expect(rows[0].catalog == nil)
    }

    @Test func isSelectedChỉKhiĐúngId() {
        let rows = ModelPickerBuilder.rows(models: [status("a", loaded: true), status("b", loaded: false, reason: "not_loaded")], selectedID: "b")
        #expect(!rows[0].isSelected && rows[1].isSelected)
    }

    // BẤT BIẾN: không cho xoá model đang dùng (nhiệm vụ F2, mục 1). "Đang dùng" = người dùng đã chọn
    // THẲNG (isSelected) HOẶC engine đang giữ model đó trong bộ nhớ (loaded == true) — xoá tệp dưới một
    // model đang nạp là rủi ro không cần thiết, dù người dùng chưa từng chọn thẳng nó.
    @Test func khôngChoXoáModelĐãChọn() {
        let row = ModelPickerRow(id: "a", kind: "local", availability: .downloadedNotLoaded, languages: ["vi"],
                                 autoDetect: false, catalog: nil, isSelected: true)
        #expect(!ModelPickerBuilder.canDelete(row))
    }

    @Test func khôngChoXoáModelĐangNạpDùChưaChọnThẳng() {
        let row = ModelPickerRow(id: "a", kind: "local", availability: .loaded, languages: ["vi"],
                                 autoDetect: false, catalog: nil, isSelected: false)
        #expect(!ModelPickerBuilder.canDelete(row))
    }

    @Test func choXoáModelĐãTảiKhôngĐangDùng() {
        let row = ModelPickerRow(id: "a", kind: "local", availability: .downloadedNotLoaded, languages: ["vi"],
                                 autoDetect: false, catalog: nil, isSelected: false)
        #expect(ModelPickerBuilder.canDelete(row))
    }

    @Test func khôngChoXoáModelChưaTải() {
        let row = ModelPickerRow(id: "a", kind: "local", availability: .notDownloaded(reason: "not_downloaded"),
                                 languages: ["vi"], autoDetect: false, catalog: nil, isSelected: false)
        #expect(!ModelPickerBuilder.canDelete(row))
    }

    @Test func choTảiKhiChưaTảiVàKhôngBịChặnChecksum() {
        let row = ModelPickerRow(id: "a", kind: "local", availability: .notDownloaded(reason: "not_downloaded"),
                                 languages: ["vi"], autoDetect: false, catalog: nil, isSelected: false)
        #expect(ModelPickerBuilder.canDownload(row))
    }

    @Test func khôngChoTảiKhiThiếuChecksumĐãXácMinh() {
        let row = ModelPickerRow(id: "a", kind: "local", availability: .notDownloaded(reason: "checksum_unverified"),
                                 languages: ["vi"], autoDetect: false, catalog: nil, isSelected: false)
        #expect(!ModelPickerBuilder.canDownload(row))
    }

    @Test func khôngChoTảiModelTừXa() {
        let row = ModelPickerRow(id: "a", kind: "remote", availability: .remoteUnavailable(reason: "tunnel_down"),
                                 languages: [], autoDetect: false, catalog: nil, isSelected: false)
        #expect(!ModelPickerBuilder.canDownload(row))
    }

    @Test func khôngChoTảiModelĐãTảiRồi() {
        let row = ModelPickerRow(id: "a", kind: "local", availability: .loaded, languages: ["vi"],
                                 autoDetect: false, catalog: nil, isSelected: false)
        #expect(!ModelPickerBuilder.canDownload(row))
    }
}

@Suite struct ModelDownloadCoordinationTests {
    @Test func khôngCóGìĐangTảiThìChoBắtĐầu() {
        #expect(ModelDownloadCoordination.canStart(activeID: nil, requestedID: "a"))
    }

    // BẤT BIẾN: điều phối tải một lần một — đang tải model khác thì KHÔNG cho bắt đầu tải thêm.
    @Test func đangTảiModelKhácThìChặn() {
        #expect(!ModelDownloadCoordination.canStart(activeID: "a", requestedID: "b"))
    }

    @Test func đangTảiĐúngModelThìChoThửLại() {
        #expect(ModelDownloadCoordination.canStart(activeID: "a", requestedID: "a"))
    }
}

@Suite struct ModelDeletionTests {
    private final class Sandbox {
        let root: String
        init() {
            root = NSTemporaryDirectory() + "model-del-test-" + UUID().uuidString
            try! FileManager.default.createDirectory(atPath: root + "/models/a", withIntermediateDirectories: true)
            try! Data("x".utf8).write(to: URL(fileURLWithPath: root + "/models/a/manifest.json"))
        }
        deinit { try? FileManager.default.removeItem(atPath: root) }
    }

    @Test func xoáThànhCôngKhiKhôngĐangDùng() {
        let s = Sandbox()
        #expect(ModelDeletion.guardDelete(id: "a", selectedID: nil, loadedIDs: []) == nil)
        let r = ModelDeletion.delete(modelsDir: s.root + "/models", id: "a", fs: .live)
        guard case .success = r else { Issue.record("phải xoá được"); return }
        #expect(!FileManager.default.fileExists(atPath: s.root + "/models/a"))
    }

    // BẤT BIẾN (nhiệm vụ F2, mục 1): KHÔNG cho xoá model đang dùng — kiểm ở lớp FS (không chỉ ở UI).
    @Test func chặnXoáKhiĐangChọnThẳng() {
        #expect(ModelDeletion.guardDelete(id: "a", selectedID: "a", loadedIDs: []) == .inUse)
    }

    @Test func chặnXoáKhiEngineĐangNạp() {
        #expect(ModelDeletion.guardDelete(id: "a", selectedID: nil, loadedIDs: ["a"]) == .inUse)
    }

    @Test func xoáModelKhôngCóTệpLàNotFound() {
        let s = Sandbox()
        let r = ModelDeletion.delete(modelsDir: s.root + "/models", id: "khong-ton-tai", fs: .live)
        guard case .failure(.notFound) = r else { Issue.record("phải là notFound"); return }
    }
}

@Suite struct EngineLanguageResolutionTests {
    private func status(_ id: String, loaded: Bool, languages: [String], autoDetect: Bool) -> ModelStatus {
        ModelStatus(id: id, kind: "local", loaded: loaded, reason: loaded ? nil : "not_loaded", languages: languages, autoDetect: autoDetect)
    }

    // BẤT BIẾN (nhiệm vụ F2, mục 2): sau khi người dùng CHỌN THẲNG một model, khả năng ngôn ngữ phải
    // tra THEO ĐÚNG model đó — KHÔNG phải "model đầu tiên đã nạp" (có thể là model CŨ còn sót lại trong
    // bộ nhớ engine vì `ensure()` không giải phóng model cũ khi đổi model).
    @Test func trảĐúngModelĐãChọnDùModelKhácNạpTrước() {
        let models = [status("zipformer-vi-30m", loaded: true, languages: ["vi"], autoDetect: false),
                      status("whisper-tiny-multilingual", loaded: true, languages: ["vi", "en"], autoDetect: true)]
        let r = EngineLanguageResolution.resolve(models: models, selectedID: "whisper-tiny-multilingual",
                                                 fallbackLanguages: ["vi"], fallbackAutoDetect: false)
        #expect(r.languages == ["vi", "en"] && r.autoDetect == true)
    }

    @Test func chưaChọnThẳngThìDùngFallback() {
        let models = [status("zipformer-vi-30m", loaded: true, languages: ["vi"], autoDetect: false)]
        let r = EngineLanguageResolution.resolve(models: models, selectedID: nil, fallbackLanguages: ["vi"], fallbackAutoDetect: false)
        #expect(r.languages == ["vi"] && r.autoDetect == false)
    }

    @Test func đãChọnNhưngModelĐóKhôngCóTrongDanhSáchThìDùngFallback() {
        let models = [status("a", loaded: true, languages: ["vi"], autoDetect: false)]
        let r = EngineLanguageResolution.resolve(models: models, selectedID: "khong-ton-tai", fallbackLanguages: ["vi"], fallbackAutoDetect: false)
        #expect(r.languages == ["vi"] && r.autoDetect == false)
    }
}

@Suite struct DictionaryEffectivenessCaveatTests {
    @Test func hiệnVớiModelWhisper() {
        #expect(DictionaryEffectivenessCaveat.appliesTo(modelID: "whisper-small"))
        #expect(DictionaryEffectivenessCaveat.appliesTo(modelID: "whisper-tiny-multilingual"))
    }

    @Test func khôngHiệnVớiModelKhácHoặcChưaChọn() {
        #expect(!DictionaryEffectivenessCaveat.appliesTo(modelID: "zipformer-vi-30m"))
        #expect(!DictionaryEffectivenessCaveat.appliesTo(modelID: nil))
    }
}

@Suite struct ModelCatalogTextTests {
    // Chữ đánh đổi hiển thị PHẢI khớp đúng số đo trong eval/reports/2026-10-30-multilingual.md — test
    // này khoá đúng nguyên văn hai dòng ví dụ trong nhiệm vụ, tránh sửa nhầm/làm trôi số liệu sau này.
    @Test func chữĐánhĐổiZipformerKhớpVíDụNhiệmVụ() throws {
        let e = try #require(ModelCatalog.entry(for: "zipformer-vi-30m"))
        #expect(e.tradeoffLine == "Chỉ tiếng Việt · nhanh nhất (~0,1 s mỗi câu) · ~270 MB bộ nhớ · 33 MB · chỉ dùng cá nhân")
        #expect(e.licenseName == "CC-BY-NC-ND-4.0")
    }

    @Test func chữĐánhĐổiWhisperSmallKhớpVíDụNhiệmVụ() throws {
        let e = try #require(ModelCatalog.entry(for: "whisper-small-multilingual"))
        #expect(e.tradeoffLine == "Việt + Anh · chậm hơn (~1,2 s cho câu 10 giây) · cần ~1 GB bộ nhớ · 610 MB · giấy phép MIT")
        #expect(e.licenseName == "MIT")
    }

    @Test func mọiMụcTrongDanhMụcCóCảnhBáoNguồnSốĐo() {
        for (id, e) in ModelCatalog.entries {
            #expect(!e.measuredCaveat.isEmpty, "\(id) thiếu cảnh báo nguồn số đo")
        }
    }

    @Test func modelKhôngCóTrongDanhMụcTrảNil() {
        #expect(ModelCatalog.entry(for: "model-khong-ton-tai") == nil)
    }
}
