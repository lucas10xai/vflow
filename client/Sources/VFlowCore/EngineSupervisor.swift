import Foundation

public protocol ProcessHandle: AnyObject {
    var pid: Int32 { get }
    var isRunning: Bool { get }
    /// SIGTERM.
    func terminate()
    /// SIGKILL.
    func kill()
}

public protocol ProcessLauncher {
    /// `onExit` có thể được gọi trên luồng bất kỳ.
    func launch(executable: String, arguments: [String], environment: [String: String],
                onStderrLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) throws -> ProcessHandle
}

public enum HealthProbe: Equatable, Sendable {
    case engine(Health)
    /// Có tiến trình nghe cổng nhưng không phải engine vflow.
    case foreign
    case unreachable
}

public enum EngineState: Equatable, Sendable {
    case stopped
    case starting
    /// `owned`: engine con do app chạy (false = dùng lại engine có sẵn).
    case running(owned: Bool, health: Health)
    case restarting(attempt: Int, delay: Duration)
    case failed(ClientError)

    public var isReady: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Chính sách khởi động lại: lùi dần theo cấp số nhân, tối đa N lần trong cửa sổ trượt.
public struct RestartPolicy: Sendable {
    public var maxRestarts = 5
    public var window: TimeInterval = 60
    public var baseDelay: Duration = .milliseconds(500)
    public var maxDelay: Duration = .seconds(16)
    private var restarts: [TimeInterval] = []

    public init() {}

    public enum Decision: Equatable, Sendable {
        case retry(attempt: Int, after: Duration)
        case giveUp
    }

    public mutating func nextAfterFailure(at now: TimeInterval) -> Decision {
        restarts.removeAll { now - $0 >= window }
        guard restarts.count < maxRestarts else { return .giveUp }
        let attempt = restarts.count + 1
        restarts.append(now)
        var delay = baseDelay
        for _ in 1..<attempt { delay = min(delay * 2, maxDelay) }
        return .retry(attempt: attempt, after: delay)
    }

    public mutating func reset() { restarts.removeAll() }
}

/// Quản lý engine con: dùng lại engine có sẵn, chạy khi thiếu, khởi động lại khi chết, đóng khi thoát.
@MainActor
public final class EngineSupervisor {
    public let spec: EngineLaunchSpec
    private let launcher: ProcessLauncher
    private let probe: () async -> HealthProbe
    private let sleep: (Duration) async -> Void
    private let now: () -> TimeInterval
    public var onStateChange: ((EngineState) -> Void)?

    public private(set) var state: EngineState = .stopped { didSet { if state != oldValue { onStateChange?(state) } } }
    public private(set) var policy = RestartPolicy()
    private var child: ProcessHandle?
    private var generation = 0
    private var stopping = false
    private nonisolated let stderrTail = LineRing(capacity: 40)
    /// Thời gian chờ engine con trả /healthz sau khi chạy.
    public var startupTimeout: Duration = .seconds(30)
    public var pollInterval: Duration = .milliseconds(250)

    public init(spec: EngineLaunchSpec, launcher: ProcessLauncher,
                probe: @escaping () async -> HealthProbe,
                sleep: @escaping (Duration) async -> Void,
                now: @escaping () -> TimeInterval) {
        self.spec = spec
        self.launcher = launcher
        self.probe = probe
        self.sleep = sleep
        self.now = now
    }

    public var ownsChild: Bool { child != nil }
    public var childPID: Int32? { child?.pid }

    /// Khởi động (hoặc thử lại thủ công sau khi đã bỏ cuộc).
    public func start() async {
        stopping = false
        policy.reset()
        state = .starting
        await ensureRunning()
    }

