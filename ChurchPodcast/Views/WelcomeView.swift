import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var vm:     PipelineViewModel
    @EnvironmentObject var server: ServerManager

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App identity
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.cpPrimary, Color(red: 0.40, green: 0.60, blue: 1.0)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 68, height: 68)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28)).foregroundColor(.white)
                    }
                    Text("Church Podcast")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("Weekly sermon automation")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.top, 12)

                // Server status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(server.isRunning ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(server.isRunning ? "Backend ready" :
                         server.startupError != nil ? "Backend error" : "Starting backend…")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.cpSurface)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.secondary.opacity(0.2)))

                // Startup error
                if let err = server.startupError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Backend failed to start")
                                .font(.system(size: 13, weight: .semibold))
                            Text(err).font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Retry") { server.start() }
                                .font(.caption).buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(10)
                }

                // Mode selection
                WizardCard(title: "How would you like to start?") {
                    VStack(spacing: 10) {
                        modeCard(.auto,
                                 icon: "arrow.down.circle.fill", color: .cpPrimary,
                                 title: "Auto Pipeline",
                                 desc:  "Download from YouTube, trim, and re-upload — fully automated.")
                        modeCard(.manual,
                                 icon: "folder.fill", color: .cpAccent,
                                 title: "Manual File",
                                 desc:  "Use a .mp4 you already downloaded. Trim, export, upload at your pace.")
                    }
                }

                // Action row
                HStack {
                    Button {
                        vm.goTo(.clean)
                        Task { await vm.loadCleanFiles() }
                    } label: {
                        Label("Clean files", systemImage: "trash")
                            .font(.system(size: 13)).foregroundColor(.secondary)
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
                            .padding(.horizontal, 22).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cpPrimary)
                    .disabled(!server.isRunning)
                }
            }
            .padding(32)
        }
    }

    private func modeCard(_ mode: PipelineMode, icon: String, color: Color,
                           title: String, desc: String) -> some View {
        let selected = vm.mode == mode
        return Button { withAnimation { vm.mode = mode } } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.opacity(selected ? 0.18 : 0.10))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: icon).font(.system(size: 18)).foregroundColor(color))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(desc).font(.system(size: 12)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? color : Color.secondary.opacity(0.3))
                    .font(.system(size: 17))
            }
            .padding(12)
            .background(selected ? color.opacity(0.06) : Color.cpBackground)
            .cornerRadius(11)
            .overlay(RoundedRectangle(cornerRadius: 11)
                .stroke(selected ? color.opacity(0.35) : Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
