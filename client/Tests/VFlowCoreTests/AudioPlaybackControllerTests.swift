import Foundation
import Testing
@testable import VFlowCore

@MainActor
private final class FakePlayer: AudioClipPlayer {
    struct Boom: Error {}
    var started: [URL] = []
    var stopCount = 0
    var failStart = false
    var progress: Double = 0
    /// Kiểm ngay lúc `start`: tệp tạm phải tồn tại và là 0600.
    var permsAtStart: [Int] = []
    private var finish: (@MainActor (Bool) -> Void)?

    func start(fileURL: URL, onFinish: @escaping @MainActor (Bool) -> Void) throws {
        if failStart { throw Boom() }
        started.append(fileURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        permsAtStart.append((attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1)
        finish = onFinish
    }

    func stop() {
        stopCount += 1
        finish = nil
    }

    /// Mô phỏng phát hết (hoặc hỏng giữa chừng).
    func complete(ok: Bool = true) { finish?(ok) }
}

@MainActor
private final class Harness {
    let dir: URL
    var players: [FakePlayer] = []
    var missing: [String] = []
    var fetchCalls: [String] = []
    var results: [String: Result<Data, ClientError>] = [:]
    /// Id nào nằm trong đây thì `fetch` treo cho tới khi `release(id)`.
    var gated: Set<String> = []
    fileprivate var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private let failPlayerStart: Bool
    private(set) var controller: AudioPlaybackController!

    init(failPlayerStart: Bool = false) {
        self.failPlayerStart = failPlayerStart
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-playback-test-\(UUID().uuidString)")
        controller = AudioPlaybackController(
            directory: dir,
            fetch: { [unowned self] id in await self.fetch(id) },
            makePlayer: { [unowned self] in self.makePlayer() })
        controller.onMissing = { [unowned self] id in self.missing.append(id) }
    }

    private func makePlayer() -> FakePlayer {
        let p = FakePlayer()
        p.failStart = failPlayerStart
        players.append(p)
        return p
    }

    private func fetch(_ id: String) async -> Result<Data, ClientError> {
        fetchCalls.append(id)
        if gated.contains(id) {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiting[id] = c }
        }
        return results[id] ?? .success(Data("RIFF-fake-wav-\(id)".utf8))
    }

    func release(_ id: String) {
        gated.remove(id)
        waiting.removeValue(forKey: id)?.resume()
    }

    var tempFiles: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }

    /// Chờ tới khi `fetch` của `id` đã bị gọi (task `toggle` chạy nền).
    func waitUntilFetching(_ id: String) async {
        for _ in 0..<200 where !fetchCalls.contains(id) { await Task.yield() }
    }
}

@MainActor
@Suite struct AudioPlaybackControllerTests {
    @Test func playsFromPrivateTempFileAndDeletesItWhenFinished() async {
        let h = Harness(); defer { h.cleanup() }
        await h.controller.toggle(id: "a")
        #expect(h.controller.state == .playing(id: "a"))
        #expect(h.tempFiles.count == 1)
        #expect(h.players[0].permsAtStart == [0o600])
        h.players[0].complete()
        #expect(h.controller.state == .idle)
        #expect(h.tempFiles.isEmpty, "phát xong phải xoá tệp tạm NGAY")
    }

    @Test func togglingTheSameIdStopsAndDeletesTempFile() async {
        let h = Harness(); defer { h.cleanup() }
        await h.controller.toggle(id: "a")
        await h.controller.toggle(id: "a")
        #expect(h.controller.state == .idle)
        #expect(h.players[0].stopCount >= 1)
        #expect(h.tempFiles.isEmpty)
        #expect(h.fetchCalls == ["a"], "dừng không được tải lại")
    }

    @Test func onlyOneClipPlaysAtATime() async {
        let h = Harness(); defer { h.cleanup() }
        await h.controller.toggle(id: "a")
        await h.controller.toggle(id: "b")
        #expect(h.controller.state == .playing(id: "b"))
        #expect(h.players.count == 2)
        #expect(h.players[0].stopCount >= 1, "bản cũ phải bị dừng trước khi phát bản mới")
        #expect(h.tempFiles.count == 1, "chỉ còn tệp tạm của bản đang phát")
        h.players[1].complete()
        #expect(h.tempFiles.isEmpty)
    }

