import SwiftUI

@main
struct ChurchPodcastApp: App {

    @StateObject private var server = ServerManager.shared
    @StateObject private var vm     = PipelineViewModel()
    @StateObject private var sse    = SSEListener.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .environmentObject(server)
                .environmentObject(sse)
                .onAppear { server.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 660, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Podcast") {
                Button("New Run") { vm.resetForNewRun() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button("Clean Files…") {
                    vm.goTo(.clean)
                    Task { await vm.loadCleanFiles() }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
