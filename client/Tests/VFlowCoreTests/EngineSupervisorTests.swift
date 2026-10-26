import Foundation
import Testing
@testable import VFlowCore

/// Thế giới giả: engine con, engine có sẵn, đồng hồ.
final class FakeWorld: @unchecked Sendable {
    final class Child: ProcessHandle {
        let pid: Int32
        var isRunning = true
        var terminated = false
        var killed = false
        /// Tiến trình bỏ qua SIGTERM (để test SIGKILL).
        var ignoresTerm = false
        var onExit: (@Sendable (Int32) -> Void)?
        init(pid: Int32) { self.pid = pid }
        func terminate() {
            terminated = true
            if !ignoresTerm { die(0) }
        }
        func kill() { killed = true; die(9) }
        func die(_ code: Int32) {
            guard isRunning else { return }
            isRunning = false
            onExit?(code)
        }
    }

    final class Launcher: ProcessLauncher {
        unowned let world: FakeWorld
        init(_ w: FakeWorld) { world = w }
        func launch(executable: String, arguments: [String], environment: [String: String],
                    onStderrLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) throws -> ProcessHandle {
            world.launches.append((executable, arguments, environment))
            let c = Child(pid: Int32(1000 + world.launches.count))
            c.onExit = onExit
            c.ignoresTerm = world.childIgnoresTerm
            world.children.append(c)
            onStderrLine("CẢNH BÁO: lần chạy \(world.launches.count)")
            return c
        }
    }

    var clock: TimeInterval = 1000
    var sleeps: [Duration] = []
    var launches: [(String, [String], [String: String])] = []
    var children: [Child] = []
    var externalEngine = false
    var foreign = false
    /// Engine con trả /healthz ngay khi chạy.
    var childHealthy = true
    var childIgnoresTerm = false
    let health = Health(version: "0.1.0", models: [ModelStatus(id: "zipformer-vi-30m", kind: "local", loaded: true, reason: nil)])

    var liveChild: Child? { children.last { $0.isRunning } }

    func probe() -> HealthProbe {
        if foreign { return .foreign }
        if externalEngine || (childHealthy && liveChild != nil) { return .engine(health) }
        return .unreachable
    }

    @MainActor func makeSupervisor() -> EngineSupervisor {
        let spec = EngineLaunchSpec(node: "/opt/homebrew/bin/node", script: "/repo/bin/vflow.js", repo: "/repo", port: 7611)
        return EngineSupervisor(spec: spec, launcher: Launcher(self),
                                probe: { [unowned self] in self.probe() },
                                sleep: { [unowned self] d in
                                    self.sleeps.append(d)
                                    self.clock += Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
                                },
                                now: { [unowned self] in self.clock })
    }
}

/// Cho các Task nội bộ (onExit ⇒ Task @MainActor) chạy hết.
@MainActor
private func settle() async {
    for _ in 0..<200 { await Task.yield() }
}

@MainActor
@Suite struct EngineSupervisorTests {
    @Test func reusesHealthyExistingEngine() async {
        let w = FakeWorld()
        w.externalEngine = true
        let s = w.makeSupervisor()
        await s.start()
        #expect(w.launches.isEmpty, "đã có engine thì không chạy thêm")
        #expect(s.state == .running(owned: false, health: w.health))
    }

    @Test func spawnsChildWithPortWhenNoneRunning() async {
        let w = FakeWorld()
        let s = w.makeSupervisor()
        await s.start()
        #expect(w.launches.count == 1)
        #expect(w.launches[0].0 == "/opt/homebrew/bin/node")
        #expect(w.launches[0].1 == ["/repo/bin/vflow.js", "serve", "--port", "7611"])
        #expect(w.launches[0].2["VFLOW_PORT"] == "7611")
        #expect(w.launches[0].2["PATH"]?.hasPrefix("/opt/homebrew/bin:") == true)
        #expect(s.state == .running(owned: true, health: w.health))
    }

    @Test func foreignProcessOnPortIsAnErrorNotReused() async {
        let w = FakeWorld()
        w.foreign = true
        let s = w.makeSupervisor()
        await s.start()
        #expect(w.launches.isEmpty)
        guard case .failed(.configInvalid(let m)) = s.state else { Issue.record("phải lỗi: \(s.state)"); return }
        #expect(m.contains("7611"))
    }

