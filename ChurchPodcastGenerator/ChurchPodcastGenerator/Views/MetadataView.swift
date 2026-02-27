import SwiftUI

struct MetadataView: View {
    @EnvironmentObject var vm: PipelineViewModel

    var body: some View {
        VStack(spacing: 24) {
            WizardCard(
                title: "Episode Metadata",
                subtitle: "Title and description used for YouTube and Spotify"
            ) {
                VStack(alignment: .leading, spacing: 18) {

                    // Quick-use defaults toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use default values from config")
                                .font(.system(size: 13, weight: .medium))
                            Text("Title prefix + today's date, and your default description")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $vm.useDefaultMetadata)
                            .toggleStyle(.switch)
                            .onChange(of: vm.useDefaultMetadata) { _, useDefault in
                                if useDefault { vm.resetMetadataToDefaults() }
                            }
                    }
                    .padding(12)
                    .background(Color.cpPrimary.opacity(0.05))
                    .cornerRadius(10)

                    Divider()

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(text: "Episode Title")
                        TextField("Sermón — 2025-01-14", text: $vm.episodeTitle)
                            .textFieldStyle(.roundedBorder)
                            .disabled(vm.useDefaultMetadata)
                            .opacity(vm.useDefaultMetadata ? 0.6 : 1)
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(text: "Description")
                        TextEditor(text: $vm.episodeDescription)
                            .font(.system(size: 13))
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25)))
                            .disabled(vm.useDefaultMetadata)
                            .opacity(vm.useDefaultMetadata ? 0.6 : 1)
                    }

                    // Privacy
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(text: "YouTube Privacy")
                        Picker("", selection: $vm.privacy) {
                            Text("Public").tag("public")
                            Text("Unlisted").tag("unlisted")
                            Text("Private").tag("private")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }
                }
            }

            WizardNavBar(
                nextLabel:    "Start Processing",
                nextDisabled: vm.episodeTitle.isEmpty,
                onBack: { vm.goTo(.timestamps) },
                onNext: {
                    vm.goTo(.processing)
                    Task { await vm.runProcessing() }
                },
                accentNext: true
            )
        }
        .padding(32)
    }
}

// MARK: - ViewModel extension for metadata reset

extension PipelineViewModel {
    func resetMetadataToDefaults() {
        let prefix  = serverConfig?.podcastTitlePrefix ?? "Sermón —"
        episodeTitle       = "\(prefix) \(today)"
        episodeDescription = serverConfig?.podcastDescription ?? ""
        privacy            = serverConfig?.youtubePrivacy ?? "public"
    }
}
