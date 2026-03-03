import Foundation
import Combine

// MARK: - Step state

enum StepStatus { case idle, running, done, failed }

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

/// Subscribes to GET /events and publishes decoded progress events on the
/// main thread so SwiftUI views can observe them directly.
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

    // MARK: - Connection management

    func connect() {
        guard let url = URL(string: "\(APIService.shared.baseURL)/events") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = .infinity

        task?.cancel()
        let session = URLSession(
            configuration: .default,
            delegate: SSESessionDelegate(listener: self),
            delegateQueue: nil)
        task = session.dataTask(with: req)
        task?.resume()
    }

    func disconnect() {
        task?.cancel()
        task = nil
    }

    // MARK: - State helpers

    func resetStep(_ key: String) {
        DispatchQueue.main.async {
            if let i = self.steps.firstIndex(where: { $0.key == key }) {
                self.steps[i] = StepState(
                    key:   self.steps[i].key,
                    label: self.steps[i].label)
            }
        }
    }

    func resetAll() {
        DispatchQueue.main.async {
            self.steps = self.steps.map { s in
                StepState(key: s.key, label: s.label)
            }
            self.lastError = nil
        }
    }

    // MARK: - Internal parsing (called by delegate)

    func receive(text: String) {
        buffer += text
        // SSE messages are double-newline separated
        while let range = buffer.range(of: "\n\n") {
            let message = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            parseMessage(message)
        }
    }

    private func parseMessage(_ raw: String) {
        var eventName = ""
        var dataStr   = ""

        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("event:") {
                eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataStr   = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
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
                self.updateStep(step, status: .running, pct: pct, message: message)
            case "done":
                self.updateStep(step, status: .done, pct: 100, message: message, payload: json)
            case "error":
                self.updateStep(step, status: .failed, pct: 0, message: message)
                self.lastError = (step: step, message: message)
            default:
                break
            }
        }
    }

    private func updateStep(_ key: String, status: StepStatus, pct: Int,
                             message: String, payload: [String: Any] = [:]) {
        guard let i = steps.firstIndex(where: { $0.key == key }) else { return }
        steps[i].status        = status
        steps[i].pct           = pct
        steps[i].message       = message
        steps[i].resultPayload = payload
    }
}

// MARK: - URLSession streaming delegate

private class SSESessionDelegate: NSObject, URLSessionDataDelegate {
    weak var listener: SSEListener?
    init(listener: SSEListener) { self.listener = listener }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        listener?.receive(text: text)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        // Auto-reconnect after a short delay (server restart, etc.)
        if let error, (error as NSError).code != NSURLErrorCancelled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.listener?.connect()
            }
        }
    }
}