    /// Kiểm định kỳ: cập nhật danh sách model; engine có sẵn biến mất ⇒ tự chạy engine con.
    public func refresh() async {
        guard !stopping else { return }
        switch state {
        case .running(let owned, _):
            switch await probe() {
            case .engine(let h): state = .running(owned: owned, health: h)
            case .foreign: state = .failed(.configInvalid("cổng \(spec.port) bị tiến trình khác chiếm"))
            case .unreachable:
                // Engine con chết sẽ được báo qua onExit; engine ngoài chết thì tự chạy engine của mình.
                if !owned { state = .starting; await ensureRunning() }
            }
        default:
            break
        }
    }

    private func ensureRunning() async {
        switch await probe() {
        case .engine(let h):
            state = .running(owned: false, health: h)
        case .foreign:
            state = .failed(.configInvalid("cổng \(spec.port) bị tiến trình khác chiếm (không phải engine vflow)"))
        case .unreachable:
            await spawn()
        }
    }

    private func spawn() async {
        generation += 1
        let gen = generation
        var env = ProcessInfo.processInfo.environment
        env["VFLOW_PORT"] = String(spec.port)
        let nodeDir = (spec.node as NSString).deletingLastPathComponent
        env["PATH"] = "\(nodeDir):/usr/bin:/bin:/usr/sbin:/sbin"
        do {
            child = try launcher.launch(
                executable: spec.node, arguments: [spec.script, "serve", "--port", String(spec.port)],
                environment: env,
                onStderrLine: { [stderrTail] line in stderrTail.append(line) },
                onExit: { [weak self] code in
                    Task { @MainActor in self?.childExited(generation: gen, code: code) }
                })
        } catch {
            await failed(detail: "không chạy được \(spec.node): \(error.localizedDescription)")
            return
        }
        // Chờ /healthz.
        var waited: Duration = .zero
        while waited < startupTimeout {
            guard gen == generation, !stopping else { return }
            if case .engine(let h) = await probe() {
                guard gen == generation, !stopping else { return }
                state = .running(owned: true, health: h)
                return
            }
            await sleep(pollInterval)
            waited += pollInterval
        }
        guard gen == generation, !stopping else { return }
        let stuck = child
        child = nil
        generation += 1 // bỏ qua onExit của tiến trình bị huỷ này
        stuck?.kill()
        await failed(detail: "engine không trả /healthz sau \(startupTimeout)")
    }

    private func childExited(generation gen: Int, code: Int32) {
        guard gen == generation else { return }
        child = nil
        guard !stopping else { return }
        generation += 1 // vòng chờ /healthz của lần chạy này dừng lại
        Task { await failed(detail: "engine thoát (mã \(code))") }
    }

    private func failed(detail: String) async {
        guard !stopping else { return }
        switch policy.nextAfterFailure(at: now()) {
        case .giveUp:
            let tail = lastStderrLine().map { "; dòng log cuối: \($0)" } ?? ""
            state = .failed(.engineGaveUp(detail + tail))
        case let .retry(attempt, delay):
            state = .restarting(attempt: attempt, delay: delay)
            let gen = generation
            await sleep(delay)
            guard !stopping, gen == generation else { return }
            await ensureRunning()
        }
    }

    /// Đóng engine con (nếu do app chạy): SIGTERM, chờ tối đa `grace`, rồi SIGKILL.
    public func stop(grace: Duration = .seconds(2)) async {
        stopping = true
        generation += 1
        defer { state = .stopped }
        guard let c = child else { return }
        child = nil
        c.terminate()
        var waited: Duration = .zero
        while c.isRunning && waited < grace {
            await sleep(.milliseconds(50))
            waited += .milliseconds(50)
        }
        if c.isRunning { c.kill() }
    }

    public func lastStderrLine() -> String? { stderrTail.lastNonEmpty() }
}

/// Vài dòng stderr cuối của engine (chỉ trong RAM) để giải thích lỗi.
final class LineRing: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let capacity: Int
    init(capacity: Int) { self.capacity = capacity }
    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }
    func lastNonEmpty() -> String? {
        lock.lock(); defer { lock.unlock() }
        return lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}
