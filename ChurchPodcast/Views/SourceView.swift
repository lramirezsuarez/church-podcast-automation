import SwiftUI
import UniformTypeIdentifiers

struct SourceView: View {
    @EnvironmentObject var vm: PipelineViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if vm.mode == .auto { autoSection }
                else               { manualSection }

                WizardNavBar(
                    nextDisabled: !isValid,
                    onBack: { vm.goTo(.welcome) },
                    onNext: { vm.goTo(.timestamps) }
                )
            }
            .padding(32)
        }
        .task { if vm.mode == .manual { await vm.loadInboxFiles() } }
    }

    // MARK: - Auto

    private var autoSection: some View {
        WizardCard(title: "YouTube Source",
                   subtitle: "Choose how to get this week's broadcast") {
            VStack(alignment: .leading, spacing: 14) {
                PillToggle(labelA: "Fetch Latest", labelB: "Paste URL",
                           aSelected: $vm.useFetchLatest)

                if vm.useFetchLatest {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.cpPrimary).font(.system(size: 18))
                        Text("Will download the most recent video from your configured channel.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(10).background(Color.cpPrimary.opacity(0.05)).cornerRadius(9)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionHeader(text: "YouTube URL")
                        TextField("https://www.youtube.com/watch?v=…", text: $vm.youtubeURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: - Manual

    private var manualSection: some View {
        WizardCard(title: "Select Source File",
                   subtitle: "Pick the .mp4 you downloaded from YouTube Studio") {
            VStack(alignment: .leading, spacing: 14) {

                if !vm.inboxFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionHeader(text: "Detected in inbox/")
                        ForEach(vm.inboxFiles) { file in
                            fileRow(file)
                        }
                    }
                    Divider()
                }

                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType.mpeg4Movie]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        vm.selectedInboxFile = MediaFile(
                            name:     url.lastPathComponent,
                            path:     url.path,
                            sizeMb:   (try? url.resourceValues(
                                forKeys: [.fileSizeKey]).fileSize.map {
                                    Double($0) / 1_048_576 }) ?? 0,
                            modified: "")
                    }
                } label: {
                    Label("Browse for file…", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)

                if let f = vm.selectedInboxFile {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text(f.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer()
                        InfoBadge(text: "\(Int(f.sizeMb)) MB")
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.06)).cornerRadius(8)
                }
            }
        }
    }

    private func fileRow(_ file: MediaFile) -> some View {
        let selected = vm.selectedInboxFile?.path == file.path
        return Button { vm.selectedInboxFile = file } label: {
            HStack {
                Image(systemName: "film").foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text("\(Int(file.sizeMb)) MB").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.cpPrimary)
                }
            }
            .padding(9)
            .background(selected ? Color.cpPrimary.opacity(0.07) : Color.cpBackground)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.cpPrimary.opacity(0.3) : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private var isValid: Bool {
        vm.mode == .auto
            ? (vm.useFetchLatest || !vm.youtubeURL.isEmpty)
            : vm.selectedInboxFile != nil
    }
}
