import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Bộ phát MỘT tệp âm thanh — lớp AppKit (`AVAudioPlayer`) hiện thực, test dùng bản giả. Mọi hàm
/// gọi trên luồng chính.
@MainActor
public protocol AudioClipPlayer: AnyObject {
    /// Bắt đầu phát `fileURL`. Gọi `onFinish(true)` khi hết bài tự nhiên, `onFinish(false)` khi hỏng
    /// giữa chừng. KHÔNG gọi `onFinish` sau `stop()`. Ném lỗi nếu không mở/giải mã được tệp.
    func start(fileURL: URL, onFinish: @escaping @MainActor (Bool) -> Void) throws
    func stop()
    /// Tiến độ 0…1 (0 khi chưa phát).
    var progress: Double { get }
}

/// Tệp tạm 0600 cho bản ghi âm đang nghe lại: tạo bằng `O_EXCL` với quyền 0600 NGAY LÚC TẠO (không
/// có khoảng hở 0644), nằm trong thư mục riêng 0700. Dọn bằng `remove`/`purge`.
public enum AudioTempFiles {
    public enum FileError: Error, Equatable, Sendable { case io(String) }

    /// Ghi `data` ra `<directory>/<uuid>.wav` (tạo `directory` 0700 nếu chưa có), trả URL.
    public static func writePrivate(_ data: Data, in directory: URL) throws -> URL {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw FileError.io(error.localizedDescription)
        }
        let url = directory.appendingPathComponent(UUID().uuidString + ".wav")
        try writeNew(data, to: url)
        return url
    }

    /// Tạo tệp MỚI (`O_EXCL`, không ghi đè) với quyền 0600 rồi ghi hết `data`; lỗi giữa chừng ⇒ xoá
    /// phần đã ghi, không để tệp nửa vời.
    static func writeNew(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw FileError.io(String(cString: strerror(errno))) }
        var failure: String?
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var off = 0
            while off < buf.count {
                guard let base = buf.baseAddress else { break }
                let n = Darwin.write(fd, base.advanced(by: off), buf.count - off)
                if n < 0 {
                    if errno == EINTR { continue }
                    failure = String(cString: strerror(errno))
                    return
                }
                off += n
            }
        }
        if close(fd) != 0, failure == nil { failure = String(cString: strerror(errno)) }
        if let failure {
            try? FileManager.default.removeItem(at: url)
            throw FileError.io(failure)
        }
    }

    public static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Xoá mọi tệp `.wav` còn sót trong `directory` (lần chạy trước bị ngắt giữa chừng). Trả số tệp đã xoá.
    @discardableResult
    public static func purge(directory: URL) -> Int {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where name.hasSuffix(".wav") {
            if (try? fm.removeItem(at: directory.appendingPathComponent(name))) != nil { removed += 1 }
        }
        return removed
    }
}

/// Lưu gói ZIP xuất âm thanh người dùng đã chọn chỗ lưu: quyền 0600 NGAY LÚC TẠO (tệp tạm cùng thư
/// mục rồi đổi tên đè — không bao giờ có lúc nào tệp đích đọc được bởi người khác), lỗi ⇒ ném lỗi
/// thật và không để lại tệp tạm.
public enum AudioExportWriter {
    public static func write(_ data: Data, to destination: URL) throws {
        let dir = destination.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".vflow-export-\(UUID().uuidString).tmp")
        try AudioTempFiles.writeNew(data, to: temp)
        if rename(temp.path, destination.path) != 0 {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temp)
            throw AudioTempFiles.FileError.io(reason)
        }
    }
}

/// Điều phối nghe lại một bản ghi âm của Lịch sử: CHỈ MỘT bản tại một thời điểm, tải WAV về tệp tạm
/// 0600, xoá NGAY khi phát xong/dừng/đổi bài/lỗi, 404 ⇒ báo `onMissing` (gỡ `audio_id` khỏi mục).
/// Không bao giờ tự phát — chỉ chạy khi người dùng gọi `toggle`.
@MainActor
public final class AudioPlaybackController {
    public typealias Fetch = (String) async -> Result<Data, ClientError>

