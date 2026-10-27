import Foundation

/// Quyết định lúc khởi động: model nhận dạng đã sẵn sàng chưa, có cần chép từ bundle không, hay phải
/// xin người dùng tải (O1). THUẦN + nhẹ: chỉ vài lệnh `stat` và đọc `manifest.json`, KHÔNG băm 33 MB
/// mỗi lần mở app (nên bản không kèm model chạy NGAY khi `~/.vflow/models/<id>` đã có, không đổi
/// trải nghiệm so với bản kèm model).
///
/// Thứ tự (khớp hành vi có từ M4b, `ModelBootstrap`): engine CHỈ đọc model ở `<VFLOW_HOME>/models/<id>`.
///  1. `<VFLOW_HOME>/models/<id>` đã đủ ⇒ dùng luôn, không đụng gì (KHÔNG BAO GIỜ bị bundle đè — người
///     dùng có thể đã tự cập nhật model).
///  2. Chưa có ở `VFLOW_HOME` nhưng bundle có ⇒ chép từ bundle (`ModelBootstrap`, nguyên tử + kiểm sha256).
///  3. Không có ở đâu (hoặc bản ở `VFLOW_HOME` thiếu tệp và không có thư mục để chép đè an toàn) ⇒
///     MỚI hiện màn hình xin tải (cần người dùng đồng ý giấy phép).
public enum ModelProvisioning {
    public static let modelID = "zipformer-vi-30m"
    /// Vai trò bắt buộc trong `manifest.json` để engine nạp được model (xem `engine/stt/models.js`).
    public static let requiredRoles = ["encoder", "decoder", "joiner", "tokens"]

    /// Trừu tượng hoá đĩa để test bằng thư mục thật/giả. Không đọc nội dung tệp model.
    public struct FS: Sendable {
        public var readData: @Sendable (String) -> Data?
        /// Kích thước tệp thường; nil nếu không có/không phải tệp.
        public var fileSize: @Sendable (String) -> Int?
        public init(readData: @escaping @Sendable (String) -> Data?, fileSize: @escaping @Sendable (String) -> Int?) {
            self.readData = readData
            self.fileSize = fileSize
        }

        public static let live = FS(
            readData: { FileManager.default.contents(atPath: $0) },
            fileSize: { path in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
                      let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? NSNumber else { return nil }
                return size.intValue
            })
    }

    public enum Presence: Equatable, Sendable {
        /// `manifest.json` hợp lệ và đủ 4 tệp (khác rỗng) — engine nạp được.
        case complete
        /// Có `manifest.json` nhưng hỏng/thiếu tệp. `String` = lý do cho người dùng.
        case incomplete(String)
        /// Không có `manifest.json`.
        case absent
    }

    /// `modelsDir` = `<VFLOW_HOME>/models` hoặc `<bundle>/Contents/Resources/models`.
    public static func inspect(modelsDir: String, modelID: String = modelID, fs: FS = .live) -> Presence {
        let dir = modelsDir + "/" + modelID
        guard let data = fs.readData(dir + "/manifest.json") else { return .absent }
        guard let manifest = ModelBootstrap.parseManifest(data) else { return .incomplete("manifest.json hỏng") }
        for role in requiredRoles {
            guard let file = manifest.files[role] else { return .incomplete("manifest thiếu tệp \(role)") }
            if file.path.contains("..") || file.path.hasPrefix("/") { return .incomplete("manifest có đường dẫn không hợp lệ (\(role))") }
            guard let size = fs.fileSize(dir + "/" + file.path), size > 0 else {
                return .incomplete("thiếu tệp \(file.path)")
            }
        }
        return .complete
    }

    public enum DownloadReason: Equatable, Sendable {
        /// Chưa có model ở đâu cả.
        case notInstalled
        /// Có thư mục model nhưng hỏng/thiếu tệp (lý do kèm theo).
        case incomplete(String)
    }

    public enum Decision: Equatable, Sendable {
        /// Model ở `VFLOW_HOME` đã đủ: chạy ngay, không chép, không tải, không hỏi.
        case ready
        /// `VFLOW_HOME` chưa có, bundle có đủ: chép từ bundle (như trước nay).
        case copyFromBundle
        /// Phải tải về (cần người dùng đồng ý giấy phép trước).
        case needsDownload(DownloadReason)
    }

