import Foundation

/// Bộ chạy tiến trình thật (Foundation.Process). stdout bỏ đi; stderr giữ vài dòng cuối trong RAM.
public struct FoundationProcessLauncher: ProcessLauncher {
    public init() {}

    final class Handle: ProcessHandle {
        let process: Process
        init(_ p: Process) { process = p }
        var pid: Int32 { process.processIdentifier }
        var isRunning: Bool { process.isRunning }
        func terminate() { if process.isRunning { process.terminate() } }
        func kill() { if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) } }
    }

    public func launch(executable: String, arguments: [String], environment: [String: String],
                       onStderrLine: @escaping @Sendable (String) -> Void,
                       onExit: @escaping @Sendable (Int32) -> Void) throws -> ProcessHandle {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardError = pipe
        let splitter = LineSplitter(onLine: onStderrLine)
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { splitter.feed(d) }
        }
        p.terminationHandler = { proc in onExit(proc.terminationStatus) }
        try p.run()
        return Handle(p)
    }
}

final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private let onLine: @Sendable (String) -> Void
    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }
    func feed(_ d: Data) {
        lock.lock()
        pending.append(d)
        var lines: [String] = []
        while let nl = pending.firstIndex(of: 0x0a) {
            lines.append(String(decoding: pending[pending.startIndex..<nl], as: UTF8.self))
            pending = Data(pending[(nl + 1)...])
        }
        if pending.count > 8192 { pending.removeAll() }
        lock.unlock()
        lines.forEach(onLine)
    }
}
