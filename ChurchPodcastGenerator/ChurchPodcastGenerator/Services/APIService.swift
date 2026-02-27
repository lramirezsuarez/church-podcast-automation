import Foundation
import Observation

// MARK: - Models

struct ServerConfig: Codable {
    var podcastTitlePrefix: String
    var podcastDescription: String
    var youtubePrivacy: String
    var loudnessTarget: String
    var outputDir: String
    var inboxDir: String
    var hasClientSecrets: Bool
    var hasToken: Bool

    enum CodingKeys: String, CodingKey {
        case podcastTitlePrefix  = "podcast_title_prefix"
        case podcastDescription  = "podcast_description"
        case youtubePrivacy      = "youtube_privacy"
        case loudnessTarget      = "loudness_target"
        case outputDir           = "output_dir"
        case inboxDir            = "inbox_dir"
        case hasClientSecrets    = "has_client_secrets"
        case hasToken            = "has_token"
    }
}

struct InboxFile: Codable, Identifiable {
    var id: String { path }
    var name: String
    var path: String
    var sizeMb: Double
    var modified: String

    enum CodingKeys: String, CodingKey {
        case name, path, modified
        case sizeMb = "size_mb"
    }
}

struct YouTubeChannel: Codable, Identifiable {
    var id: String
    var title: String
    var thumbnail: String
}

struct CleanFile: Codable, Identifiable {
    var id: String { path }
    var label: String
    var name: String
    var path: String
    var sizeMb: Double

    enum CodingKeys: String, CodingKey {
        case label, name, path
        case sizeMb = "size_mb"
    }
}

// MARK: - SSE Event

struct SSEEvent {
    enum Kind { case progress, done, error }
    var kind: Kind
    var step: String
    var pct: Int
    var message: String
    var payload: [String: Any]
}

// MARK: - APIService

@Observable
class APIService {

    static let shared = APIService()
    let base = "http://localhost:5001"

    // MARK: Status

    func checkStatus() async -> Bool {
        guard let url = URL(string: "\(base)/status") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: Config

    func getConfig() async throws -> ServerConfig {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base)/config")!)
        return try JSONDecoder().decode(ServerConfig.self, from: data)
    }

    // MARK: Inbox

    func getInboxFiles() async throws -> [InboxFile] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base)/inbox/files")!)
        return try JSONDecoder().decode([InboxFile].self, from: data)
    }

    // MARK: YouTube channels

    func getYouTubeChannels() async throws -> [YouTubeChannel] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base)/youtube/channels")!)
        return try JSONDecoder().decode([YouTubeChannel].self, from: data)
    }

    // MARK: Clean files

    func getCleanFiles() async throws -> [CleanFile] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base)/clean/list")!)
        return try JSONDecoder().decode([CleanFile].self, from: data)
    }

    func deleteFiles(paths: [String]) async throws -> Int {
        var req = URLRequest(url: URL(string: "\(base)/clean/delete")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["paths": paths])
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["deleted"] as? [Any])?.count ?? 0
    }

    // MARK: Pipeline steps

    func startDownload(url: String) async throws {
        try await post("/download", body: ["url": url])
    }

    func detectTimestamps(filepath: String) async throws {
        try await post("/detect-timestamps", body: ["filepath": filepath])
    }

    func startTrim(filepath: String, start: String, end: String, label: String) async throws {
        try await post("/trim", body: ["filepath": filepath, "start": start, "end": end, "label": label])
    }

    func startExportAudio(filepath: String, label: String) async throws {
        try await post("/export-audio", body: ["filepath": filepath, "label": label])
    }

    func startYouTubeUpload(filepath: String, title: String, description: String, privacy: String) async throws {
        try await post("/youtube/upload", body: [
            "filepath": filepath, "title": title,
            "description": description, "privacy": privacy
        ])
    }

    func openSpotify(filepath: String) async throws {
        try await post("/spotify/open", body: ["filepath": filepath])
    }

    // MARK: Private helpers

    @discardableResult
    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: URL(string: "\(base)\(path)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}
