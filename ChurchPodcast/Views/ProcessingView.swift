import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var vm:  PipelineViewModel
    @EnvironmentObject var sse: SSEListener

    private var activeKeys: [String] {
        vm.mode == .auto
            ? ["download", "trim", "export"]
            : ["trim", "export"]
    }

    private var activeSteps: [StepState] {
        sse.steps.filter { activeKeys.contains($0.key) }
    }

    private var allDone: Bool {
        activeKeys.allSatisfy { k in
            sse.steps.first(where: { $0.key == k })?.status == .done
        }
    }

    private var anyFailed: Bool {
        activeSteps.contains(where: { $0.status == .failed })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                WizardCard(title: "Processing",
                           subtitle: "Sit back — this may take a few minutes") {
                    VStack(spacing: 7) {
                        ForEach(activeSteps) { step in
                            StepProgressRow(step: step)
                        }
                    }
                }

                if let err = vm.errorMessage { errorBanner(err) }

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
    }

    // MARK: - Output preview

    private var outputPreview: some View {
        WizardCard(title: "Output Files") {
            VStack(spacing: 7) {
                if !vm.trimmedFilePath.isEmpty {
                    fileRow(icon: "film.fill", color: .cpPrimary,
                            label: "Trimmed video", path: vm.trimmedFilePath)
                }
                if !vm.audioFilePath.isEmpty {
                    fileRow(icon: "music.note", color: .cpAccent,
                            label: "Podcast audio (MP3)", path: vm.audioFilePath)
                }
            }
        }
    }

    private func fileRow(icon: String, color: Color,
                          label: String, path: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundColor(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12, weight: .medium))
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "arrow.right.circle").foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(9).background(color.opacity(0.05)).cornerRadius(8)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Something went wrong")
                    .font(.system(size: 13, weight: .semibold))
                Text(message).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Dismiss") { vm.errorMessage = nil }
                .font(.caption).buttonStyle(.plain).foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.red.opacity(0.07)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.18)))
    }
}
