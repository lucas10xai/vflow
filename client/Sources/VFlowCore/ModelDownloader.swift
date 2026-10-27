import Foundation

/// Tiến trình "vflow models pull" in ra stderr dạng "  <tên tệp>: 12.0 / 25.2 MB" (xem
/// `engine/stt/models.js: pullModel`). Thuần để test.
public enum ModelPullOutput {
    public struct Progress: Equatable, Sendable {
        public var doneMB: Double
        public var totalMB: Double?
        public init(doneMB: Double, totalMB: Double?) { self.doneMB = doneMB; self.totalMB = totalMB }
        /// 0…1 nếu biết tổng; nil nếu không.
        public var fraction: Double? {
            guard let t = totalMB, t > 0 else { return nil }
            return min(1, max(0, doneMB / t))
        }
    }

    public static func parseProgress(_ line: String) -> Progress? {
        guard line.hasSuffix(" MB"), let colon = line.lastIndex(of: ":") else { return nil }
        let tail = line[line.index(after: colon)...].dropLast(3).trimmingCharacters(in: .whitespaces)
        let parts = tail.split(separator: "/", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 1 || parts.count == 2, let done = Double(parts[0]) else { return nil }
        if parts.count == 2 {
            guard let total = Double(parts[1]) else { return nil }
            return Progress(doneMB: done, totalMB: total)
        }
        return Progress(doneMB: done, totalMB: nil)
    }

    /// Dòng stderr cuối của tiến trình ⇒ thông điệp tiếng Việt đúng nguyên nhân cho người dùng.
    public static func failureMessage(lastLine: String?, exitCode: Int32) -> String {
        let line = (lastLine ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = line.lowercased()
        if lower.contains("sai sha256") {
            return "Tải xong nhưng mã băm SHA-256 không khớp nguồn gốc — đã huỷ, không ghi model. Thử lại sau."
        }
        let networkHints = ["fetch failed", "enotfound", "econnrefused", "econnreset", "etimedout", "eai_again", "network", "http 5", "http 4", "socket", "terminated"]
        if networkHints.contains(where: { lower.contains($0) }) {
            return "Không tải được model — lỗi mạng hoặc máy chủ (\(line.isEmpty ? "mã \(exitCode)" : line)). Kiểm tra kết nối rồi thử lại."
        }
        return "Tải model không thành công (mã \(exitCode))" + (line.isEmpty ? "." : ": \(line)")
    }
}

public enum ModelDownloadState: Equatable, Sendable {
    case idle
    case downloading(ModelPullOutput.Progress?)
    case verifying
    case done
    case cancelled
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .downloading, .verifying: return true
        default: return false
        }
    }
}

/// Tải model bằng ĐÚNG cơ chế đã có của engine (`node bin/vflow.js models pull <id>`: tải, kiểm sha256
/// gói gốc, giải nén, ghi manifest, đổi tên nguyên tử) — KHÔNG viết lại logic tải ở Swift. Sau khi
/// tiến trình thoát mã 0, client TỰ băm lại từng tệp theo manifest (`ModelProvisioning.verifyInstalled`):
/// sai ⇒ xoá thư mục model vừa tải, báo lỗi, không bao giờ chạy model hỏng.
/// Chỉ được gọi SAU khi người dùng đã bấm đồng ý giấy phép (xem màn hình xin tải).
@MainActor
public final class ModelDownloader {
    private let spec: EngineLaunchSpec
    private let home: String
    private let modelID: String
    private let launcher: ProcessLauncher
    private let fs: ModelBootstrap.FS
    private var handle: ProcessHandle?
    private var generation = 0
    private var lastLine: String?
    public private(set) var state: ModelDownloadState = .idle { didSet { if state != oldValue { onState?(state) } } }
    public var onState: ((ModelDownloadState) -> Void)?