    /// `home`: model ở `<VFLOW_HOME>/models`; `bundle`: model trong `<bundle>/Contents/Resources/models`
    /// (`.absent` nếu bản dựng không kèm model).
    public static func decide(home: Presence, bundle: Presence) -> Decision {
        switch (home, bundle) {
        case (.complete, _): return .ready
        case (.absent, .complete): return .copyFromBundle
        case (.absent, _): return .needsDownload(.notInstalled)
        case (.incomplete(let why), _): return .needsDownload(.incomplete(why))
        }
    }

    public enum VerifyResult: Equatable, Sendable {
        case ok
        case failed(ModelBootstrap.BootstrapError)
    }

    /// Băm lại từng tệp khai trong `manifest.json` của `<modelsDir>/<id>` và so với sha256 đã ghi.
    /// Dùng sau khi tải: sai ⇒ KHÔNG được dùng model.
    public static func verifyInstalled(modelsDir: String, modelID: String = modelID, fs: ModelBootstrap.FS = .live) -> VerifyResult {
        let dir = modelsDir + "/" + modelID
        guard let data = fs.readData(dir + "/manifest.json") else { return .failed(.manifestMissing(dir + "/manifest.json")) }
        guard let manifest = ModelBootstrap.parseManifest(data) else { return .failed(.manifestInvalid(dir + "/manifest.json")) }
        for role in requiredRoles where manifest.files[role] == nil {
            return .failed(.manifestInvalid("thiếu \(role)"))
        }
        for (role, file) in manifest.files.sorted(by: { $0.key < $1.key }) {
            if file.path.contains("..") || file.path.hasPrefix("/") { return .failed(.manifestInvalid("\(role): \(file.path)")) }
            guard let got = fs.sha256OfFile(dir + "/" + file.path) else {
                return .failed(.copyFailed("không đọc được \(file.path) để kiểm sha256"))
            }
            guard got == file.sha256 else {
                return .failed(.checksumMismatch(role: role, path: file.path, expected: file.sha256, got: got))
            }
        }
        return .ok
    }
}

/// Thông tin hiện trên màn hình xin tải (đúng sự thật, tiếng Việt): xem `engine/stt/registry.js`.
public enum ModelDownloadInfo {
    public static let title = "Zipformer-30M-RNNT-6000h (sherpa-onnx, int8)"
    /// Gói tải về (tar.bz2) ≈ 26,4 MB; sau giải nén chỉ giữ 4 tệp model + test_wavs ≈ 33 MB trên đĩa.
    public static let downloadSizeText = "khoảng 26 MB tải về (khoảng 33 MB trên đĩa sau khi giải nén)"
    public static let sourceText = "Model gốc: hynt/Zipformer-30M-RNNT-6000h trên Hugging Face. Gói đóng sẵn cho sherpa-onnx tải từ GitHub (k2-fsa/sherpa-onnx), vflow kiểm mã băm SHA-256 sau khi tải."
    public static let licenseName = "CC-BY-NC-ND-4.0"
    public static let licenseSummary = "Chỉ dùng cá nhân, phi thương mại; không được phát hành lại bản sửa đổi."
    public static let licenseURL = "https://creativecommons.org/licenses/by-nc-nd/4.0/"
    public static let modelPageURL = "https://huggingface.co/hynt/Zipformer-30M-RNNT-6000h"

    public static func reasonText(_ reason: ModelProvisioning.DownloadReason) -> String {
        switch reason {
        case .notInstalled:
            return "Bản vflow này không kèm sẵn model nhận dạng giọng nói, và máy chưa có model ở thư mục dữ liệu. Cần tải một lần để đọc chính tả."
        case .incomplete(let why):
            return "Model nhận dạng giọng nói trong thư mục dữ liệu bị thiếu hoặc hỏng (\(why)). Cần tải lại để đọc chính tả."
        }
    }
}

extension ModelProvisioning.Decision {
    /// Nhãn ngắn cho nhật ký/kiểm tự động (không có dữ liệu riêng tư).
    public var logLabel: String {
        switch self {
        case .ready: return "ready"
        case .copyFromBundle: return "copy_from_bundle"
        case .needsDownload(.notInstalled): return "needs_download:not_installed"
        case .needsDownload(.incomplete): return "needs_download:incomplete"
        }
    }
}
