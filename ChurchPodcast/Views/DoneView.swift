import SwiftUI

struct DoneView: View {
    @EnvironmentObject var vm: PipelineViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Hero
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.green.opacity(0.7), .green],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 68, height: 68)
                        Image(systemName: "checkmark")
                            .font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                    }
                    Text("All Done!").font(.largeTitle).fontWeight(.bold)
                    Text("This week's sermon has been processed and uploaded.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                // Summary
                WizardCard(title: "Summary") {
                    VStack(spacing: 0) {
                        row(icon: "film.fill",   color: .cpPrimary,
                            label: "Trimmed video", value: fname(vm.trimmedFilePath))
                        Divider().padding(.vertical, 3)
                        row(icon: "music.note",  color: .cpAccent,
                            label: "Audio MP3",     value: fname(vm.audioFilePath))
                        if !vm.uploadedVideoId.isEmpty {
                            Divider().padding(.vertical, 3)
                            row(icon: "checkmark.circle.fill", color: .green,
                                label: "YouTube", value: "Published ✓")
                        }
                    }
                }

                // Clean-up
                if !vm.cleanFiles.isEmpty { cleanCard }

                // Actions
                HStack(spacing: 10) {
                    Button {
                        vm.resetForNewRun()
                    } label: {
                        Label("New week", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                    }
                    .buttonStyle(.bordered)

                    if !vm.uploadedStudioURL.isEmpty {
                        Button {
                            if let u = URL(string: vm.uploadedStudioURL) {
                                NSWorkspace.shared.open(u)
                            }
                        } label: {
                            Label("YouTube Studio", systemImage: "pencil.circle")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                        }
                        .buttonStyle(.bordered).tint(.cpPrimary)
                    }
                }
            }
            .padding(32)
        }
        .task { await vm.loadCleanFiles() }
    }

    // MARK: - Clean card

    private var cleanCard: some View {
        WizardCard(title: "Clean Up",
                   subtitle: "Delete working files to free up disk space") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(vm.cleanFiles) { file in
                    HStack {
                        Toggle("", isOn: Binding(
                            get:  { vm.cleanFilesSelected.contains(file.path) },
                            set:  { on in
                                if on { vm.cleanFilesSelected.insert(file.path) }
                                else  { vm.cleanFilesSelected.remove(file.path) }
                            })).toggleStyle(.checkbox)
                        Image(systemName: file.name.hasSuffix(".mp3") ? "music.note" : "film.fill")
                            .foregroundColor(file.label == "output" ? .cpPrimary : .cpAccent)
                            .frame(width: 16)
                        Text(file.name).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Text("\(Int(file.sizeMb)) MB").font(.caption).foregroundColor(.secondary)
                    }
                }
                Divider()
                HStack {
                    Text("\(Int(vm.cleanTotalMB)) MB selected")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        Task { await vm.runClean() }
                    } label: {
                        Label("Delete selected", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered).tint(.red)
                    .disabled(vm.cleanFilesSelected.isEmpty)
                }
                Text("⚠ This is permanent and cannot be undone.")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func row(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color).frame(width: 18)
            Text(label).font(.system(size: 13)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }

    private func fname(_ path: String) -> String {
        path.isEmpty ? "—" : URL(fileURLWithPath: path).lastPathComponent
    }
}
