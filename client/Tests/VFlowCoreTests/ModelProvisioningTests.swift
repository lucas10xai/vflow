import Foundation
import Testing
import CryptoKit
@testable import VFlowCore

// O1: bản công khai KHÔNG kèm model (giấy phép CC-BY-NC-ND-4.0), bản chủ dự án dùng vẫn kèm/đã có model ở
// ~/.vflow/models và KHÔNG được đổi trải nghiệm. Test bằng thư mục thật dưới thư mục tạm (không đụng ~/.vflow).

private func sha(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

private let modelFiles: [String: (String, String)] = [
    "encoder": ("encoder.int8.onnx", "ENC-BYTES"), "decoder": ("decoder.onnx", "DEC-BYTES"),
    "joiner": ("joiner.int8.onnx", "JOIN-BYTES"), "tokens": ("tokens.txt", "TOK-BYTES"),
]

/// Thư mục tạm có `models/<id>` đủ tệp + manifest thật (sha256 thật). Tự xoá khi `deinit`.
private final class Sandbox {
    let root: String
    init() {
        root = NSTemporaryDirectory() + "o1-test-" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(atPath: root) }

    var home: String { root + "/home" }
    var modelsDir: String { home + "/models" }
    var bundleModelsDir: String { root + "/App.app/Contents/Resources/models" }
    func modelDir(_ models: String) -> String { models + "/" + ModelProvisioning.modelID }

    func write(_ path: String, _ content: String) {
        try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! Data(content.utf8).write(to: URL(fileURLWithPath: path))
    }

    /// `corruptRole`: ghi nội dung KHÁC với sha trong manifest (mô phỏng tải/ghi hỏng).
    func installModel(in models: String, corruptRole: String? = nil, skipRole: String? = nil, emptyRole: String? = nil) {
        let dir = modelDir(models)
        var entries: [String] = []
        for (role, (name, content)) in modelFiles.sorted(by: { $0.key < $1.key }) {
            entries.append(#""\#(role)":{"path":"\#(name)","sha256":"\#(sha(content))"}"#)
            if role == skipRole { continue }
            let body = role == corruptRole ? content + "-HONG" : (role == emptyRole ? "" : content)
            write(dir + "/" + name, body)
        }
        write(dir + "/manifest.json", "{\"files\":{\(entries.joined(separator: ","))}}")
    }
}

@Suite struct ModelPresenceTests {
    @Test func đủManifestVàBốnTệpKhácRỗngLàComplete() {
        let s = Sandbox(); s.installModel(in: s.modelsDir)
        #expect(ModelProvisioning.inspect(modelsDir: s.modelsDir) == .complete)
    }

    @Test func khôngCóManifestLàAbsent_kểCảKhiThưMụcModelTrống() {
        let s = Sandbox()
        #expect(ModelProvisioning.inspect(modelsDir: s.modelsDir) == .absent)
        try! FileManager.default.createDirectory(atPath: s.modelDir(s.modelsDir), withIntermediateDirectories: true)
        #expect(ModelProvisioning.inspect(modelsDir: s.modelsDir) == .absent)
    }

    @Test func thiếuTệpHoặcTệpRỗngHoặcManifestHỏngLàIncomplete_khôngBaoGiờLàComplete() {
        for variant in ["thiếu", "rỗng"] {
            let s = Sandbox()
            s.installModel(in: s.modelsDir, skipRole: variant == "thiếu" ? "joiner" : nil, emptyRole: variant == "rỗng" ? "encoder" : nil)
            guard case .incomplete = ModelProvisioning.inspect(modelsDir: s.modelsDir) else { Issue.record("\(variant): phải là incomplete"); continue }
        }
        let broken = Sandbox(); broken.write(broken.modelDir(broken.modelsDir) + "/manifest.json", "{ không phải json")
        #expect(ModelProvisioning.inspect(modelsDir: broken.modelsDir) == .incomplete("manifest.json hỏng"))
        let noRole = Sandbox()
        noRole.write(noRole.modelDir(noRole.modelsDir) + "/e.onnx", "ENC") // manifest chỉ khai encoder (có tệp) — thiếu decoder/joiner/tokens
        noRole.write(noRole.modelDir(noRole.modelsDir) + "/manifest.json", #"{"files":{"encoder":{"path":"e.onnx","sha256":"x"}}}"#)
        guard case .incomplete(let why) = ModelProvisioning.inspect(modelsDir: noRole.modelsDir) else { Issue.record("phải incomplete"); return }
        #expect(why.contains("decoder"))
    }

    @Test func đườngDẫnTrongManifestThoátKhỏiThưMụcBịTừChối() {
        let s = Sandbox()
        s.write(s.modelDir(s.modelsDir) + "/manifest.json",
                #"{"files":{"encoder":{"path":"../x","sha256":"a"},"decoder":{"path":"d","sha256":"a"},"joiner":{"path":"j","sha256":"a"},"tokens":{"path":"t","sha256":"a"}}}"#)
        guard case .incomplete = ModelProvisioning.inspect(modelsDir: s.modelsDir) else { Issue.record("phải incomplete"); return }
    }
}

@Suite struct ModelDecisionTests {
    /// YÊU CẦU CỨNG: model đã có ở VFLOW_HOME (bản chủ dự án) ⇒ chạy NGAY, dù bản dựng có kèm model hay không.
    @Test func modelĐãCóỞVflowHomeThìReady_bảnKhôngKèmModelKhôngHỏiKhôngTải() {
        #expect(ModelProvisioning.decide(home: .complete, bundle: .absent) == .ready)      // bản công khai trên máy chủ dự án
        #expect(ModelProvisioning.decide(home: .complete, bundle: .complete) == .ready)    // bản kèm model: KHÔNG chép đè
        #expect(ModelProvisioning.decide(home: .complete, bundle: .incomplete("x")) == .ready)
    }

    @Test func chưaCóỞHomeNhưngBundleCóThìChépTừBundle() {
        #expect(ModelProvisioning.decide(home: .absent, bundle: .complete) == .copyFromBundle)
    }

    @Test func khôngCóỞĐâuCảThìMớiXinTải() {
        #expect(ModelProvisioning.decide(home: .absent, bundle: .absent) == .needsDownload(.notInstalled))
        #expect(ModelProvisioning.decide(home: .absent, bundle: .incomplete("hỏng")) == .needsDownload(.notInstalled))
    }

    @Test func modelỞHomeBịThiếuTệpThìXinTảiLại_khôngÂmThầmCoiLàĐủ() {
        #expect(ModelProvisioning.decide(home: .incomplete("thiếu tệp a"), bundle: .absent) == .needsDownload(.incomplete("thiếu tệp a")))
        #expect(ModelProvisioning.decide(home: .incomplete("thiếu tệp a"), bundle: .complete) == .needsDownload(.incomplete("thiếu tệp a")))
    }

    // Ba kịch bản theo thư mục thật: chỉ trong bundle / chỉ trong VFLOW_HOME / không có đâu cả.
    @Test func baKịchBảnThưMụcGiả() {
        func decision(_ s: Sandbox) -> ModelProvisioning.Decision {
            ModelProvisioning.decide(home: ModelProvisioning.inspect(modelsDir: s.modelsDir),
                                     bundle: ModelProvisioning.inspect(modelsDir: s.bundleModelsDir))
        }
        let onlyBundle = Sandbox(); onlyBundle.installModel(in: onlyBundle.bundleModelsDir)
        #expect(decision(onlyBundle) == .copyFromBundle)
        let onlyHome = Sandbox(); onlyHome.installModel(in: onlyHome.modelsDir)
        #expect(decision(onlyHome) == .ready)
        let none = Sandbox()
        #expect(decision(none) == .needsDownload(.notInstalled))
        let both = Sandbox(); both.installModel(in: both.modelsDir); both.installModel(in: both.bundleModelsDir)
        #expect(decision(both) == .ready)
    }

    @Test func nhãnNhậtKýĐủĐểKiểmTựĐộng() {
        #expect(ModelProvisioning.Decision.ready.logLabel == "ready")
        #expect(ModelProvisioning.Decision.copyFromBundle.logLabel == "copy_from_bundle")
        #expect(ModelProvisioning.Decision.needsDownload(.notInstalled).logLabel == "needs_download:not_installed")
        #expect(ModelProvisioning.Decision.needsDownload(.incomplete("x")).logLabel == "needs_download:incomplete")
    }
}

@Suite struct ModelVerifyTests {
    @Test func đúngMãBămThìOk() {
        let s = Sandbox(); s.installModel(in: s.modelsDir)
        #expect(ModelProvisioning.verifyInstalled(modelsDir: s.modelsDir) == .ok)
    }

    @Test func saiMãBămMộtTệpThìTừChốiVàNóiĐúngTệp() {
        let s = Sandbox(); s.installModel(in: s.modelsDir, corruptRole: "joiner")
        guard case .failed(.checksumMismatch(let role, let path, let expected, let got)) = ModelProvisioning.verifyInstalled(modelsDir: s.modelsDir) else {
            Issue.record("phải checksumMismatch"); return
        }
        #expect(role == "joiner" && path == "joiner.int8.onnx")
        #expect(expected == sha("JOIN-BYTES") && got == sha("JOIN-BYTES-HONG"))
    }

    @Test func thiếuTệpHoặcManifestThìKhôngBaoGiờOk() {
        let missing = Sandbox(); missing.installModel(in: missing.modelsDir, skipRole: "tokens")
        #expect(ModelProvisioning.verifyInstalled(modelsDir: missing.modelsDir) != .ok)
        let none = Sandbox()
        guard case .failed(.manifestMissing) = ModelProvisioning.verifyInstalled(modelsDir: none.modelsDir) else { Issue.record("phải manifestMissing"); return }
    }
}

@Suite struct ModelPullOutputTests {
    @Test func đọcDòngTiếnĐộCủaEngine() {
        #expect(ModelPullOutput.parseProgress("  sherpa-onnx-zipformer-vi-30M-int8-2026-02-09.tar.bz2: 12.0 / 25.2 MB")
                == .init(doneMB: 12.0, totalMB: 25.2))
        #expect(ModelPullOutput.parseProgress("  a.tar.bz2: 3.5 MB") == .init(doneMB: 3.5, totalMB: nil))
        #expect(ModelPullOutput.parseProgress("Tải https://github.com/x.tar.bz2") == nil)
        #expect(ModelPullOutput.parseProgress("Giải nén…") == nil)
        #expect(abs((ModelPullOutput.parseProgress("  a: 12.6 / 25.2 MB")?.fraction ?? 0) - 0.5) < 1e-9)
        #expect(ModelPullOutput.parseProgress("  a: 30 / 25.2 MB")?.fraction == 1) // không vượt 100%
    }

    @Test func thôngĐiệpLỗiĐúngNguyênNhân() {
        #expect(ModelPullOutput.failureMessage(lastLine: "vflow: fetch failed", exitCode: 1).contains("lỗi mạng"))
        #expect(ModelPullOutput.failureMessage(lastLine: "vflow: [internal] Sai sha256 cho x: mong đợi a, nhận b. Đã huỷ, không ghi model.", exitCode: 1).contains("SHA-256 không khớp"))
        let other = ModelPullOutput.failureMessage(lastLine: "vflow: hết dung lượng", exitCode: 1)
        #expect(other.contains("hết dung lượng") && !other.contains("lỗi mạng"))
        #expect(ModelPullOutput.failureMessage(lastLine: nil, exitCode: 7).contains("mã 7"))
    }
}

// MARK: - ModelDownloader với bộ chạy tiến trình giả

private final class FakeProcess: ProcessHandle, @unchecked Sendable {
    let pid: Int32 = 4242
    var isRunning = true
    var terminated = false
    func terminate() { terminated = true; isRunning = false }
    func kill() { isRunning = false }
}

private final class FakeLauncher: ProcessLauncher, @unchecked Sendable {
    var launches: [(executable: String, arguments: [String], environment: [String: String])] = []
    var stderr: (@Sendable (String) -> Void)?
    var exit: (@Sendable (Int32) -> Void)?
    var process = FakeProcess()
    func launch(executable: String, arguments: [String], environment: [String: String],
                onStderrLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) throws -> ProcessHandle {
        launches.append((executable, arguments, environment))
        stderr = onStderrLine
        exit = onExit
        process = FakeProcess()
        return process
    }
}

@MainActor
private func waitUntil(_ timeout: Double = 5, _ cond: () -> Bool) async {
    let end = Date().addingTimeInterval(timeout)
    while !cond(), Date() < end { try? await Task.sleep(for: .milliseconds(5)) }
}

@MainActor
private func makeDownloader(_ s: Sandbox, _ launcher: FakeLauncher) -> ModelDownloader {
    let spec = EngineLaunchSpec(node: "/app/node/bin/node", script: "/app/engine/bin/vflow.js", repo: "/app/engine", port: 7611)
    return ModelDownloader(spec: spec, home: s.home, launcher: launcher)
}

@Suite @MainActor struct ModelDownloaderTests {
    @Test func chưaBấmĐồngÝThìKhôngChạyGìCả_vàStartDùngĐúngCơChếTảiCủaEngine() {
        let s = Sandbox(); let l = FakeLauncher()
        let d = makeDownloader(s, l)
        #expect(l.launches.isEmpty)                 // chỉ tạo downloader/hiện màn hình KHÔNG tải
        #expect(d.state == .idle)
        d.start()                                   // = người dùng bấm "Đồng ý và tải"
        #expect(l.launches.count == 1)
        #expect(l.launches[0].executable == "/app/node/bin/node")
        #expect(l.launches[0].arguments == ["/app/engine/bin/vflow.js", "models", "pull", "zipformer-vi-30m"])
        #expect(l.launches[0].environment["VFLOW_HOME"] == s.home)
        #expect(d.state == .downloading(nil))
    }

    @Test func tiếnĐộĐượcCậpNhậtTừStderrCủaEngine() async {
        let s = Sandbox(); let l = FakeLauncher(); let d = makeDownloader(s, l)
        d.start()
        l.stderr?("Tải https://github.com/k2-fsa/…tar.bz2")
        l.stderr?("  gói.tar.bz2: 8.0 / 25.2 MB")
        await waitUntil { d.state == .downloading(.init(doneMB: 8.0, totalMB: 25.2)) }
        #expect(d.state == .downloading(.init(doneMB: 8.0, totalMB: 25.2)))
    }

    @Test func tảiXongMãBămKhớpThìDone() async {
        let s = Sandbox(); let l = FakeLauncher(); let d = makeDownloader(s, l)
        d.start()
        s.installModel(in: s.modelsDir)             // engine đã ghi model + manifest
        l.exit?(0)
        await waitUntil { d.state == .done }
        #expect(d.state == .done)
        #expect(ModelProvisioning.inspect(modelsDir: s.modelsDir) == .complete)
    }

    /// Tải xong nhưng một tệp sai mã băm ⇒ TỪ CHỐI, XOÁ model hỏng, báo rõ, không bao giờ để engine nạp.
    @Test func saiMãBămSauKhiTảiThìXoáVàBáoLỗi() async {
        let s = Sandbox(); let l = FakeLauncher(); let d = makeDownloader(s, l)
        d.start()
        s.installModel(in: s.modelsDir, corruptRole: "encoder")
        l.exit?(0)
        await waitUntil { if case .failed = d.state { return true } else { return false } }
        guard case .failed(let msg) = d.state else { Issue.record("phải failed, được \(d.state)"); return }
        #expect(msg.contains("encoder.int8.onnx") && msg.contains("SHA-256"))
        #expect(!FileManager.default.fileExists(atPath: s.modelDir(s.modelsDir)))   // đã xoá model hỏng
        #expect(ModelProvisioning.inspect(modelsDir: s.modelsDir) == .absent)
    }

    @Test func lỗiMạngBáoRõVàThửLạiĐược() async {
        let s = Sandbox(); let l = FakeLauncher(); let d = makeDownloader(s, l)
        d.start()
        l.stderr?("vflow: fetch failed")
        await waitUntil { if case .downloading = d.state { return true } else { return false } }
        l.exit?(1)
        await waitUntil { if case .failed = d.state { return true } else { return false } }
        guard case .failed(let msg) = d.state else { Issue.record("phải failed"); return }
        #expect(msg.contains("lỗi mạng"))
        d.start()                                   // "Thử lại"
        #expect(l.launches.count == 2)
        #expect(d.state == .downloading(nil))
    }

    @Test func huỷDừngTiếnTrìnhDọnThưMụcTạmVàKhôngĐụngModelĐãCó() async {
        let s = Sandbox(); let l = FakeLauncher(); let d = makeDownloader(s, l)
        s.installModel(in: s.modelsDir)             // đang có model hỏng/cũ — việc huỷ không được động tới
        let tmp = s.modelsDir + "/.tmp-zipformer-vi-30m.123.abcd"
        let newer = s.modelsDir + "/.new-zipformer-vi-30m.123.abcd"
        let unrelated = s.modelsDir + "/.tmp-model-khac.1.zz"
        for p in [tmp, newer, unrelated] { s.write(p + "/x", "dở dang") }
        d.start()
        d.cancel()
        #expect(l.process.terminated)
        #expect(d.state == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: tmp) && !FileManager.default.fileExists(atPath: newer))
        #expect(FileManager.default.fileExists(atPath: unrelated))                      // chỉ dọn của model này
        #expect(ModelProvisioning.inspect(modelsDir: s.modelsDir) == .complete)         // model đã có còn nguyên
        // Sự kiện muộn của tiến trình đã bị huỷ KHÔNG được lật trạng thái về lỗi/xong.
        l.exit?(15)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(d.state == .cancelled)
    }

    @Test func huỷRồiTảiLạiĐược() async {
        let s = Sandbox(); let l = FakeLauncher(); let d = makeDownloader(s, l)
        d.start(); d.cancel()
        d.start()
        #expect(l.launches.count == 2)
        #expect(d.state == .downloading(nil))
    }

    @Test func đangTảiThìBấmTảiLầnNữaKhôngChạyHaiTiếnTrình() {
        let s = Sandbox(); let l = FakeLauncher(); let d = makeDownloader(s, l)
        d.start(); d.start()
        #expect(l.launches.count == 1)
    }
}
