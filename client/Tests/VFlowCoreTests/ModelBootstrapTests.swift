import Foundation
import Testing
import CryptoKit
@testable import VFlowCore

/// FS giả trong RAM cho `ModelBootstrap` — không đụng đĩa thật, test được cả nhánh lỗi/dọn dẹp.
private final class FakeModelFS: @unchecked Sendable {
    enum Err: Error { case missing(String) }
    var directories: Set<String> = []
    var files: [String: Data] = [:]
    var removedPaths: [String] = []
    var copyCalls: [(String, String)] = []
    var moveCalls: [(String, String)] = []
    private var tagCounter = 0

    func addDirectory(_ path: String) { directories.insert(path) }
    func addFile(_ path: String, _ content: String) { files[path] = Data(content.utf8) }
    func sha256(of content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func fs() -> ModelBootstrap.FS {
        ModelBootstrap.FS(
            fileExists: { [unowned self] p in self.files[p] != nil || self.directories.contains(p) },
            itemsInDirectory: { [unowned self] dir in
                let prefix = dir + "/"
                var names = Set<String>()
                for p in self.files.keys where p.hasPrefix(prefix) {
                    let rest = String(p.dropFirst(prefix.count))
                    names.insert(String(rest.split(separator: "/", maxSplits: 1).first ?? ""))
                }
                for p in self.directories where p.hasPrefix(prefix) {
                    let rest = String(p.dropFirst(prefix.count))
                    if !rest.isEmpty { names.insert(String(rest.split(separator: "/", maxSplits: 1).first ?? "")) }
                }
                return Array(names)
            },
            readData: { [unowned self] p in self.files[p] },
            sha256OfFile: { [unowned self] p in
                guard let data = self.files[p] else { return nil }
                return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            },
            createDirectory: { [unowned self] p in self.directories.insert(p) },
            copyItem: { [unowned self] src, dst in
                self.copyCalls.append((src, dst))
                guard let data = self.files[src] else { throw Err.missing(src) }
                self.files[dst] = data
            },
            removeItem: { [unowned self] p in
                self.removedPaths.append(p)
                self.files = self.files.filter { !$0.key.hasPrefix(p) }
                self.directories = self.directories.filter { !$0.hasPrefix(p) }
            },
            moveItem: { [unowned self] src, dst in
                self.moveCalls.append((src, dst))
                let prefix = src + "/"
                for (k, v) in self.files where k.hasPrefix(prefix) {
                    self.files[dst + "/" + String(k.dropFirst(prefix.count))] = v
                    self.files.removeValue(forKey: k)
                }
                self.directories.insert(dst)
                self.directories.remove(src)
            },
            uniqueTag: { [unowned self] in self.tagCounter += 1; return "tag\(self.tagCounter)" })
    }
}

/// Hồi quy M4b/Phần 2: chép model lần đầu từ bundle sang `VFLOW_HOME` — nguyên tử, kiểm sha256,
/// không bao giờ đè model đã có, dọn thư mục tạm bỏ dở.
@Suite struct ModelBootstrapTests {
    func manifestJSON(encoderSha: String) -> String {
        #"{"files":{"encoder":{"path":"encoder.onnx","sha256":"\#(encoderSha)"}}}"#
    }

    @Test func alreadyPresentNeverTouchesBundleOrCopies() {
        let w = FakeModelFS()
        w.addFile("/home/.vflow/models/zipformer-vi-30m/manifest.json", "{}")
        let outcome = ModelBootstrap.installIfNeeded(vflowHome: "/home/.vflow", modelID: "zipformer-vi-30m",
                                                      bundleModelsDir: "/App/Contents/Resources/models", fs: w.fs())
        #expect(outcome == .alreadyPresent)
        #expect(w.copyCalls.isEmpty)
        #expect(w.moveCalls.isEmpty)
    }

    @Test func nilBundleDirMeansNoBundledSource() {
        let w = FakeModelFS()
        let outcome = ModelBootstrap.installIfNeeded(vflowHome: "/home/.vflow", modelID: "zipformer-vi-30m",
                                                      bundleModelsDir: nil, fs: w.fs())
        #expect(outcome == .noBundledSource)
    }

    @Test func bundleWithoutManifestMeansNoBundledSource() {
        let w = FakeModelFS()
        // Bundle `--no-bundle` không có models/ bên trong ⇒ không có manifest nguồn.
        let outcome = ModelBootstrap.installIfNeeded(vflowHome: "/home/.vflow", modelID: "zipformer-vi-30m",
                                                      bundleModelsDir: "/App/Contents/Resources/models", fs: w.fs())
        #expect(outcome == .noBundledSource)
    }

