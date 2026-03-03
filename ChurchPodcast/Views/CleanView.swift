import SwiftUI

struct CleanView: View {
    @EnvironmentObject var vm: PipelineViewModel

    @State private var phase:        Int    = 0   // 0=list 1=confirm 2=type DELETE 3=done
    @State private var typedConfirm: String = ""
    @State private var isDeleting:   Bool   = false

    var body: some View {
        ScrollView {
            Group {
                switch phase {
                case 0: listPhase
                case 1: confirmPhase
                case 2: typePhase
                default: successPhase
                }
            }
            .padding(32)
        }
        .task { await vm.loadCleanFiles() }
    }

    // MARK: - Phase 0: list

    private var listPhase: some View {
        VStack(spacing: 20) {
            WizardCard(title: "Clean Files",
                       subtitle: "Permanently delete processed files to free up disk space") {
                VStack(alignment: .leading, spacing: 12) {
                    if vm.cleanFiles.isEmpty {
                        Label("Nothing to clean — all folders are empty.",
                              systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13)).foregroundColor(.green)
                            .padding(12).background(Color.green.opacity(0.06))
                            .cornerRadius(9)
                    } else {
                        HStack {
                            Button("All")  { vm.cleanFilesSelected = Set(vm.cleanFiles.map { $0.path }) }
                                .buttonStyle(.plain).font(.caption).foregroundColor(.cpPrimary)
                            Text("·").foregroundColor(.secondary)
                            Button("None") { vm.cleanFilesSelected = [] }
                                .buttonStyle(.plain).font(.caption).foregroundColor(.cpPrimary)
                            Spacer()
                            Text("\(vm.cleanFiles.count) file(s)  ·  \(Int(totalMB)) MB")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Divider()
                        ForEach(vm.cleanFiles) { file in
                            fileRow(file)
                        }
                    }
                }
            }

            WizardNavBar(
                backLabel:    "← Main menu",
                nextLabel:    "Delete selected",
                nextDisabled: vm.cleanFilesSelected.isEmpty,
                onBack: { vm.goTo(.welcome) },
                onNext: { phase = 1 }
            )
        }
    }

    // MARK: - Phase 1: first confirmation

    private var confirmPhase: some View {
        VStack(spacing: 20) {
            WizardCard(title: "Are you sure?",
                       subtitle: "This action cannot be undone") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange).font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(vm.cleanFilesSelected.count) file(s) will be permanently deleted")
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(Int(vm.cleanTotalMB)) MB will be freed")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(12).background(Color.orange.opacity(0.08)).cornerRadius(9)

                    Text("Make sure everything has been uploaded before deleting.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            HStack {
                Button("← Back") { phase = 0 }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                Spacer()
                Button("Yes, continue") { phase = 2 }
                    .buttonStyle(.borderedProminent).tint(.orange)
            }
        }
    }

    // MARK: - Phase 2: type DELETE

    private var typePhase: some View {
        VStack(spacing: 20) {
            WizardCard(title: "Final confirmation",
                       subtitle: "Type DELETE in all caps to proceed") {
                VStack(alignment: .leading, spacing: 12) {
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
                Button("← Back") { phase = 1; typedConfirm = "" }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                Spacer()
                Button {
                    Task {
                        isDeleting = true
                        await vm.runClean()
                        isDeleting = false
                        phase = 3
                    }
                } label: {
                    if isDeleting { ProgressView().controlSize(.small) }
                    else { Label("Delete now", systemImage: "trash.fill") }
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(typedConfirm != "DELETE" || isDeleting)
            }
        }
    }

    // MARK: - Phase 3: success

    private var successPhase: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.12)).frame(width: 60, height: 60)
                    Image(systemName: "trash.slash.fill")
                        .font(.system(size: 24)).foregroundColor(.green)
                }
                Text("Files deleted").font(.title2).fontWeight(.semibold)
                Text("Folders are empty and ready for next week.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding(.top, 12)

            Button {
                phase = 0; typedConfirm = ""
                vm.goTo(.welcome)
            } label: {
                Text("Back to main menu")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 22).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).tint(.cpPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - File row

    private func fileRow(_ file: CleanFile) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get:  { vm.cleanFilesSelected.contains(file.path) },
                set:  { on in
                    if on { vm.cleanFilesSelected.insert(file.path) }
                    else  { vm.cleanFilesSelected.remove(file.path) }
                })).toggleStyle(.checkbox)
            Image(systemName: file.name.hasSuffix(".mp3") ? "music.note" : "film.fill")
                .foregroundColor(file.label == "output" ? .cpPrimary : .cpAccent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(file.path).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Text("\(Int(file.sizeMb)) MB").font(.caption).foregroundColor(.secondary)
        }
    }

    private var totalMB: Double { vm.cleanFiles.reduce(0) { $0 + $1.sizeMb } }
}
