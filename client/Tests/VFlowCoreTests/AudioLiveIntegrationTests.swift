import Foundation
import Testing
@testable import VFlowCore

/// Kiểm tích hợp THẬT cho "Lưu âm thanh để nghe lại": lớp client (`EngineAPI` + `AudioPlaybackController`
/// + `AudioExportWriter`) nói chuyện với một engine Node THẬT ở cổng cô lập và VFLOW_HOME tạm. Chạy khi có
/// `VFLOW_LIVE_TEST_PORT`, `VFLOW_LIVE_TEST_TOKEN` và `VFLOW_LIVE_TEST_WAV` (một tệp WAV 16-bit tiếng Việt
/// TỔNG HỢP, không phải giọng người dùng); vắng ⇒ bỏ qua êm. Xem `client/scripts` hoặc báo cáo P2 cho lệnh chạy.
@Suite(.enabled(if: LiveAudio.isConfigured), .serialized)
struct AudioLiveIntegrationTests {
    @Test @MainActor func fullLifecycleListFetchPlayDeleteExportAgainstRealEngine() async throws {
        let live = try LiveAudio()

        // 1. Mặc định engine mới: lưu âm thanh TẮT, danh sách rỗng.
        let before = try await live.audioList()
        #expect(before.items.isEmpty)

        // 2. Bật lưu âm thanh; dictation THẬT tạo vài tệp, mỗi lần trả audio_id.
        let settings = try await live.send(EngineAPI.settingsPutRequest(port: live.port, token: live.token, patch: .init(audioHistory: true, audioHistoryMb: 50, audioHistoryDays: 3)))
        let applied = try EngineAPI.parseSettings(status: settings.status, data: settings.data).get()
        #expect(applied.audioHistory && applied.audioHistoryMb == 50 && applied.audioHistoryDays == 3)

        var ids: [String] = []
        for _ in 0..<3 {
            let r = try await live.send(EngineAPI.transcribeRequest(port: live.port, token: live.token, pcm: live.pcm, mode: .normal, app: nil))
            let t = try EngineAPI.parseTranscribe(status: r.status, data: r.data).get()
            let id = try #require(t.audioId, "dictation thành công khi audio_history bật phải có audio_id")
            ids.append(id)
        }
        #expect(Set(ids).count == 3)

        // 3. Liệt kê: đủ 3 mục, tổng dung lượng khớp từng mục, giới hạn/ngày đúng cài đặt.
        let listed = try await live.audioList()
        #expect(listed.enabled)
        #expect(Set(listed.items.map(\.id)).isSuperset(of: ids))
        #expect(listed.count == 3)
        #expect(listed.bytes == listed.items.map(\.bytes).reduce(0, +))
        #expect(listed.budgetBytes == 50 * 1024 * 1024)
        #expect(listed.days == 3)

        // 4. Tải một bản: WAV nguyên vẹn, đúng số byte đã liệt kê.
        let item = try #require(listed.items.first { $0.id == ids[0] })
        let got = try await live.send(EngineAPI.audioGetRequest(port: live.port, token: live.token, id: ids[0]))
        let wav = try EngineAPI.parseAudioGet(status: got.status, data: got.data).get()
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        #expect(wav.count == item.bytes)

        // 5. Phát qua AudioPlaybackController với fetch THẬT: tệp tạm 0600 tồn tại khi phát, mất khi dừng.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-live-playback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let observed = LivePlaybackObservation()
        let port = live.port, token = live.token
        let controller = AudioPlaybackController(
            directory: dir,
            fetch: { id in
                let req = EngineAPI.audioGetRequest(port: port, token: token, id: id)
                do {
                    let (d, resp) = try await URLSession.shared.data(for: req)
                    return EngineAPI.parseAudioGet(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: d)
                } catch { return .failure(.network(error.localizedDescription)) }
            },
            makePlayer: { LiveFakePlayer(observed) })
        controller.onMissing = { observed.missing.append($0) }
        await controller.toggle(id: ids[0])
        #expect(controller.state == .playing(id: ids[0]))
        #expect(observed.sizesAtStart == [item.bytes], "tệp tạm phải chứa đúng WAV đã tải")
        #expect(observed.permsAtStart == [0o600])
        await controller.toggle(id: ids[0]) // dừng
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty ?? true)