    /// Bản cũ báo "xong" muộn sau khi đã đổi bài không được xoá tệp/làm đổi trạng thái của bản mới.
    @Test func lateFinishOfReplacedClipIsIgnored() async {
        let h = Harness(); defer { h.cleanup() }
        await h.controller.toggle(id: "a")
        let old = h.players[0]
        await h.controller.toggle(id: "b")
        old.complete() // đã bị stop() ⇒ không còn callback; gọi thêm cũng không tác dụng
        #expect(h.controller.state == .playing(id: "b"))
        #expect(h.tempFiles.count == 1)
    }

    @Test func notFoundReportsMissingAndDoesNotPlay() async {
        let h = Harness(); defer { h.cleanup() }
        h.results["gone"] = .failure(.engine(status: 404, code: "not_found", message: "Không có tệp âm thanh này."))
        await h.controller.toggle(id: "gone")
        #expect(h.missing == ["gone"], "404 ⇒ gỡ audio_id khỏi mục")
        #expect(h.controller.state == .idle)
        #expect(h.players.isEmpty)
        #expect(h.tempFiles.isEmpty)
    }

    /// Lỗi tạm (engine chết, 500) KHÔNG được coi là "bản ghi đã mất" — nếu không, một lần engine
    /// khởi động lại sẽ xoá nút nghe lại của mọi câu.
    @Test func transientErrorShowsErrorButKeepsTheAudioReference() async {
        let h = Harness(); defer { h.cleanup() }
        h.results["a"] = .failure(.network("Connection refused"))
        await h.controller.toggle(id: "a")
        #expect(h.missing.isEmpty)
        guard case .error(let id, let message) = h.controller.state else { Issue.record("phải ở trạng thái lỗi"); return }
        #expect(id == "a")
        #expect(!message.isEmpty)
        #expect(h.tempFiles.isEmpty)
        // Bấm lại phải thử lại được (không kẹt ở trạng thái lỗi).
        h.results["a"] = nil
        await h.controller.toggle(id: "a")
        #expect(h.controller.state == .playing(id: "a"))
    }

    @Test func playerStartFailureCleansUpTempFileAndReportsError() async {
        let h = Harness(failPlayerStart: true); defer { h.cleanup() }
        await h.controller.toggle(id: "a")
        guard case .error(let id, _) = h.controller.state else { Issue.record("phải ở trạng thái lỗi"); return }
        #expect(id == "a")
        #expect(h.tempFiles.isEmpty, "không phát được thì cũng không để lại tệp giọng nói")
    }

    @Test func playerFailingMidwayCleansUp() async {
        let h = Harness(); defer { h.cleanup() }
        await h.controller.toggle(id: "a")
        h.players[0].complete(ok: false)
        guard case .error = h.controller.state else { Issue.record("phải ở trạng thái lỗi"); return }
        #expect(h.tempFiles.isEmpty)
    }

    @Test func stopAllStopsPlaybackAndDeletesTempFile() async {
        let h = Harness(); defer { h.cleanup() }
        await h.controller.toggle(id: "a")
        h.controller.stopAll()
        #expect(h.controller.state == .idle)
        #expect(h.tempFiles.isEmpty)
    }

    @Test func stopIfPlayingOnlyAffectsThatId() async {
        let h = Harness(); defer { h.cleanup() }
        await h.controller.toggle(id: "a")
        h.controller.stopIfPlaying(id: "other")
        #expect(h.controller.state == .playing(id: "a"))
        h.controller.stopIfPlaying(id: "a")
        #expect(h.controller.state == .idle)
        #expect(h.tempFiles.isEmpty)
    }

    /// Đang tải bản "a" mà bấm sang "b": khi "a" tải xong muộn, TUYỆT ĐỐI không được phát chồng.
    @Test func slowFetchOfSupersededClipNeverStartsPlayback() async {
        let h = Harness(); defer { h.cleanup() }
        h.gated = ["a"]
        let first = Task { await h.controller.toggle(id: "a") }
        await h.waitUntilFetching("a")
        await h.controller.toggle(id: "b")
        #expect(h.controller.state == .playing(id: "b"))
        h.release("a")
        await first.value
        #expect(h.controller.state == .playing(id: "b"))
        #expect(h.players.count == 1, "chỉ có player của b")
        #expect(h.tempFiles.count == 1)
    }

