import SwiftUI

struct UploadView: View {
    @EnvironmentObject var vm:  PipelineViewModel
    @EnvironmentObject var sse: SSEListener

    private var uploadStep:    StepState? { sse.steps.first(where: { $0.key == "upload" }) }
    private var uploadDone:    Bool       { uploadStep?.status == .done    }
    private var uploadRunning: Bool       { uploadStep?.status == .running }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                youtubeCard
                spotifyCard

                WizardNavBar(
                    onBack: { vm.goTo(.processing) },
                    onNext: { vm.goTo(.done) }
                )
            }
            .padding(32)
        }
    }

    // MARK: - YouTube

    private var youtubeCard: some View {
        WizardCard(title: "Upload to YouTube",
                   subtitle: "Re-upload the trimmed sermon clip to your channel") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Skip YouTube upload").font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $vm.skipYouTubeUpload).toggleStyle(.switch)
                }

                if !vm.skipYouTubeUpload {
                    Divider()

                    if vm.channels.isEmpty {
                        ProgressView("Loading channels…").controlSize(.small)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            SectionHeader(text: "Upload to channel")
                            Picker("Channel", selection: $vm.selectedChannelId) {
                                ForEach(vm.channels) { ch in
                                    Text(ch.title).tag(ch.id)
                                }
                            }
                            .pickerStyle(.menu).frame(maxWidth: 260)
                        }
                    }

                    if let step = uploadStep,
                       step.status == .running || step.status == .done || step.status == .failed {
                        StepProgressRow(step: step)
                    } else if !uploadDone {
                        Button {
                            Task { await vm.runUpload() }
                        } label: {
                            Label("Upload now", systemImage: "arrow.up.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent).tint(.cpPrimary)
                        .disabled(uploadRunning || vm.channels.isEmpty)
                    }

                    if uploadDone { uploadSuccessBanner }
                }
            }
        }
    }

    private var uploadSuccessBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Uploaded successfully!", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.green)
            if !vm.uploadedStudioURL.isEmpty {
                Button {
                    if let url = URL(string: vm.uploadedStudioURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open YouTube Studio →", systemImage: "pencil.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain).foregroundColor(.cpPrimary)
            }
        }
        .padding(12).background(Color.green.opacity(0.06)).cornerRadius(9)
    }

    // MARK: - Spotify

    private var spotifyCard: some View {
        WizardCard(title: "Publish Podcast",
                   subtitle: "Open Spotify for Podcasters to upload the MP3 episode") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "music.note.list")
                        .foregroundColor(Color(red: 0.11, green: 0.73, blue: 0.33))
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.audioFilePath.isEmpty
                             ? "MP3 not ready yet"
                             : URL(fileURLWithPath: vm.audioFilePath).lastPathComponent)
                            .font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if !vm.audioFilePath.isEmpty {
                            Text("File path is copied to clipboard when you open Spotify.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Button {
                    Task { await vm.openSpotify() }
                } label: {
                    Label("Open Spotify for Podcasters", systemImage: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.11, green: 0.73, blue: 0.33))
                .disabled(vm.audioFilePath.isEmpty)
            }
        }
    }
}