        // 6. Xoá MỘT bản: engine trả ok; tải lại ⇒ 404 ⇒ controller báo "mất" và KHÔNG phát.
        let del = try await live.send(EngineAPI.audioDeleteOneRequest(port: live.port, token: live.token, id: ids[1]))
        #expect(del.status == 200)
        let gone = try await live.send(EngineAPI.audioGetRequest(port: live.port, token: live.token, id: ids[1]))
        guard case .failure(let err) = EngineAPI.parseAudioGet(status: gone.status, data: gone.data) else {
            Issue.record("bản đã xoá phải 404"); return
        }
        #expect(EngineAPI.isAudioMissing(err))
        await controller.toggle(id: ids[1])
        #expect(controller.state == .idle)
        #expect(observed.missing == [ids[1]], "404 ⇒ báo gỡ audio_id")
        #expect(observed.startCount == 1, "không phát thêm bản nào")
        // Xoá lần hai ⇒ 404 (best-effort phía client sẽ chỉ bỏ qua).
        let again = try await live.send(EngineAPI.audioDeleteOneRequest(port: live.port, token: live.token, id: ids[1]))
        #expect(again.status == 404)

        // 7. Id độc hại KHÔNG chạm route khác: "." không được xoá hàng loạt.
        let evil = try await live.send(EngineAPI.audioDeleteOneRequest(port: live.port, token: live.token, id: "."))
        #expect(evil.status == 404)
        #expect(try await live.audioList().count == 2)

        // 8. Xuất ZIP: đúng chữ ký PK, lưu qua AudioExportWriter ⇒ 0600, mở ra có đủ 2 WAV + index.json.
        let exp = try await live.send(EngineAPI.audioExportRequest(port: live.port, token: live.token))
        let zip = try EngineAPI.parseAudioExport(status: exp.status, data: exp.data).get()
        #expect(zip.prefix(2) == Data("PK".utf8))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("vflow-live-export-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: out) }
        try AudioExportWriter.write(zip, to: out)
        let mode = (try FileManager.default.attributesOfItem(atPath: out.path)[.posixPermissions] as? NSNumber)?.intValue
        #expect(mode == 0o600)
        let text = String(decoding: zip, as: UTF8.self)
        #expect(text.contains("index.json"))
        #expect(text.contains("\(ids[0]).wav") && text.contains("\(ids[2]).wav"))
        #expect(!text.contains("\(ids[1]).wav"), "bản đã xoá không được có trong ZIP")

        // 9. Xoá TẤT CẢ: trả số đã xoá thật, danh sách về rỗng.
        let all = try await live.send(EngineAPI.audioDeleteAllRequest(port: live.port, token: live.token))
        #expect(try EngineAPI.parseAudioDeleteAll(status: all.status, data: all.data).get() == 2)
        #expect(try await live.audioList().count == 0)

        // 10. Tắt lại, dictation mới KHÔNG có audio_id.
        let off = try await live.send(EngineAPI.settingsPutRequest(port: live.port, token: live.token, patch: .init(audioHistory: false)))
        #expect(try EngineAPI.parseSettings(status: off.status, data: off.data).get().audioHistory == false)
        let r = try await live.send(EngineAPI.transcribeRequest(port: live.port, token: live.token, pcm: live.pcm, mode: .normal, app: nil))
        #expect(try EngineAPI.parseTranscribe(status: r.status, data: r.data).get().audioId == nil)
        #expect(try await live.audioList().count == 0)
    }

    @Test func teachReturnsRawHeardTextAndWritesNothing() async throws {
        let live = try LiveAudio()
        let r = try await live.send(EngineAPI.teachRequest(port: live.port, token: live.token, pcm: live.pcm))
        let t = try EngineAPI.parseTeach(status: r.status, data: r.data).get()
        #expect(TeachWordVariants.acceptHeard(t.heard) != nil, "câu tổng hợp tiếng Việt phải nghe ra chữ")
        #expect(t.audioMs > 0)
        // /v1/teach không được lưu âm thanh dù audio_history bật.
        let on = try await live.send(EngineAPI.settingsPutRequest(port: live.port, token: live.token, patch: .init(audioHistory: true)))
        _ = try EngineAPI.parseSettings(status: on.status, data: on.data).get()
        let before = try await live.audioList().count
        _ = try await live.send(EngineAPI.teachRequest(port: live.port, token: live.token, pcm: live.pcm))
        #expect(try await live.audioList().count == before)
        _ = try await live.send(EngineAPI.settingsPutRequest(port: live.port, token: live.token, patch: .init(audioHistory: false)))
    }

    /// Tắt Lịch sử ⇒ `AudioHistoryEnforcer` (đường AppController dùng) làm engine THẬT đặt audio_history=false,
    /// và dictation sau đó KHÔNG còn tạo tệp âm thanh mồ côi; bật lại Lịch sử không tự bật lưu âm thanh.
    @Test func historyOffEnforcerTurnsEngineAudioHistoryOffAndStopsOrphans() async throws {
        let live = try LiveAudio()
        let port = live.port, token = live.token
        let put: @Sendable (SettingsPatch) async -> Result<AppSettings, ClientError> = { patch in
            do {
                let (d, resp) = try await URLSession.shared.data(for: EngineAPI.settingsPutRequest(port: port, token: token, patch: patch))
                return EngineAPI.parseSettings(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: d)
            } catch { return .failure(.network(error.localizedDescription)) }
        }
        _ = try await put(.init(audioHistory: true)).get()
        let enforcer = AudioHistoryEnforcer(send: put)
        // Bật lại Lịch sử: không đụng audio_history (vẫn true).
        _ = await enforcer.historyEnabledChanged(to: true)
        let stillOn = try await live.send(EngineAPI.settingsGetRequest(port: port, token: token))
        #expect(try EngineAPI.parseSettings(status: stillOn.status, data: stillOn.data).get().audioHistory)
        // Tắt Lịch sử: engine nhận audio_history=false.
        _ = try await enforcer.historyEnabledChanged(to: false).get()
        let off = try await live.send(EngineAPI.settingsGetRequest(port: port, token: token))
        #expect(try EngineAPI.parseSettings(status: off.status, data: off.data).get().audioHistory == false)
        let before = try await live.audioList().count
        let r = try await live.send(EngineAPI.transcribeRequest(port: port, token: token, pcm: live.pcm, mode: .normal, app: nil))
        #expect(try EngineAPI.parseTranscribe(status: r.status, data: r.data).get().audioId == nil)
        #expect(try await live.audioList().count == before)
    }

    @Test func teachTooLongIs413TooLong() async throws {
        let live = try LiveAudio()
        let long = Data(count: 16000 * 2 * 16) // 16 giây im lặng > 15 giây
        let r = try await live.send(EngineAPI.teachRequest(port: live.port, token: live.token, pcm: long))
        guard case .failure(let e) = EngineAPI.parseTeach(status: r.status, data: r.data) else { Issue.record("phải lỗi"); return }
        #expect(EngineAPI.isTeachTooLong(e))
        #expect(TeachErrorText.message(e).contains("giây"))
    }
}

