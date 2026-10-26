import Foundation
import CryptoKit

/// Chép model từ bundle (`VFlow.app/Contents/Resources/models/<id>/`) sang `<VFLOW_HOME>/models/<id>/`
/// ở LẦN CHẠY ĐẦU khi `VFLOW_HOME` chưa có model đó — để app tự đủ (không cần `vflow models pull`
/// qua mạng). KHÔNG BAO GIỜ đè model đã có (dù checksum khác — người dùng có thể đã tự cập nhật);
/// chép qua thư mục tạm rồi đổi tên nguyên tử (giống `engine/stt/models.js: pullModel`), kiểm
/// sha256 từng tệp khai trong `manifest.json` trước khi coi là xong.
public enum ModelBootstrap {
    public struct ManifestFile: Equatable, Sendable {
        public var path: String
        public var sha256: String
        public init(path: String, sha256: String) { self.path = path; self.sha256 = sha256 }
    }

    /// Chỉ phần cần dùng của `manifest.json` (xem `engine/stt/models.js`): map vai trò ⇒ tệp.
    public struct Manifest: Equatable, Sendable {
        public var files: [String: ManifestFile]
    }

    public enum BootstrapError: Error, Equatable, Sendable {
        case manifestMissing(String)
        case manifestInvalid(String)
        case checksumMismatch(role: String, path: String, expected: String, got: String)
        case copyFailed(String)
    }

    public enum Outcome: Equatable, Sendable {
        /// Đã có model ở `VFLOW_HOME` từ trước ⇒ không đụng tới.
        case alreadyPresent
        /// Không có model trong bundle (bản dựng `--no-bundle`, hoặc chạy từ repo) ⇒ im lặng bỏ qua,
        /// không phải lỗi (người dùng sẽ `vflow models pull` như trước M4b).
        case noBundledSource
        case copied
        case failed(BootstrapError)
    }

    /// Trừu tượng hoá filesystem — test được bằng bộ giả, không đụng đĩa thật (giống `ClientConfig.FileSystem`).
    public struct FS: Sendable {
        public var fileExists: @Sendable (String) -> Bool
        /// Tên tệp/thư mục con trực tiếp (không đệ quy); rỗng nếu đọc được coi là thư mục không tồn tại.
        public var itemsInDirectory: @Sendable (String) -> [String]
        public var readData: @Sendable (String) -> Data?
        public var sha256OfFile: @Sendable (String) -> String?
        public var createDirectory: @Sendable (String) throws -> Void
        public var copyItem: @Sendable (String, String) throws -> Void
        public var removeItem: @Sendable (String) throws -> Void
        public var moveItem: @Sendable (String, String) throws -> Void
        public var uniqueTag: @Sendable () -> String

        public init(fileExists: @escaping @Sendable (String) -> Bool,
                    itemsInDirectory: @escaping @Sendable (String) -> [String],
                    readData: @escaping @Sendable (String) -> Data?,
                    sha256OfFile: @escaping @Sendable (String) -> String?,
                    createDirectory: @escaping @Sendable (String) throws -> Void,
                    copyItem: @escaping @Sendable (String, String) throws -> Void,
                    removeItem: @escaping @Sendable (String) throws -> Void,
                    moveItem: @escaping @Sendable (String, String) throws -> Void,
                    uniqueTag: @escaping @Sendable () -> String = { UUID().uuidString }) {
            self.fileExists = fileExists
            self.itemsInDirectory = itemsInDirectory
            self.readData = readData
            self.sha256OfFile = sha256OfFile
            self.createDirectory = createDirectory
            self.copyItem = copyItem
            self.removeItem = removeItem
            self.moveItem = moveItem
            self.uniqueTag = uniqueTag
        }

        public static let live = FS(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            itemsInDirectory: { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] },
            readData: { FileManager.default.contents(atPath: $0) },
            sha256OfFile: { path in
                guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
                defer { try? fh.close() }
                var hasher = SHA256()
                while true {
                    let chunk = fh.readData(ofLength: 4 * 1024 * 1024)
                    if chunk.isEmpty { break }
                    hasher.update(data: chunk)
                }
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            },
            createDirectory: { try FileManager.default.createDirectory(atPath: $0, withIntermediateDirectories: true) },
            copyItem: { try FileManager.default.copyItem(atPath: $0, toPath: $1) },
            removeItem: { try FileManager.default.removeItem(atPath: $0) },
            moveItem: { try FileManager.default.moveItem(atPath: $0, toPath: $1) })
    }

    static func parseManifest(_ data: Data) -> Manifest? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filesObj = obj["files"] as? [String: Any] else { return nil }
        var files: [String: ManifestFile] = [:]
        for (role, v) in filesObj {
            guard let f = v as? [String: Any], let path = f["path"] as? String, let sha = f["sha256"] as? String else { return nil }
            files[role] = ManifestFile(path: path, sha256: sha)
        }
        return files.isEmpty ? nil : Manifest(files: files)
    }

    /// `bundleModelsDir`: `<bundle>/Contents/Resources/models` nếu bản dựng có kèm model, nil nếu không
    /// (bản `--no-bundle`, hoặc chạy không qua bundle).
    public static func installIfNeeded(vflowHome: String, modelID: String, bundleModelsDir: String?, fs: FS) -> Outcome {
        let modelsRoot = vflowHome + "/models"
        let destDir = modelsRoot + "/" + modelID
        guard !fs.fileExists(destDir + "/manifest.json") else { return .alreadyPresent }
        guard let bundleModelsDir else { return .noBundledSource }
        let srcDir = bundleModelsDir + "/" + modelID
        guard fs.fileExists(srcDir + "/manifest.json") else { return .noBundledSource }
        guard let manifestData = fs.readData(srcDir + "/manifest.json") else {
            return .failed(.manifestMissing(srcDir + "/manifest.json"))
        }
        guard let manifest = parseManifest(manifestData) else {
            return .failed(.manifestInvalid(srcDir + "/manifest.json"))
        }

        // Dọn thư mục tạm bỏ dở từ lần chạy trước bị gián đoạn (crash giữa chừng).
        let tmpPrefix = ".new-\(modelID)."
        for name in fs.itemsInDirectory(modelsRoot) where name.hasPrefix(tmpPrefix) {
            try? fs.removeItem(modelsRoot + "/" + name)
        }

        let tmp = modelsRoot + "/\(tmpPrefix)\(fs.uniqueTag())"
        do {
            try fs.createDirectory(tmp)
            for name in fs.itemsInDirectory(srcDir) {
                try fs.copyItem(srcDir + "/" + name, tmp + "/" + name)
            }
        } catch {
            try? fs.removeItem(tmp)
            return .failed(.copyFailed("\(error)"))
        }

        for (role, file) in manifest.files.sorted(by: { $0.key < $1.key }) {
            let path = tmp + "/" + file.path
            guard let got = fs.sha256OfFile(path) else {
                try? fs.removeItem(tmp)
                return .failed(.copyFailed("không đọc được \(path) để kiểm sha256"))
            }
            guard got == file.sha256 else {
                try? fs.removeItem(tmp)
                return .failed(.checksumMismatch(role: role, path: file.path, expected: file.sha256, got: got))
            }
        }

        do {
            try fs.moveItem(tmp, destDir)
        } catch {
            try? fs.removeItem(tmp)
            return .failed(.copyFailed("\(error)"))
        }
        return .copied
    }
}