    @Test func stopWhileLoadingCancelsPlayback() async {
        let h = Harness(); defer { h.cleanup() }
        h.gated = ["a"]
        let first = Task { await h.controller.toggle(id: "a") }
        await h.waitUntilFetching("a")
        h.controller.stopAll()
        h.release("a")
        await first.value
        #expect(h.controller.state == .idle)
        #expect(h.players.isEmpty)
        #expect(h.tempFiles.isEmpty)
    }

    @Test func strayTempFilesFromAPreviousRunArePurgedOnInit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-playback-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("old.wav"))
        _ = AudioPlaybackController(directory: dir, fetch: { _ in .failure(.engineNotRunning) }, makePlayer: { FakePlayer() })
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
}

@Suite struct AudioTempFilesTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vflow-audiofiles-test-\(UUID().uuidString)")
    }

    private func mode(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func fileIs0600AndDirectoryIs0700() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AudioTempFiles.writePrivate(Data("RIFFxxxx".utf8), in: dir)
        #expect(try mode(url) == 0o600)
        #expect(try mode(dir) == 0o700)
        #expect(try Data(contentsOf: url) == Data("RIFFxxxx".utf8))
    }

    @Test func eachWriteGetsItsOwnFile() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = try AudioTempFiles.writePrivate(Data("a".utf8), in: dir)
        let b = try AudioTempFiles.writePrivate(Data("b".utf8), in: dir)
        #expect(a != b)
    }

    @Test func writeNewRefusesToOverwriteExistingFile() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AudioTempFiles.writePrivate(Data("goc".utf8), in: dir)
        #expect(throws: AudioTempFiles.FileError.self) { try AudioTempFiles.writeNew(Data("ghi de".utf8), to: url) }
        #expect(try Data(contentsOf: url) == Data("goc".utf8))
    }

    @Test func purgeRemovesOnlyWavFiles() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try AudioTempFiles.writePrivate(Data("a".utf8), in: dir)
        try Data("keep".utf8).write(to: dir.appendingPathComponent("note.txt"))
        #expect(AudioTempFiles.purge(directory: dir) == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["note.txt"])
    }
}

@Suite struct AudioExportWriterTests {
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-export-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func mode(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func savedZipIs0600AndHasExactBytes() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let dest = dir.appendingPathComponent("vflow-audio.zip")
        let payload = Data((0..<4096).map { UInt8($0 % 251) })
        try AudioExportWriter.write(payload, to: dest)
        #expect(try mode(dest) == 0o600)
        #expect(try Data(contentsOf: dest) == payload)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["vflow-audio.zip"], "không để lại tệp tạm")
    }

    /// Người dùng chọn đè một tệp cũ quyền 0644: tệp mới phải là 0600 (không thừa hưởng quyền cũ).
    @Test func overwritingLooseFileTightensPermissions() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let dest = dir.appendingPathComponent("x.zip")
        try Data("cu".utf8).write(to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)
        try AudioExportWriter.write(Data("moi".utf8), to: dest)
        #expect(try mode(dest) == 0o600)
        #expect(try Data(contentsOf: dest) == Data("moi".utf8))
    }

    @Test func unwritableDestinationThrowsAndLeavesNothingBehind() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-khong-ton-tai-\(UUID().uuidString)")
        let dest = missing.appendingPathComponent("a.zip")
        #expect(throws: AudioTempFiles.FileError.self) { try AudioExportWriter.write(Data("x".utf8), to: dest) }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func renameFailureThrowsAndRemovesTempFile() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        // Đích là một THƯ MỤC không rỗng ⇒ rename tệp đè lên thư mục thất bại.
        let dest = dir.appendingPathComponent("isdir")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dest.appendingPathComponent("inner"))
        #expect(throws: AudioTempFiles.FileError.self) { try AudioExportWriter.write(Data("x".utf8), to: dest) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["isdir"], "tệp tạm phải bị dọn")
    }
}
