import Foundation
import Combine
import SwiftUI

// MARK: - Wizard step enum

enum WizardStep: Int, CaseIterable {
    case welcome      = 0
    case source       = 1
    case timestamps   = 2
    case metadata     = 3
    case processing   = 4
    case upload       = 5
    case done         = 6
    case clean        = 7
}

enum PipelineMode { case auto, manual }

// MARK: - PipelineViewModel

@MainActor
class PipelineViewModel: ObservableObject {

    // ── Navigation ───────────────────────────────────────────────
    @Published var currentStep: WizardStep = .welcome
    @Published var mode: PipelineMode = .auto

    // ── Step 1: Source ───────────────────────────────────────────
    @Published var youtubeURL:         String = ""
    @Published var useFetchLatest:     Bool   = false
    @Published var selectedInboxFile:  MediaFile? = nil
    @Published var inboxFiles:         [MediaFile] = []

    // ── Step 2: Timestamps ───────────────────────────────────────
    @Published var startTimestamp:     String = ""
    @Published var endTimestamp:       String = ""
    @Published var useAutoDetect:      Bool   = false
    @Published var detectRunning:      Bool   = false

    // ── Step 3: Metadata ─────────────────────────────────────────
    @Published var episodeTitle:       String = ""
    @Published var episodeDescription: String = ""
    @Published var privacy:            String = "public"
    @Published var useDefaultMetadata: Bool   = true

    // ── Processing results ───────────────────────────────────────
    @Published var downloadedFilePath: String = ""
    @Published var trimmedFilePath:    String = ""
    @Published var audioFilePath:      String = ""

    // ── Upload ───────────────────────────────────────────────────
    @Published var channels:            [YouTubeChannel] = []
    @Published var selectedChannelId:   String = ""
    @Published var skipYouTubeUpload:   Bool   = false
    @Published var uploadedVideoId:     String = ""
    @Published var uploadedStudioURL:   String = ""

    // ── Clean ────────────────────────────────────────────────────
    @Published var cleanFiles:          [CleanFile] = []
    @Published var cleanFilesSelected:  Set<String> = []

    // ── Global ───────────────────────────────────────────────────
    @Published var serverConfig:        ServerConfig?
    @Published var errorMessage:        String?
    @Published var isLoading:           Bool   = false

    private let api     = APIService.shared
    private let sse     = SSEListener.shared
    private var cancels = Set<AnyCancellable>()

