import SwiftUI

struct CleanView: View {
    @EnvironmentObject var vm: PipelineViewModel
    @State private var confirmationPhase: Int = 0  // 0 = list, 1 = first confirm, 2 = type DELETE
    @State private var typedConfirm: String = ""
    @State private var isDeleting = false
    @State private var deletedCount: Int? = nil

    var body: some View {
        VStack(spacing: 24) {
            switch confirmationPhase {
            case 0: listPhase
            case 1: firstConfirmPhase
            case 2: typeDeletePhase
            default: successPhase
            }
        }
        .padding(32)
        .task { await vm.loadCleanFiles() }
    }

    // MARK: - Phase 0: file list

    private var listPhase: some View {
        VStack(spacing: 24) {
            WizardCard(
                title: "Clean Files",
                subtitle: "Select files to permanently delete"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if vm.cleanFiles.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Nothing to clean — all folders are empty.")
                                .font(.system(size: 13))
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.06))
                        .cornerRadius(10)
                    } else {
                        // Select all / none
                        HStack {
                            Button("Select all") {
                                vm.cleanFilesSelected = Set(vm.cleanFiles.map { $0.path })
                            }
                            .buttonStyle(.plain).font(.caption).foregroundColor(.cpPrimary)

                            Text("·").foregroundColor(.secondary)

                            Button("Select none") {
                                vm.cleanFilesSelected = []
                            }
                            .buttonStyle(.plain).font(.caption).foregroundColor(.cpPrimary)

                            Spacer()

                            Text("\(vm.cleanFiles.count) file(s)  ·  \(String(format: "%.1f", totalMB)) MB total")
                                .font(.caption).foregroundColor(.secondary)
                        }

                        Divider()

                        ForEach(groupedFiles, id: \.0) { group, files in
                            VStack(alignment: .leading, spacing: 6) {
                                SectionHeader(text: group == "output" ? "Output folder" : "Inbox folder")
                                ForEach(files) { file in
                                    fileRow(file)
                                }
                            }
                        }
                    }
                }
            }

            WizardNavBar(
                backLabel:    "← Back",
                nextLabel:    "Delete Selected",
                nextDisabled: vm.cleanFilesSelected.isEmpty,
                onBack: { vm.goTo(.welcome) },
                onNext: { confirmationPhase = 1 }
            )
        }
    }

    // MARK: - Phase 1: first confirmation

    private var firstConfirmPhase: some View {
        VStack(spacing: 24) {
            WizardCard(title: "Are you sure?", subtitle: "This action cannot be undone") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange).font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(vm.cleanFilesSelected.count) file(s) will be permanently deleted")
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(String(format: "%.1f", selectedMB)) MB will be freed")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(10)

                    Text("Make sure you have already uploaded everything to YouTube and Spotify before deleting.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("← Go back") { confirmationPhase = 0 }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                Spacer()
                Button("Yes, continue") { confirmationPhase = 2 }
                    .buttonStyle(.borderedProminent).tint(.orange)
            }
        }
    }

    // MARK: - Phase 2: type DELETE

    private var typeDeletePhase: some View {
        VStack(spacing: 24) {
            WizardCard(title: "Final Confirmation",
                       subtitle: "Type DELETE in all caps to confirm") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Type **DELETE** to permanently remove the selected files.")
                        .font(.system(size: 13))

                    TextField("Type DELETE here…", text: $typedConfirm)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()

                    if !typedConfirm.isEmpty && typedConfirm != "DELETE" {
                        Text("Must be exactly: DELETE")
                            .font(.caption).foregroundColor(.red)
                    }
                }
            }

            HStack {
                Button("← Go back") { confirmationPhase = 1; typedConfirm = "" }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                Spacer()
                Button {
                    Task {
                        isDeleting = true
                        await vm.runClean()
                        deletedCount = vm.cleanFiles.isEmpty ? vm.cleanFilesSelected.count : 0
                        isDeleting = false
                        confirmationPhase = 3
                    }
                } label: {
                    if isDeleting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Delete now", systemImage: "trash.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(typedConfirm != "DELETE" || isDeleting)
            }
        }
    }

    // MARK: - Phase 3: success

    private var successPhase: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "trash.slash.fill")
                        .font(.system(size: 26)).foregroundColor(.green)
                }
                Text("Files deleted")
                    .font(.title2).fontWeight(.semibold)
                Text("Folders are empty and ready for next week.")
                    .font(.subheadline).foregroundColor(.secondary)
            }

            Button {
                confirmationPhase = 0
                typedConfirm = ""
                vm.goTo(.welcome)
            } label: {
                Text("Back to main menu")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24).padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent).tint(.cpPrimary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - File row

    private func fileRow(_ file: CleanFile) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { vm.cleanFilesSelected.contains(file.path) },
                set: { on in
                    if on { vm.cleanFilesSelected.insert(file.path) }
                    else  { vm.cleanFilesSelected.remove(file.path) }
                }))
            .toggleStyle(.checkbox)

            Image(systemName: file.name.hasSuffix(".mp3") ? "music.note" : "film.fill")
                .foregroundColor(file.label == "output" ? .cpPrimary : .cpAccent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(file.path).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1)
            }

            Spacer()

            Text("\(String(format: "%.0f", file.sizeMb)) MB")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var groupedFiles: [(String, [CleanFile])] {
        let groups = Dictionary(grouping: vm.cleanFiles, by: { $0.label })
        return [("output", groups["output"] ?? []), ("inbox", groups["inbox"] ?? [])]
            .filter { !$0.1.isEmpty }
    }

    private var totalMB: Double    { vm.cleanFiles.reduce(0) { $0 + $1.sizeMb } }
    private var selectedMB: Double { vm.cleanTotalMB }
}