@MainActor
private final class LivePlaybackObservation {
    var sizesAtStart: [Int] = []
    var permsAtStart: [Int] = []
    var startCount = 0
    var missing: [String] = []
}

@MainActor
private final class LiveFakePlayer: AudioClipPlayer {
    let observed: LivePlaybackObservation
    init(_ observed: LivePlaybackObservation) { self.observed = observed }
    var progress: Double { 0 }
    func start(fileURL: URL, onFinish: @escaping @MainActor (Bool) -> Void) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        observed.sizesAtStart.append((attrs[.size] as? NSNumber)?.intValue ?? -1)
        observed.permsAtStart.append((attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1)
        observed.startCount += 1
    }
    func stop() {}
}

private struct LiveAudio {
    let port: Int
    let token: String
    let pcm: Data

    static var isConfigured: Bool {
        let e = ProcessInfo.processInfo.environment
        return e["VFLOW_LIVE_TEST_PORT"] != nil && e["VFLOW_LIVE_TEST_TOKEN"] != nil && e["VFLOW_LIVE_TEST_WAV"] != nil
    }

    init() throws {
        let e = ProcessInfo.processInfo.environment
        port = Int(e["VFLOW_LIVE_TEST_PORT"] ?? "") ?? 0
        token = e["VFLOW_LIVE_TEST_TOKEN"] ?? ""
        let wav = try Data(contentsOf: URL(fileURLWithPath: e["VFLOW_LIVE_TEST_WAV"] ?? ""))
        pcm = try Self.pcmFromWav(wav)
    }

    /// Cắt phần PCM từ chunk "data" của WAV 16-bit mono 16 kHz.
    static func pcmFromWav(_ wav: Data) throws -> Data {
        var i = 12
        while i + 8 <= wav.count {
            let tag = String(decoding: wav[i..<i + 4], as: UTF8.self)
            let size = Int(wav[i + 4]) | Int(wav[i + 5]) << 8 | Int(wav[i + 6]) << 16 | Int(wav[i + 7]) << 24
            if tag == "data" { return wav.subdata(in: i + 8..<min(wav.count, i + 8 + size)) }
            i += 8 + size + (size & 1)
        }
        throw NSError(domain: "AudioLive", code: 1, userInfo: [NSLocalizedDescriptionKey: "WAV không có chunk data"])
    }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, resp) = try await URLSession.shared.data(for: request)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func audioList() async throws -> AudioHistorySummary {
        let r = try await send(EngineAPI.audioListRequest(port: port, token: token))
        return try EngineAPI.parseAudioList(status: r.status, data: r.data).get()
    }
}
