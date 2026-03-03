import SwiftUI

struct MetadataView: View {
    @EnvironmentObject var vm: PipelineViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                WizardCard(title: "Episode Details",
                           subtitle: "Title and description used for YouTube and Spotify") {
                    VStack(alignment: .leading, spacing: 16) {

                        // Defaults toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use config defaults")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Auto-generated title and your default description")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $vm.useDefaultMetadata)
                                .toggleStyle(.switch)
                                .onChange(of: vm.useDefaultMetadata) { use in
                                    if use { vm.resetMetadataToDefaults() }
                                }
                        }
                        .padding(12).background(Color.cpPrimary.opacity(0.05)).cornerRadius(9)

                        Divider()

                        VStack(alignment: .leading, spacing: 5) {
                            SectionHeader(text: "Title")
                            TextField("Sermón — 2025-01-14", text: $vm.episodeTitle)
                                .textFieldStyle(.roundedBorder)
                                .disabled(vm.useDefaultMetadata)
                                .opacity(vm.useDefaultMetadata ? 0.55 : 1)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            SectionHeader(text: "Description")
                            TextEditor(text: $vm.episodeDescription)
                                .font(.system(size: 13))
                                .frame(minHeight: 72)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.22)))
                                .disabled(vm.useDefaultMetadata)
                                .opacity(vm.useDefaultMetadata ? 0.55 : 1)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            SectionHeader(text: "YouTube Privacy")
                            Picker("", selection: $vm.privacy) {
                                Text("Public").tag("public")
                                Text("Unlisted").tag("unlisted")
                                Text("Private").tag("private")
                            }
                            .pickerStyle(.segmented).frame(maxWidth: 260)
                        }
                    }
                }

                WizardNavBar(
                    nextLabel:    "Start Processing",
                    nextDisabled: vm.episodeTitle.isEmpty,
                    accentNext: true,
                    onBack: { vm.goTo(.timestamps) },
                    onNext: {
                        vm.goTo(.processing)
                        Task { await vm.runProcessing() }
                    }
                )
            }
            .padding(32)
        }
    }
}