    @Test func restartsWithExponentialBackoffThenGivesUp() async {
        let w = FakeWorld()
        let s = w.makeSupervisor()
        await s.start()
        for _ in 0..<5 {
            w.liveChild?.die(1)
            await settle()
            #expect(s.state.isReady, "phải khởi động lại: \(s.state)")
        }
        #expect(w.launches.count == 6)
        #expect(w.sleeps == [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)])
        // Lần chết thứ 6 trong vòng 60 s ⇒ bỏ cuộc, báo rõ.
        w.liveChild?.die(1)
        await settle()
        #expect(w.launches.count == 6)
        guard case .failed(.engineGaveUp(let d)) = s.state else { Issue.record("phải bỏ cuộc: \(s.state)"); return }
        #expect(d.contains("mã 1") && d.contains("CẢNH BÁO"))
        // Thử lại thủ công từ menu: chạy lại được.
        await s.start()
        #expect(s.state.isReady && w.launches.count == 7)
    }

    @Test func crashesSpreadOverTimeDoNotGiveUp() async {
        let w = FakeWorld()
        let s = w.makeSupervisor()
        await s.start()
        for _ in 0..<10 {
            w.clock += 61
            w.liveChild?.die(1)
            await settle()
        }
        #expect(s.state.isReady)
        #expect(w.launches.count == 11)
        #expect(Set(w.sleeps) == [.milliseconds(500)], "mỗi lần chết cách nhau > 60 s ⇒ không lùi thêm")
    }

    @Test func stopTerminatesChildAndDoesNotRestart() async {
        let w = FakeWorld()
        let s = w.makeSupervisor()
        await s.start()
        let child = w.children[0]
        await s.stop()
        await settle()
        #expect(child.terminated && !child.isRunning && !child.killed)
        #expect(w.launches.count == 1)
        #expect(s.state == .stopped)
    }

    @Test func stopKillsChildIgnoringSigterm() async {
        let w = FakeWorld()
        w.childIgnoresTerm = true
        let s = w.makeSupervisor()
        await s.start()
        await s.stop(grace: .milliseconds(200))
        await settle()
        #expect(w.children[0].terminated && w.children[0].killed && !w.children[0].isRunning)
        #expect(w.launches.count == 1)
    }

    @Test func stopDoesNotTouchReusedEngine() async {
        let w = FakeWorld()
        w.externalEngine = true
        let s = w.makeSupervisor()
        await s.start()
        await s.stop()
        #expect(w.children.isEmpty && w.launches.isEmpty)
    }

    @Test func childThatNeverAnswersHealthzIsKilledAndCounted() async {
        let w = FakeWorld()
        w.childHealthy = false
        let s = w.makeSupervisor()
        s.startupTimeout = .seconds(1)
        await s.start()
        await settle()
        #expect(w.children.allSatisfy { $0.killed })
        guard case .failed(.engineGaveUp(let d)) = s.state else { Issue.record("phải bỏ cuộc: \(s.state)"); return }
        #expect(d.contains("/healthz"))
        #expect(w.launches.count == 6)
    }

    @Test func externalEngineDisappearsThenOwnChildStarts() async {
        let w = FakeWorld()
        w.externalEngine = true
        let s = w.makeSupervisor()
        await s.start()
        w.externalEngine = false
        await s.refresh()
        #expect(w.launches.count == 1)
        #expect(s.state == .running(owned: true, health: w.health))
    }

    @Test func prefersEngineThatAppearedDuringBackoff() async {
        let w = FakeWorld()
        let s = w.makeSupervisor()
        await s.start()
        w.externalEngine = true // người dùng tự chạy engine trong lúc engine con chết
        w.liveChild?.die(1)
        await settle()
        #expect(w.launches.count == 1)
        #expect(s.state == .running(owned: false, health: w.health))
    }
}

