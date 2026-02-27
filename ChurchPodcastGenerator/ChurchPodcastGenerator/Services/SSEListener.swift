import Foundation
import Combine

// MARK: - Step State

enum StepStatus {
    case idle, running, done, failed
}

struct StepState: Identifiable {
    var id: String { key }
    var key: String
    var label: String
    var status: StepStatus = .idle
    var pct: Int = 0
    var message: String = ""
    var resultPayload: [String: Any] = [:]
}

// MARK: - SSEListener

/// Connects to /events and publishes decoded SSEEvent objects on the main thread.
class SSEListener: ObservableObject {

    static let shared = SSEListener()

    @Published var steps: [StepState] = [
        StepState(key: "download", label: "Downloading video"),
        StepState(key: "detect",   label: "Detecting timestamps"),
        StepState(key: "trim",     label: "Trimming & normalizing"),
        StepState(key: "export",   label: "Exporting MP3"),
        StepState(key: "upload",   label: "Uploading to YouTube"),
    ]

    @Published var lastError: (step: String, message: String)?

    private var task: URLSessionDataTask?
    private var buffer = ""

    func connect() {
        guard let url = URL(string: "\(APIService.shared.base)/events") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = .infinity

        task?.cancel()
        let session = URLSession(configuration: .default, delegate: SSEDelegate(listener: self), delegateQueue: nil)
        task = session.dataTask(with: request)
        task?.resume()
    }

    func disconnect() {
        task?.cancel()
        task = nil
    }

    func resetStep(_ key: String) {
        DispatchQueue.main.async {
            if let i = self.steps.firstIndex(where: { $0.key == key }) {
                self.steps[i].status  = .idle
                self.steps[i].pct     = 0
                self.steps[i].message = ""
                self.steps[i].resultPayload = [:]
            }
        }
    }

    func resetAll() {
        DispatchQueue.main.async {
            for i in self.steps.indices {
                self.steps[i].status  = .idle
                self.steps[i].pct     = 0
                self.steps[i].message = ""
                self.steps[i].resultPayload = [:]
            }
            self.lastError = nil
        }
    }

    // Called by SSEDelegate
    func handleLine(_ line: String) {
        buffer += line + "\n"

        // SSE messages are separated by blank lines
        guard buffer.contains("\n\n") else { return }

        let messages = buffer.components(separatedBy: "\n\n")
        buffer = messages.last ?? ""

        for msg in messages.dropLast() {
            parse(msg)
        }
    }

    private func parse(_ raw: String) {
        var eventName = ""
        var dataStr   = ""

        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("event:") {
                eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataStr = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
        }

        guard !eventName.isEmpty, !dataStr.isEmpty,
              let data = dataStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let step    = json["step"]    as? String ?? ""
        let pct     = json["pct"]     as? Int    ?? 0
        let message = json["message"] as? String ?? ""

        DispatchQueue.main.async {
            switch eventName {
            case "progress":
                self.update(step: step, status: .running, pct: pct, message: message)
            case "done":
                self.update(step: step, status: .done, pct: 100, message: message, payload: json)
            case "error":
                self.update(step: step, status: .failed, pct: 0, message: message)
                self.lastError = (step: step, message: message)
            default:
                break
            }
        }
    }

    private func update(step: String, status: StepStatus, pct: Int, message: String, payload: [String: Any] = [:]) {
        if let i = steps.firstIndex(where: { $0.key == step }) {
            steps[i].status         = status
            steps[i].pct            = pct
            steps[i].message        = message
            steps[i].resultPayload  = payload
        }
    }
}

// MARK: - URLSession Delegate for streaming

private class SSEDelegate: NSObject, URLSessionDataDelegate {
    weak var listener: SSEListener?
    init(listener: SSEListener) { self.listener = listener }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.components(separatedBy: "\n") {
            listener?.handleLine(line)
        }
    }
}
