//
//  BinaryExplorerApp.swift
//  BinaryExplorer
//
//  Created by Viktorianec on 12.09.2026.
//

import SwiftUI

/// Bridges Finder / `open` document events into the shared state.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var state: AppState?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in AppDelegate.state?.load(url: url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct BinaryExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Binary Explorer", id: "main") {
            RootView()
                .environmentObject(state)
                .onAppear { AppDelegate.state = state }
                .frame(minWidth: 1120, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open IPA…") { state.openPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Find in Bundle…") { state.isSearchPresented = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(state.analysis == nil)
                Divider()
                ForEach(ExplorerSection.allCases) { section in
                    Button(section.title) { state.section = section }
                        .disabled(state.analysis == nil)
                }
            }
            CommandGroup(replacing: .help) {
                Link("Apple: Bundle Structures",
                     destination: URL(string: "https://developer.apple.com/documentation/bundleresources")!)
            }
        }
    }
}
