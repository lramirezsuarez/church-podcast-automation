import SwiftUI

struct UploadView: View {
    @EnvironmentObject var vm: PipelineViewModel
    @EnvironmentObject var sse: SSEListener

    private var uploadStep: StepState? { sse.steps.first(where: { $0.key == "upload" }) }
    private var uploadDone: Bool { uploadStep?.status == .done }
    private var uploadRunning: Bool { uploadStep?.status == .running }

    var body: some View {
        VStack(spacing: 24) {

            // YouTube upload card
            youtubeCard

            // Spotify card
            spotifyCard

            WizardNavBar(
                nextLabel:    "Finish",
                nextDisabled: false,
                onBack: { vm.goTo(.processing) },
                onNext: { vm.goTo(.done) }
            )
        }
        .padding(32)
    }

    // MARK: - YouTube

    private var youtubeCard: some View {
        WizardCard(title: "Upload to YouTube",
                   subtitle: "Re-upload the trimmed sermon clip to your channel") {
            VStack(alignment: .leading, spacing: 16) {

                // Skip toggle
                HStack {
                    Text("Skip YouTube upload")
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $vm.skipYouTubeUpload)
                        .toggleStyle(.switch)
                }

                if !vm.skipYouTubeUpload {
                    Divider()

                    // Channel picker
                    if !vm.channels.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(text: "Upload to channel")
                            Picker("Channel", selection: $vm.selectedChannelId) {
                                ForEach(vm.channels) { ch in
                                    Text(ch.title).tag(ch.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 260)
                        }
                    } else {
                        ProgressView("Loading channels…").controlSize(.small)
                    }

                    // Upload button / progress
                    if let step = uploadStep, step.status == .running || step.status == .done {
                        StepProgressRow(step: step)
                    } else if !uploadDone {
                        Button {
                            Task { await vm.runUpload() }
                        } label: {
                            Label("Upload now", systemImage: "arrow.up.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 20).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cpPrimary)
                        .disabled(uploadRunning || vm.channels.isEmpty)
                    }

                    // Success result
                    if uploadDone {
                        uploadSuccessBanner
                    }
                }
            }
        }
    }

    private var uploadSuccessBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Uploaded successfully!").font(.system(size: 13, weight: .semibold))
            }
            if !vm.uploadedStudioURL.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.circle").foregroundColor(.cpPrimary)
                    Button("Open YouTube Studio →") {
                        if let url = URL(string: vm.uploadedStudioURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.cpPrimary)
                    .font(.system(size: 13))
                }
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.06))
        .cornerRadius(10)
    }

    // MARK: - Spotify

    private var spotifyCard: some View {
        WizardCard(title: "Publish Podcast",
                   subtitle: "Open Spotify for Podcasters to upload the MP3 episode") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .foregroundColor(Color(red: 0.11, green: 0.73, blue: 0.33))
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.audioFilePath.isEmpty ? "MP3 not ready yet" : URL(fileURLWithPath: vm.audioFilePath).lastPathComponent)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        if !vm.audioFilePath.isEmpty {
                            Text("File path copied to clipboard when you open Spotify.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Button {
                    Task { await vm.openSpotify() }
                } label: {
                    Label("Open Spotify for Podcasters", systemImage: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.11, green: 0.73, blue: 0.33))
                .disabled(vm.audioFilePath.isEmpty)
            }
        }
    }
}