@Suite struct RestartPolicyTests {
    @Test func windowSlides() {
        var p = RestartPolicy()
        for i in 0..<5 { #expect(p.nextAfterFailure(at: Double(i)) != .giveUp) }
        #expect(p.nextAfterFailure(at: 10) == .giveUp)
        #expect(p.nextAfterFailure(at: 60.5) == .retry(attempt: 5, after: .seconds(8)))
    }

    @Test func delayIsCapped() {
        var p = RestartPolicy()
        p.maxRestarts = 20
        var last: Duration = .zero
        for i in 0..<20 {
            if case .retry(_, let d) = p.nextAfterFailure(at: Double(i)) { last = d }
        }
        #expect(last == .seconds(16))
    }
}

@Suite struct ClientConfigTests {
    func fs(files: [String: String] = [:], exec: Set<String> = []) -> ClientConfig.FileSystem {
        ClientConfig.FileSystem(read: { files[$0].map { Data($0.utf8) } },
                                fileExists: { files[$0] != nil || exec.contains($0) },
                                isExecutable: { exec.contains($0) })
    }

    @Test func repoFromBundleAndNodeCandidatesInOrder() throws {
        let f = fs(files: ["/r/bin/vflow.js": ""], exec: ["/opt/homebrew/bin/node", "/usr/local/bin/node"])
        let s = try ClientConfig.resolve(home: "/Users/u", bundlePath: "/r/client/build/VFlow.app", fs: f).get()
        #expect(s == EngineLaunchSpec(node: "/opt/homebrew/bin/node", script: "/r/bin/vflow.js", repo: "/r", port: 7611))
        let s2 = try ClientConfig.resolve(home: "/Users/u", bundlePath: "/r/client/build/VFlow.app",
                                          fs: self.fs(files: ["/r/bin/vflow.js": ""], exec: ["/Users/u/.local/bin/node", "/usr/local/bin/node"])).get()
        #expect(s2.node == "/Users/u/.local/bin/node")
    }

    @Test func configOverrides() throws {
        let cfg = #"{"repo":"~/src/vflow","node":"~/n/node","port":7700}"#
        let f = fs(files: ["/Users/u/.vflow/client.json": cfg, "/Users/u/src/vflow/bin/vflow.js": ""], exec: ["/Users/u/n/node", "/opt/homebrew/bin/node"])
        let s = try ClientConfig.resolve(home: "/Users/u", bundlePath: "/Applications/VFlow.app", fs: f).get()
        #expect(s == EngineLaunchSpec(node: "/Users/u/n/node", script: "/Users/u/src/vflow/bin/vflow.js", repo: "/Users/u/src/vflow", port: 7700))
    }

    @Test func configuredNodeThatDoesNotRunIsAnErrorNotSilentFallback() {
        let f = fs(files: ["/h/.vflow/client.json": #"{"node":"/nope/node"}"#, "/r/bin/vflow.js": ""], exec: ["/opt/homebrew/bin/node"])
        guard case .failure(.configInvalid(let m)) = ClientConfig.resolve(home: "/h", bundlePath: "/r/client/build/VFlow.app", fs: f) else {
            Issue.record("phải lỗi"); return
        }
        #expect(m.contains("/nope/node"))
    }

    @Test func errorsAreExplicit() {
        let noRepo = ClientConfig.resolve(home: "/h", bundlePath: "/Applications/VFlow.app", fs: fs(exec: ["/opt/homebrew/bin/node"]))
        guard case .failure(.configInvalid(let m1)) = noRepo else { Issue.record("thiếu repo phải lỗi"); return }
        #expect(m1.contains("repo"))
        let noNode = ClientConfig.resolve(home: "/h", bundlePath: "/r/client/build/VFlow.app", fs: fs(files: ["/r/bin/vflow.js": ""]))
        guard case .failure(.configInvalid(let m2)) = noNode else { Issue.record("thiếu node phải lỗi"); return }
        #expect(m2.contains("node"))
        let badJSON = ClientConfig.resolve(home: "/h", bundlePath: nil, fs: fs(files: ["/h/.vflow/client.json": "{oops"]))
        guard case .failure(.configInvalid) = badJSON else { Issue.record("JSON hỏng phải lỗi"); return }
        let badPort = ClientConfig.resolve(home: "/h", bundlePath: nil, fs: fs(files: ["/h/.vflow/client.json": #"{"port":0}"#]))
        guard case .failure(.configInvalid(let m3)) = badPort else { Issue.record("port sai phải lỗi"); return }
        #expect(m3.contains("port"))
    }

    @Test func repoFromBundlePath() {
        #expect(ClientConfig.repoFromBundle("/Users/n/Developer/vflow/client/build/VFlow.app") == "/Users/n/Developer/vflow")
        #expect(ClientConfig.repoFromBundle("/Applications/VFlow.app") == nil)
    }
}
