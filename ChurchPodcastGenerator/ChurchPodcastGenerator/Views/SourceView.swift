import SwiftUI
import UniformTypeIdentifiers

struct SourceView: View {
    @EnvironmentObject var vm: PipelineViewModel

    var body: some View {
        VStack(spacing: 24) {
            if vm.mode == .auto {
                autoSourceSection
            } else {
                manualSourceSection
            }

            WizardNavBar(
                nextLabel:    "Continue",
                nextDisabled: !sourceIsValid,
                onBack: { vm.goTo(.welcome) },
                onNext: {
                    vm.goTo(.timestamps)
                    if vm.useAutoDetect && !sourceFilePath.isEmpty {
                        Task { await vm.runAutoDetect() }
                    }
                }
            )
        }
        .padding(32)
        .task { if vm.mode == .manual { await vm.loadInboxFiles() } }
    }

    // MARK: - Auto (URL / Latest)

    private var autoSourceSection: some View {
        WizardCard(title: "YouTube Source",
                   subtitle: "Choose how to get this week's broadcast") {
            VStack(alignment: .leading, spacing: 16) {

                // Toggle: Latest vs Paste URL
                HStack(spacing: 0) {
                    togglePill("Fetch Latest", selected: vm.useFetchLatest) {
                        vm.useFetchLatest = true
                        vm.youtubeURL = ""
                    }
                    togglePill("Paste URL", selected: !vm.useFetchLatest) {
                        vm.useFetchLatest = false
                    }
                }
                .background(Color.cpPrimary.opacity(0.06))
                .cornerRadius(9)

                if vm.useFetchLatest {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.cpPrimary)
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-fetch latest video")
                                .font(.system(size: 13, weight: .medium))
                            Text("Will download the most recent public video from your configured channel.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.cpPrimary.opacity(0.05))
                    .cornerRadius(10)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(text: "YouTube URL")
                        TextField("https://www.youtube.com/watch?v=...", text: $vm.youtubeURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: - Manual (file picker)

    private var manualSourceSection: some View {
        WizardCard(title: "Select Source File",
                   subtitle: "Pick a .mp4 you already downloaded from YouTube Studio") {
            VStack(alignment: .leading, spacing: 16) {

                // Inbox auto-detected files
                if !vm.inboxFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(text: "Detected in inbox/")
                        ForEach(vm.inboxFiles) { file in
                            fileRow(file, selected: vm.selectedInboxFile?.path == file.path) {
                                vm.selectedInboxFile = file
                            }
                        }
                    }
                }

                Divider()

                // Browse button
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType.mpeg4Movie]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url {
                        vm.selectedInboxFile = InboxFile(
                            name:     url.lastPathComponent,
                            path:     url.path,
                            sizeMb:   (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Double ?? 0) ?? 0,
                            modified: ""
                        )
                    }
                } label: {
                    Label("Browse for file…", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)

                if let f = vm.selectedInboxFile {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text(f.name).font(.system(size: 13, weight: .medium))
                        Spacer()
                        InfoBadge(text: "\(String(format: "%.0f", f.sizeMb)) MB")
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.06))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Helpers

    private var sourceIsValid: Bool {
        if vm.mode == .auto {
            return vm.useFetchLatest || !vm.youtubeURL.isEmpty
        } else {
            return vm.selectedInboxFile != nil
        }
    }

    private var sourceFilePath: String {
        vm.mode == .auto ? "" : (vm.selectedInboxFile?.path ?? "")
    }

    private func togglePill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(selected ? Color.cpPrimary : Color.clear)
                .foregroundColor(selected ? .white : .cpPrimary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ file: InboxFile, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "film").foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("\(String(format: "%.0f", file.sizeMb)) MB")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.cpPrimary)
                }
            }
            .padding(10)
            .background(selected ? Color.cpPrimary.opacity(0.07) : Color.cpBackground)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.cpPrimary.opacity(0.3) : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