    public private(set) var coordinator = AudioPlaybackCoordinator()
    /// Gọi mỗi khi `coordinator.state` đổi (để view vẽ lại).
    public var onChange: (() -> Void)?
    /// Bản ghi âm không còn phía engine (404) — gọi một lần với id đó.
    public var onMissing: ((String) -> Void)?

    private let directory: URL
    private let fetch: Fetch
    private let makePlayer: () -> AudioClipPlayer
    private var player: AudioClipPlayer?
    private var tempFile: URL?
    /// Tăng mỗi lần dừng/đổi bài: một lần tải/phát cũ hoàn tất muộn thì bị bỏ, không phát chồng.
    private var generation = 0

    public init(directory: URL, fetch: @escaping Fetch, makePlayer: @escaping () -> AudioClipPlayer) {
        self.directory = directory
        self.fetch = fetch
        self.makePlayer = makePlayer
        AudioTempFiles.purge(directory: directory)
    }

    public var state: AudioPlaybackState { coordinator.state }
    public var progress: Double { player?.progress ?? 0 }

    /// Bấm nút phát/dừng của mục `id`.
    public func toggle(id: String) async {
        switch coordinator.togglePlay(id: id) {
        case .stop:
            halt()
            onChange?()
        case .startNew(let id):
            halt()
            let gen = generation
            onChange?()
            let result = await fetch(id)
            guard gen == generation else { return } // đã dừng/đổi bài trong lúc tải
            switch result {
            case .failure(let error):
                if EngineAPI.isAudioMissing(error) {
                    coordinator.stop()
                    onChange?()
                    onMissing?(id)
                } else {
                    coordinator.failed(id: id, message: Self.message(for: error))
                    onChange?()
                }
            case .success(let data):
                play(data, id: id, gen: gen)
            }
        }
    }

    /// Dừng mọi thứ đang phát/đang tải và xoá tệp tạm (đóng tab, thoát app, xoá mục đang nghe).
    public func stopAll() {
        halt()
        coordinator.stop()
        onChange?()
    }

    /// Dừng nếu đang phát/đang tải đúng `id` (xoá âm thanh/mục của chính bản đang nghe).
    public func stopIfPlaying(id: String) {
        if case .playing(let current) = coordinator.state, current == id { stopAll() }
    }

    private func play(_ data: Data, id: String, gen: Int) {
        let url: URL
        do {
            url = try AudioTempFiles.writePrivate(data, in: directory)
        } catch {
            coordinator.failed(id: id, message: "Không tạo được tệp tạm để phát: \(error)")
            onChange?()
            return
        }
        tempFile = url
        let p = makePlayer()
        player = p
        do {
            try p.start(fileURL: url) { [weak self] ok in
                self?.finish(id: id, gen: gen, ok: ok)
            }
        } catch {
            cleanup()
            coordinator.failed(id: id, message: "Không phát được bản ghi âm này: \(error.localizedDescription)")
        }
        onChange?()
    }

    private func finish(id: String, gen: Int, ok: Bool) {
        guard gen == generation else { return }
        cleanup()
        if ok { coordinator.finished(id: id) } else { coordinator.failed(id: id, message: "Bản ghi âm bị lỗi giữa chừng.") }
        onChange?()
    }

    /// Dừng player, xoá tệp tạm, vô hiệu hoá mọi lần tải/phát đang chờ. KHÔNG đổi `coordinator`.
    private func halt() {
        generation += 1
        cleanup()
    }

    private func cleanup() {
        player?.stop()
        player = nil
        if let url = tempFile { AudioTempFiles.remove(url) }
        tempFile = nil
    }

    private static func message(for error: ClientError) -> String {
        switch error {
        case .engineNotRunning, .network: return "Không tải được bản ghi âm — engine chưa chạy hoặc không kết nối được."
        default: return "Không tải được bản ghi âm: \(ErrorText.message(error))"
        }
    }
}
