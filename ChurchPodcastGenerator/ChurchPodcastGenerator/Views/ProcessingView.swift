import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var vm: PipelineViewModel
    @EnvironmentObject var sse: SSEListener

    private var allDone: Bool {
        let keys: [String] = vm.mode == .auto
            ? ["download", "trim", "export"]
            : ["trim", "export"]
        return keys.allSatisfy { key in
            sse.steps.first(where: { $0.key == key })?.status == .done
        }
    }

    private var anyFailed: Bool {
        sse.steps.contains(where: { $0.status == .failed })
    }

    private var activeSteps: [StepState] {
        let keys: [String] = vm.mode == .auto
            ? ["download", "trim", "export"]
            : ["trim", "export"]
        return sse.steps.filter { keys.contains($0.key) }
    }

    var body: some View {
        VStack(spacing: 24) {
            WizardCard(
                title:    "Processing",
                subtitle: "Sit back — this may take a few minutes"
            ) {
                VStack(spacing: 8) {
                    ForEach(activeSteps) { step in
                        StepProgressRow(step: step)
                    }
                }
            }

            // Error banner
            if let err = vm.errorMessage {
                errorBanner(message: err)
            }

            // Output files preview (shown as steps complete)
            if !vm.trimmedFilePath.isEmpty || !vm.audioFilePath.isEmpty {
                outputPreview
            }

            WizardNavBar(
                nextLabel:    "Continue to Upload",
                nextDisabled: !allDone,
                showBack:     anyFailed,
                onBack: { vm.goTo(.source) },
                onNext: {
                    vm.goTo(.upload)
                    Task { await vm.loadChannels() }
                }
            )
        }
        .padding(32)
    }

    // MARK: - Output preview

    private var outputPreview: some View {
        WizardCard(title: "Output Files") {
            VStack(spacing: 8) {
                if !vm.trimmedFilePath.isEmpty {
                    outputRow(
                        icon: "film.fill", color: .cpPrimary,
                        label: "Trimmed video",
                        path:  vm.trimmedFilePath
                    )
                }
                if !vm.audioFilePath.isEmpty {
                    outputRow(
                        icon: "music.note", color: .cpAccent,
                        label: "Podcast audio (MP3)",
                        path:  vm.audioFilePath
                    )
                }
            }
        }
    }

    private func outputRow(icon: String, color: Color, label: String, path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12, weight: .medium))
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(color.opacity(0.05))
        .cornerRadius(8)
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Something went wrong").font(.system(size: 13, weight: .semibold))
                Text(message).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Dismiss") { vm.errorMessage = nil }
                .font(.caption).buttonStyle(.plain).foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color.red.opacity(0.07))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.2)))
    }
}
