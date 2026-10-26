import AppKit
import VFlowCore

/// Nguồn tiến trình đang chạy thật, dùng `NSWorkspace` (bộ cung cấp giả nằm trong
/// `VFlowCoreTests` để test `ConflictDetector` không cần chạy ứng dụng khác thật).
struct WorkspaceRunningApps: RunningAppsProvider {
    func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
