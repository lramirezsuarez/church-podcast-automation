import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var vm: PipelineViewModel
    @Environment(ServerManager.self) var server

    var body: some View {
        VStack(spacing: 28) {

            // App identity
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.cpPrimary, Color(red: 0.40, green: 0.60, blue: 1.0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
                Text("Church Podcast")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Weekly sermon automation")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding(.top, 8)

            // Server status
            serverStatusBadge

            // Mode selection
            WizardCard(title: "How would you like to start?",
                       subtitle: "You can change this at any time") {
                VStack(spacing: 12) {
                    modeCard(
                        icon:        "arrow.down.circle.fill",
                        iconColor:   .cpPrimary,
                        title:       "Auto Pipeline",
                        description: "Download the broadcast from YouTube, trim it, and upload everything automatically.",
                        mode:        .auto
                    )
                    modeCard(
                        icon:        "folder.fill",
                        iconColor:   .cpAccent,
                        title:       "Manual File",
                        description: "Use a .mp4 you already downloaded. Trim, export, and upload at your own pace.",
                        mode:        .manual
                    )
                }
            }

            // Bottom row
            HStack {
                Button {
                    vm.goTo(.clean)
                    Task { await vm.loadCleanFiles() }
                } label: {
                    Label("Clean files", systemImage: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    vm.goTo(.source)
                    Task {
                        await vm.loadConfig()
                        if vm.mode == .manual { await vm.loadInboxFiles() }
                    }
                } label: {
                    Text("Get started")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cpPrimary)
                .disabled(!server.isRunning)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var serverStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(server.isRunning ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(server.isRunning ? "Backend ready" : "Starting backend…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.cpSurface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.secondary.opacity(0.2)))
    }

    private func modeCard(icon: String, iconColor: Color, title: String, description: String, mode: PipelineMode) -> some View {
        let selected = vm.mode == mode
        return Button {
            withAnimation { vm.mode = mode }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor.opacity(selected ? 0.18 : 0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? iconColor : Color.secondary.opacity(0.3))
                    .font(.system(size: 18))
            }
            .padding(14)
            .background(selected ? iconColor.opacity(0.06) : Color.cpBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? iconColor.opacity(0.4) : Color.secondary.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
}