    public init(spec: EngineLaunchSpec, home: String, modelID: String = ModelProvisioning.modelID,
                launcher: ProcessLauncher = FoundationProcessLauncher(), fs: ModelBootstrap.FS = .live) {
        self.spec = spec
        self.home = home
        self.modelID = modelID
        self.launcher = launcher
        self.fs = fs
    }

    public var modelsDir: String { home + "/models" }

    public func start() {
        guard !state.isBusy else { return }
        generation += 1
        let gen = generation
        lastLine = nil
        var env = ProcessInfo.processInfo.environment
        env["VFLOW_HOME"] = home
        let nodeDir = (spec.node as NSString).deletingLastPathComponent
        env["PATH"] = "\(nodeDir):/usr/bin:/bin:/usr/sbin:/sbin"
        state = .downloading(nil)
        do {
            handle = try launcher.launch(
                executable: spec.node, arguments: [spec.script, "models", "pull", modelID], environment: env,
                onStderrLine: { [weak self] line in Task { @MainActor in self?.stderrLine(line, generation: gen) } },
                onExit: { [weak self] code in Task { @MainActor in self?.exited(code: code, generation: gen) } })
        } catch {
            state = .failed("Không chạy được engine để tải model: \(error)")
        }
    }

    /// Huỷ: dừng tiến trình tải và dọn thư mục tạm bỏ dở (`.tmp-`/`.new-`/`.old-` của lần tải này) —
    /// KHÔNG đụng thư mục model đã có.
    public func cancel() {
        guard state.isBusy else { return }
        generation += 1 // bỏ qua mọi sự kiện muộn của tiến trình cũ
        handle?.terminate()
        handle = nil
        cleanupPartial()
        state = .cancelled
    }

    private func stderrLine(_ line: String, generation gen: Int) {
        guard gen == generation else { return }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { lastLine = trimmed }
        if let p = ModelPullOutput.parseProgress(line), case .downloading = state { state = .downloading(p) }
    }

    private func exited(code: Int32, generation gen: Int) {
        guard gen == generation else { return }
        handle = nil
        guard code == 0 else {
            cleanupPartial()
            state = .failed(ModelPullOutput.failureMessage(lastLine: lastLine, exitCode: code))
            return
        }
        state = .verifying
        let modelsDir = self.modelsDir, id = modelID, fs = self.fs
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = ModelProvisioning.verifyInstalled(modelsDir: modelsDir, modelID: id, fs: fs)
            await MainActor.run { self?.verified(result, generation: gen) }
        }
    }

    private func verified(_ result: ModelProvisioning.VerifyResult, generation gen: Int) {
        guard gen == generation else { return }
        switch result {
        case .ok:
            state = .done
        case .failed(let e):
            // Model hỏng KHÔNG được để lại để engine nạp: xoá hẳn thư mục model vừa tải.
            try? fs.removeItem(modelsDir + "/" + modelID)
            switch e {
            case .checksumMismatch(_, let path, _, _):
                state = .failed("Mã băm SHA-256 của tệp \(path) không khớp sau khi tải — đã xoá model hỏng, không dùng. Thử tải lại.")
            default:
                state = .failed("Kiểm tra model sau khi tải không đạt (\(e)) — đã xoá model hỏng. Thử tải lại.")
            }
        }
    }

    private func cleanupPartial() {
        let root = modelsDir
        for name in fs.itemsInDirectory(root) where name.hasPrefix(".tmp-\(modelID).") || name.hasPrefix(".new-\(modelID).") || name.hasPrefix(".old-\(modelID).") {
            // `.old-` chỉ xuất hiện giữa lúc đổi tên; nếu tiến trình chết đúng lúc đó mà thư mục model chính
            // đã mất thì khôi phục thay vì xoá (không làm mất model cũ).
            if name.hasPrefix(".old-\(modelID).") && !fs.fileExists(root + "/" + modelID) {
                try? fs.moveItem(root + "/" + name, root + "/" + modelID)
            } else {
                try? fs.removeItem(root + "/" + name)
            }
        }
    }
}
