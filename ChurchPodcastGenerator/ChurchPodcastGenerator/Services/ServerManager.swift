import Foundation
import Observation
import Combine

/// Manages the lifecycle of the embedded Python Flask server.
/// The server is bundled inside the app and started/stopped with the app.
@Observable
class ServerManager {

    static let shared = ServerManager()

    var isRunning = false
    var startupError: String?

    private var process: Process?
    private let port = 5001

    /// Start the server. Looks for the Python venv and server.py relative to the app bundle.
    func start() {
        guard !isRunning else { return }

        // During development: server.py lives in the repo next to the Xcode project.
        // In a distributed app: bundle it inside Resources/.
        let serverPath = resolveServerPath()
        guard FileManager.default.fileExists(atPath: serverPath) else {
            startupError = "server.py not found at \(serverPath)"
            return
        }

        let pythonPath = resolvePythonPath()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: pythonPath)
        p.arguments     = [serverPath]
        p.environment   = ProcessInfo.processInfo.environment.merging(
            ["CP_PORT": "\(port)", "PYTHONUNBUFFERED": "1"],
            uniquingKeysWith: { _, new in new }
        )

        // Pipe stdout/stderr so we can detect when server is ready
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe

        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.isRunning = false }
        }

        do {
            try p.run()
            process = p
        } catch {
            startupError = "Failed to start server: \(error.localizedDescription)"
            return
        }

        // Poll until the server responds (max 10 seconds)
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let alive = await APIService.shared.checkStatus()
                if alive {
                    await MainActor.run {
                        self.isRunning = true
                        SSEListener.shared.connect()
                    }
                    return
                }
            }
            await MainActor.run {
                self.startupError = "Server did not respond within 10 seconds."
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

    private func resolveServerPath() -> String {
        let fm = FileManager.default

        // 0. Explicit override for development via environment variable
        if let override = ProcessInfo.processInfo.environment["CP_SERVER_PATH"],
           fm.fileExists(atPath: override) {
            return override
        }

        // 1. Bundled inside the app (Resources/python-server/server.py)
        if let bundled = Bundle.main.path(forResource: "server", ofType: "py", inDirectory: "python-server") {
            return bundled
        }

        // 2. Try common development locations relative to the project root.
        // If Xcode provides SRCROOT via the scheme environment, use it to resolve candidates.
        if let srcroot = ProcessInfo.processInfo.environment["SRCROOT"] {
            let candidates = [
                "\(srcroot)/python-server/server.py",
                "\(srcroot)/server/server.py",
                "\(srcroot)/backend/server.py"
            ]
            if let found = candidates.first(where: { fm.fileExists(atPath: $0) }) {
                return found
            }
        }

        // 3. As a last resort, try a few candidates relative to the user's home directory.
        let home = fm.homeDirectoryForCurrentUser.path
        let homeCandidates = [
            "\(home)/python-server/server.py",
            "\(home)/Projects/python-server/server.py"
        ]
        if let found = homeCandidates.first(where: { fm.fileExists(atPath: $0) }) {
            return found
        }

        // 4. Fallback: return a placeholder path (caller will validate and surface an error)
        return "server.py"
    }

    private func resolvePythonPath() -> String {
        // 1. Check for venv next to the repo root
        let appDir = Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let venvPython = appDir.appendingPathComponent(".venv/bin/python3").path
        if FileManager.default.fileExists(atPath: venvPython) {
            return venvPython
        }
        // 2. Homebrew Python 3.12
        let brewPython = "/opt/homebrew/opt/python@3.12/bin/python3.12"
        if FileManager.default.fileExists(atPath: brewPython) {
            return brewPython
        }
        // 3. System fallback
        return "/usr/bin/python3"
    }
}