    var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    init() {
        sse.$lastError
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] err in self?.errorMessage = err.message }
            .store(in: &cancels)
    }

    // MARK: - Navigation

    func goTo(_ step: WizardStep) {
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = step }
    }

    // MARK: - Startup

    func loadConfig() async {
        guard let cfg = try? await api.getConfig() else { return }
        serverConfig = cfg
        if episodeTitle.isEmpty {
            episodeTitle       = "\(cfg.podcastTitlePrefix) \(today)"
            episodeDescription = cfg.podcastDescription
            privacy            = cfg.youtubePrivacy
        }
    }

    // MARK: - Step 1

    func loadInboxFiles() async {
        inboxFiles = (try? await api.getInboxFiles()) ?? []
    }

    // MARK: - Step 2

    func runAutoDetect() async {
        let path: String
        if mode == .auto {
            path = downloadedFilePath
        } else {
            path = selectedInboxFile?.path ?? ""
        }
        guard !path.isEmpty else { return }

        detectRunning = true
        sse.resetStep("detect")
        try? await api.detectTimestamps(filepath: path)

        // Watch until the detect step completes or fails
        for await steps in sse.$steps.values {
            guard let s = steps.first(where: { $0.key == "detect" }) else { continue }
            if s.status == .done {
                startTimestamp = s.resultPayload["start"] as? String ?? startTimestamp
                endTimestamp   = s.resultPayload["end"]   as? String ?? endTimestamp
                detectRunning  = false
                return
            }
            if s.status == .failed {
                detectRunning = false
                return
            }
        }
    }

    // MARK: - Step 4: Processing

    func runProcessing() async {
        sse.resetStep("download")
        sse.resetStep("trim")
        sse.resetStep("export")

        // If Auto mode, download first
        if mode == .auto {
            let url = useFetchLatest ? "LATEST" : youtubeURL
            try? await api.startDownload(url: url)
            downloadedFilePath = await waitForStep("download", key: "filepath") ?? ""
            guard !downloadedFilePath.isEmpty else { return }
        } else {
            downloadedFilePath = selectedInboxFile?.path ?? ""
        }

        let source = downloadedFilePath
        try? await api.startTrim(filepath: source,
                                  start: startTimestamp,
                                  end:   endTimestamp,
                                  label: today)
        trimmedFilePath = await waitForStep("trim", key: "filepath") ?? ""
        guard !trimmedFilePath.isEmpty else { return }

        try? await api.startExportAudio(filepath: trimmedFilePath, label: today)
        audioFilePath = await waitForStep("export", key: "filepath") ?? ""
    }

    // MARK: - Step 5: Upload

    func loadChannels() async {
        channels = (try? await api.getYouTubeChannels()) ?? []
        if selectedChannelId.isEmpty, let first = channels.first {
            selectedChannelId = first.id
        }
    }

    func runUpload() async {
        guard !skipYouTubeUpload, !trimmedFilePath.isEmpty else { return }
        sse.resetStep("upload")
        try? await api.startYouTubeUpload(
            filepath:    trimmedFilePath,
            title:       episodeTitle,
            description: episodeDescription,
            privacy:     privacy)
        if let id = await waitForStep("upload", key: "video_id") {
            uploadedVideoId   = id
            uploadedStudioURL =
                sse.steps.first(where: { $0.key == "upload" })?
                         .resultPayload["studio_url"] as? String ?? ""
        }
    }

    func openSpotify() async {
        try? await api.openSpotify(filepath: audioFilePath)
    }

    // MARK: - Clean

    func loadCleanFiles() async {
        cleanFiles         = (try? await api.getCleanFiles()) ?? []
        cleanFilesSelected = Set(cleanFiles.map { $0.path })
    }

    func runClean() async {
        _ = try? await api.deleteFiles(paths: Array(cleanFilesSelected))
        await loadCleanFiles()
    }

    var cleanTotalMB: Double {
        cleanFiles
            .filter { cleanFilesSelected.contains($0.path) }
            .reduce(0) { $0 + $1.sizeMb }
    }

    // MARK: - Reset

    func resetForNewRun() {
        youtubeURL         = ""
        useFetchLatest     = false
        selectedInboxFile  = nil
        startTimestamp     = ""
        endTimestamp       = ""
        downloadedFilePath = ""
        trimmedFilePath    = ""
        audioFilePath      = ""
        uploadedVideoId    = ""
        uploadedStudioURL  = ""
        skipYouTubeUpload  = false
        errorMessage       = nil
        sse.resetAll()
        // Reload title with today's date for the next run
        if let cfg = serverConfig {
            episodeTitle       = "\(cfg.podcastTitlePrefix) \(today)"
            episodeDescription = cfg.podcastDescription
            privacy            = cfg.youtubePrivacy
        }
        goTo(.welcome)
    }

    func resetMetadataToDefaults() {
        guard let cfg = serverConfig else { return }
        episodeTitle       = "\(cfg.podcastTitlePrefix) \(today)"
        episodeDescription = cfg.podcastDescription
        privacy            = cfg.youtubePrivacy
    }

    // MARK: - Helpers

    private func waitForStep(_ stepKey: String, key: String) async -> String? {
        for await steps in sse.$steps.values {
            guard let s = steps.first(where: { $0.key == stepKey }) else { continue }
            if s.status == .done   { return s.resultPayload[key] as? String }
            if s.status == .failed { return nil }
        }
        return nil
    }
}
