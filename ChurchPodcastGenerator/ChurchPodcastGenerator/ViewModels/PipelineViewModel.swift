import Foundation
import Combine
import SwiftUI

// MARK: - Wizard Step Enum

enum WizardStep: Int, CaseIterable {
    case welcome      = 0
    case source       = 1   // Mode A: URL/Latest  |  Mode B: pick file
    case timestamps   = 2
    case metadata     = 3
    case processing   = 4   // trim + export
    case upload       = 5
    case done         = 6
    case clean        = 7   // can be entered from welcome or done
}

enum PipelineMode {
    case auto    // download from YouTube
    case manual  // use local file
}

// MARK: - PipelineViewModel

@MainActor
class PipelineViewModel: ObservableObject {

    // Wizard navigation
    @Published var currentStep: WizardStep = .welcome
    @Published var mode: PipelineMode = .auto

    // Step 1 — Source
    @Published var youtubeURL: String        = ""
    @Published var useFetchLatest: Bool      = false
    @Published var selectedInboxFile: InboxFile? = nil
    @Published var inboxFiles: [InboxFile]   = []

    // Step 2 — Timestamps
    @Published var startTimestamp: String    = ""
    @Published var endTimestamp: String      = ""
    @Published var useAutoDetect: Bool       = false
    @Published var detectRunning: Bool       = false

    // Step 3 — Metadata
    @Published var episodeTitle: String      = ""
    @Published var episodeDescription: String = ""
    @Published var privacy: String           = "public"
    @Published var useDefaultMetadata: Bool  = true

    // Step 4 — Processing results
    @Published var downloadedFilePath: String  = ""
    @Published var trimmedFilePath: String     = ""
    @Published var audioFilePath: String       = ""

    // Step 5 — Upload
    @Published var channels: [YouTubeChannel] = []
    @Published var selectedChannelId: String  = ""
    @Published var skipYouTubeUpload: Bool    = false
    @Published var uploadedVideoId: String    = ""
    @Published var uploadedStudioURL: String  = ""

    // Clean
    @Published var cleanFiles: [CleanFile]    = []
    @Published var cleanFilesSelected: Set<String> = []

    // Global state
    @Published var serverConfig: ServerConfig?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private let api    = APIService.shared
    private let sse    = SSEListener.shared
    private var cancellables = Set<AnyCancellable>()

    var today: String { DateFormatter.yyyyMMdd.string(from: Date()) }

    init() {
        // Mirror SSE errors into the VM
        sse.$lastError
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] err in
                self?.errorMessage = err.message
            }
            .store(in: &cancellables)
    }

    // MARK: - Navigation helpers

    func goTo(_ step: WizardStep) {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = step
        }
    }

    func goNext() {
        let all = WizardStep.allCases
        guard let idx = all.firstIndex(of: currentStep), idx + 1 < all.count else { return }
        goTo(all[idx + 1])
    }

    // MARK: - Startup

    func loadConfig() async {
        guard let config = try? await api.getConfig() else { return }
        serverConfig = config

        let prefix = config.podcastTitlePrefix
        episodeTitle       = "\(prefix) \(today)"
        episodeDescription = config.podcastDescription
        privacy            = config.youtubePrivacy
    }

    // MARK: - Step 1: Source

    func loadInboxFiles() async {
        inboxFiles = (try? await api.getInboxFiles()) ?? []
    }

    // MARK: - Step 2: Timestamps

    func runAutoDetect() async {
        let path = mode == .auto ? downloadedFilePath : (selectedInboxFile?.path ?? "")
        guard !path.isEmpty else { return }
        detectRunning = true
        sse.resetStep("detect")
        try? await api.detectTimestamps(filepath: path)

        // Wait for SSE done/error
        for await _ in sse.$steps.values {
            if let s = sse.steps.first(where: { $0.key == "detect" }) {
                if s.status == .done {
                    startTimestamp = s.resultPayload["start"] as? String ?? startTimestamp
                    endTimestamp   = s.resultPayload["end"]   as? String ?? endTimestamp
                    detectRunning  = false
                    return
                } else if s.status == .failed {
                    detectRunning = false
                    return
                }
            }
        }
    }

    // MARK: - Step 4: Processing

    func runProcessing() async {
        sse.resetStep("download")
        sse.resetStep("trim")
        sse.resetStep("export")

        // A: download first if needed
        if mode == .auto {
            let url = useFetchLatest ? "LATEST" : youtubeURL
            try? await api.startDownload(url: url)
            // Wait for download to complete
            downloadedFilePath = await waitForStepDone("download", payloadKey: "filepath") ?? ""
            guard !downloadedFilePath.isEmpty else { return }
        } else {
            downloadedFilePath = selectedInboxFile?.path ?? ""
        }

        // Trim
        let sourcePath = downloadedFilePath
        try? await api.startTrim(filepath: sourcePath, start: startTimestamp, end: endTimestamp, label: today)
        trimmedFilePath = await waitForStepDone("trim", payloadKey: "filepath") ?? ""
        guard !trimmedFilePath.isEmpty else { return }

        // Export audio
        try? await api.startExportAudio(filepath: trimmedFilePath, label: today)
        audioFilePath = await waitForStepDone("export", payloadKey: "filepath") ?? ""
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
            filepath: trimmedFilePath,
            title: episodeTitle,
            description: episodeDescription,
            privacy: privacy
        )
        if let id = await waitForStepDone("upload", payloadKey: "video_id") {
            uploadedVideoId    = id
            uploadedStudioURL  = sse.steps.first(where: { $0.key == "upload" })?.resultPayload["studio_url"] as? String ?? ""
        }
    }

    func openSpotify() async {
        try? await api.openSpotify(filepath: audioFilePath)
    }

    // MARK: - Clean

    func loadCleanFiles() async {
        cleanFiles = (try? await api.getCleanFiles()) ?? []
        cleanFilesSelected = Set(cleanFiles.map { $0.path })
    }

    func runClean() async {
        let paths = Array(cleanFilesSelected)
        _ = try? await api.deleteFiles(paths: paths)
        await loadCleanFiles()
        // If called from done step, reset for a fresh run
        if currentStep == .done || currentStep == .clean {
            resetForNewRun()
        }
    }

    var cleanTotalMB: Double {
        cleanFiles.filter { cleanFilesSelected.contains($0.path) }.reduce(0) { $0 + $1.sizeMb }
    }

    // MARK: - Helpers

    private func waitForStepDone(_ key: String, payloadKey: String) async -> String? {
        for await steps in sse.$steps.values {
            if let s = steps.first(where: { $0.key == key }) {
                if s.status == .done   { return s.resultPayload[payloadKey] as? String }
                if s.status == .failed { return nil }
            }
        }
        return nil
    }

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
        goTo(.welcome)
    }
}

// MARK: - DateFormatter helper

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
