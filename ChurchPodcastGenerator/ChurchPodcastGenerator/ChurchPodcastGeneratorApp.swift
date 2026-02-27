//
//  ChurchPodcastGeneratorApp.swift
//  ChurchPodcastGenerator
//
//  Created by Luis Alejandro Ramirez Suarez on 27/02/26.
//

import SwiftUI

@main
struct ChurchPodcastGeneratorApp: App {
    @State private var server = ServerManager.shared
    @StateObject private var vm     = PipelineViewModel()
    @StateObject private var sse    = SSEListener.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .environment(server)
                .environmentObject(sse)
                .onAppear { server.start() }  // not available pre-Ventura; see note below
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}  // remove File > New
            CommandMenu("Podcast") {
                Button("New Run") {
                    vm.resetForNewRun()
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Divider()
                
                Button("Clean Files…") {
                    vm.goTo(.clean)
                    Task { await vm.loadCleanFiles() }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
        .defaultSize(width: 680, height: 620)
    }
}