    @Test func successfulCopyVerifiesChecksumThenMovesIntoPlace() {
        let w = FakeModelFS()
        let content = "fake-encoder-bytes"
        let srcDir = "/App/Contents/Resources/models/zipformer-vi-30m"
        w.addFile(srcDir + "/manifest.json", manifestJSON(encoderSha: w.sha256(of: content)))
        w.addFile(srcDir + "/encoder.onnx", content)

        let outcome = ModelBootstrap.installIfNeeded(vflowHome: "/home/.vflow", modelID: "zipformer-vi-30m",
                                                      bundleModelsDir: "/App/Contents/Resources/models", fs: w.fs())
        #expect(outcome == .copied)
        #expect(w.files["/home/.vflow/models/zipformer-vi-30m/encoder.onnx"] != nil, "phải nằm ở đích sau khi move")
        #expect(w.files["/home/.vflow/models/zipformer-vi-30m/manifest.json"] != nil)
        #expect(w.moveCalls.count == 1)
        // Thư mục tạm đã bị move đi, không còn sót lại dưới tên `.new-*`.
        #expect(!w.directories.contains(where: { $0.contains(".new-zipformer-vi-30m.") }))
    }

    @Test func checksumMismatchLeavesDestUntouchedAndCleansTemp() {
        // Phá nhánh: manifest ghi sha256 SAI so với nội dung thật — phải phát hiện, không ghi model hỏng.
        let w = FakeModelFS()
        let srcDir = "/App/Contents/Resources/models/zipformer-vi-30m"
        w.addFile(srcDir + "/manifest.json", manifestJSON(encoderSha: "0000000000000000000000000000000000000000000000000000000000000"))
        w.addFile(srcDir + "/encoder.onnx", "fake-encoder-bytes")

        let outcome = ModelBootstrap.installIfNeeded(vflowHome: "/home/.vflow", modelID: "zipformer-vi-30m",
                                                      bundleModelsDir: "/App/Contents/Resources/models", fs: w.fs())
        guard case .failed(.checksumMismatch(let role, _, _, _)) = outcome else {
            Issue.record("phải báo sai checksum: \(outcome)"); return
        }
        #expect(role == "encoder")
        #expect(w.files["/home/.vflow/models/zipformer-vi-30m/manifest.json"] == nil, "đích không được có gì khi sai checksum")
        #expect(w.moveCalls.isEmpty, "không bao giờ move khi chưa kiểm xong")
    }

    @Test func staleTempDirFromInterruptedRunIsCleanedBeforeNewAttempt() {
        let w = FakeModelFS()
        let content = "fake-encoder-bytes"
        let srcDir = "/App/Contents/Resources/models/zipformer-vi-30m"
        w.addFile(srcDir + "/manifest.json", manifestJSON(encoderSha: w.sha256(of: content)))
        w.addFile(srcDir + "/encoder.onnx", content)
        // Mô phỏng lần chạy trước bị crash giữa chừng, để lại thư mục tạm dở dang.
        w.addDirectory("/home/.vflow/models/.new-zipformer-vi-30m.oldcrash")
        w.addFile("/home/.vflow/models/.new-zipformer-vi-30m.oldcrash/encoder.onnx", "nửa vời")

        let outcome = ModelBootstrap.installIfNeeded(vflowHome: "/home/.vflow", modelID: "zipformer-vi-30m",
                                                      bundleModelsDir: "/App/Contents/Resources/models", fs: w.fs())
        #expect(outcome == .copied)
        #expect(w.removedPaths.contains("/home/.vflow/models/.new-zipformer-vi-30m.oldcrash"))
    }

    @Test func neverOverwritesEvenWhenBundleManifestDiffers() {
        // Bất biến quan trọng nhất: dù bundle có bản khác, model đã có ở VFLOW_HOME không bao giờ bị đè.
        let w = FakeModelFS()
        w.addFile("/home/.vflow/models/zipformer-vi-30m/manifest.json", "{\"existing\":true}")
        w.addFile("/home/.vflow/models/zipformer-vi-30m/encoder.onnx", "bản-đã-có-của-người-dùng")
        let srcDir = "/App/Contents/Resources/models/zipformer-vi-30m"
        w.addFile(srcDir + "/manifest.json", manifestJSON(encoderSha: w.sha256(of: "bản-khác-trong-bundle")))
        w.addFile(srcDir + "/encoder.onnx", "bản-khác-trong-bundle")

        let outcome = ModelBootstrap.installIfNeeded(vflowHome: "/home/.vflow", modelID: "zipformer-vi-30m",
                                                      bundleModelsDir: "/App/Contents/Resources/models", fs: w.fs())
        #expect(outcome == .alreadyPresent)
        #expect(w.files["/home/.vflow/models/zipformer-vi-30m/encoder.onnx"].map { String(data: $0, encoding: .utf8) } == "bản-đã-có-của-người-dùng")
    }
}
