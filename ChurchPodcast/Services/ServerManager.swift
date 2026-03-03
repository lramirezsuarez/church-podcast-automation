import Foundation
import Combine

/// Manages the lifecycle of the embedded Python Flask server.
///
/// Bundle layout after Xcode copies python-server/ and .venv/ into Resources:
///
///   ChurchPodcast.app/
///   └── Contents/
///       └── Resources/
///           ├── python-server/
///           │   └── server.py
///           └── .venv/
///               └── bin/
///                   └── python
///
/// User data (output/, inbox/, client_secrets.json, youtube_token.json)
/// lives in: ~/Library/Application Support/ChurchPodcast/
class ServerManager: ObservableObject {

    static let shared = ServerManager()

    @Published var isRunning    = false
    @Published var startupError: String?

    private var process: Process?
    private let port = 5001

    // MARK: - App Support directory (user data)

    static var appSupportDir: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ChurchPodcast")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        startupError = nil

        guard let serverPath = resolveServerPath() else {
            let expected = Bundle.main.resourceURL?
                .appendingPathComponent("python-server/server.py").path ?? "unknown"
            startupError = "server.py not found in bundle Resources.\n\nExpected:\n\(expected)\n\nFix: run setup.sh then Product → Clean Build Folder and rebuild (⌘B)."
            return
        }

        guard let pythonPath = resolvePythonPath() else {
            let expected = Bundle.main.resourceURL?
                .appendingPathComponent(".venv/bin/python").path ?? "unknown"
            startupError = ".venv/bin/python not found.\n\nExpected:\n\(expected)\n\nFix: run setup.sh to create .venv, then rebuild."
            return
        }

        let dataRoot = Self.appSupportDir.path

        let p = Process()
        p.executableURL = URL(fileURLWithPath: pythonPath)
        p.arguments     = [serverPath]
        p.environment   = ProcessInfo.processInfo.environment.merging([
            "CP_PORT":          "\(port)",
            "PYTHONUNBUFFERED": "1",
            "CP_DATA_ROOT":     dataRoot,
            "VIRTUAL_ENV":      URL(fileURLWithPath: pythonPath)
                                    .deletingLastPathComponent()
                                    .deletingLastPathComponent()
                                    .path,
        ], uniquingKeysWith: { _, new in new })

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in _ = h.availableData }

        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.isRunning = false }
        }

        do {
            try p.run()
            process = p
        } catch {
            startupError = "Failed to launch Python: \(error.localizedDescription)"
            return
        }

        // Poll /status until ready (up to 15 s)
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if await APIService.shared.checkStatus() {
                    await MainActor.run {
                        self.isRunning = true
                        SSEListener.shared.connect()
                    }
                    return
                }
            }
            await MainActor.run {
                self.startupError = "Server did not respond within 15 seconds. Try Product → Clean Build Folder and rebuild."
            }
        }
    }

    func stop() {
        SSEListener.shared.disconnect()
        process?.terminate()
        process = nil
        isRunning = false
    }

    // MARK: - Path resolution

    private func resolveServerPath() -> String? {
        let fm = FileManager.default

        // PRIMARY: bundle Resources (both Debug from DerivedData and Release archive)
        if let res = Bundle.main.resourceURL {
            let p = res.appendingPathComponent("python-server/server.py").path
            if fm.fileExists(atPath: p) { return p }
        }

        // FALLBACK: walk up from the .app to find project folder
        // (useful when running from Xcode before the CopyFiles phase ran)
        var dir = Bundle.main.bundleURL
        for _ in 0..<15 {
            dir = dir.deletingLastPathComponent()
            let p = dir.appendingPathComponent("python-server/server.py").path
            if fm.fileExists(atPath: p) { return p }
        }

        return nil
    }

    private func resolvePythonPath() -> String? {
        let fm = FileManager.default

        // PRIMARY: .venv in bundle Resources
        if let res = Bundle.main.resourceURL {
            let p = res.appendingPathComponent(".venv/bin/python").path
            if fm.fileExists(atPath: p) { return p }
        }

        // FALLBACK: .venv next to server.py in project folder
        if let serverPath = resolveServerPath() {
            let root = URL(fileURLWithPath: serverPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let p = root.appendingPathComponent(".venv/bin/python").path
            if fm.fileExists(atPath: p) { return p }
        }

        // FALLBACK: walk upward
        var dir = Bundle.main.bundleURL
        for _ in 0..<15 {
            dir = dir.deletingLastPathComponent()
            let p = dir.appendingPathComponent(".venv/bin/python").path
            if fm.fileExists(atPath: p) { return p }
        }

        // Homebrew Python as last resort
        for candidate in [
            "/opt/homebrew/opt/python@3.12/bin/python3.12",
            "/usr/local/opt/python@3.12/bin/python3.12",
            "/opt/homebrew/bin/python3",
        ] {
            if fm.fileExists(atPath: candidate) { return candidate }
        }

        return nil
    }
}
