import SwiftUI

struct DoneView: View {
    @EnvironmentObject var vm: PipelineViewModel

    var body: some View {
        VStack(spacing: 28) {

            // Success hero
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.7), Color.green],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
                Text("All Done!")
                    .font(.largeTitle).fontWeight(.bold)
                Text("This week's sermon has been processed and uploaded.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Summary card
            WizardCard(title: "Summary") {
                VStack(spacing: 0) {
                    summaryRow(icon: "film.fill",      color: .cpPrimary,
                               label: "Trimmed video",  value: filename(vm.trimmedFilePath))
                    Divider().padding(.vertical, 4)
                    summaryRow(icon: "music.note",     color: .cpAccent,
                               label: "Audio MP3",      value: filename(vm.audioFilePath))
                    if !vm.uploadedVideoId.isEmpty {
                        Divider().padding(.vertical, 4)
                        summaryRow(icon: "checkmark.circle.fill", color: .green,
                                   label: "YouTube upload", value: "Published")
                    }
                }
            }

            // Clean files
            cleanSection

            // Actions
            HStack(spacing: 12) {
                Button {
                    vm.resetForNewRun()
                } label: {
                    Label("New week", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                if !vm.uploadedStudioURL.isEmpty {
                    Button {
                        if let url = URL(string: vm.uploadedStudioURL) { NSWorkspace.shared.open(url) }
                    } label: {
                        Label("YouTube Studio", systemImage: "pencil.circle")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cpPrimary)
                }
            }
        }
        .padding(32)
        .task { await vm.loadCleanFiles() }
    }

    // MARK: - Clean section

    @ViewBuilder
    private var cleanSection: some View {
        if !vm.cleanFiles.isEmpty {
            WizardCard(title: "Clean Up",
                       subtitle: "Delete working files to free up disk space") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.cleanFiles) { file in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(file.label == "output" ? .cpPrimary : .cpAccent)
                                .frame(width: 18)
                            Text(file.name).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Text("\(String(format: "%.0f", file.sizeMb)) MB")
                                .font(.caption).foregroundColor(.secondary)
                            Toggle("", isOn: Binding(
                                get: { vm.cleanFilesSelected.contains(file.path) },
                                set: { on in
                                    if on { vm.cleanFilesSelected.insert(file.path) }
                                    else  { vm.cleanFilesSelected.remove(file.path) }
                                }))
                            .toggleStyle(.checkbox)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total: \(String(format: "%.0f", vm.cleanTotalMB)) MB selected")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await vm.runClean() }
                        } label: {
                            Label("Delete selected", systemImage: "trash")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(vm.cleanFilesSelected.isEmpty)
                    }

                    Text("⚠ This is permanent and cannot be undone.")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func summaryRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color).frame(width: 20)
            Text(label).font(.system(size: 13)).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }

    private func filename(_ path: String) -> String {
        path.isEmpty ? "—" : URL(fileURLWithPath: path).lastPathComponent
    }
}
