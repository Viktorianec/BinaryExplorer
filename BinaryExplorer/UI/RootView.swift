//
//  RootView.swift
//  BinaryExplorer
//
//  Window shell: sidebar, section router, drop target, progress and search.
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            AuroraBackground()

            if state.analysis == nil {
                WelcomeView()
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 218, ideal: 244, max: 300)
                } detail: {
                    detail
                        .background(Color.clear)
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar { toolbarContent }
            }

            if state.isLoading { LoadingOverlay() }
            if state.isDropTargeted { DropHighlight() }
        }
        .onDrop(of: [.fileURL], isTargeted: $state.isDropTargeted) { providers in
            state.handleDrop(providers: providers)
        }
        .alert("Could not inspect archive",
               isPresented: Binding(get: { state.errorMessage != nil },
                                    set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .sheet(isPresented: $state.isSearchPresented) { SearchPalette() }
    }

    @ViewBuilder
    private var detail: some View {
        if let analysis = state.analysis {
            switch state.section {
            case .overview: OverviewSection(analysis: analysis)
            case .spatial: SpatialSection(analysis: analysis)
            case .structure: StructureSection(analysis: analysis)
            case .resources: ResourcesSection(analysis: analysis)
            case .binary: MachOSection_View(analysis: analysis)
            case .dependencies: DependenciesSection(analysis: analysis)
            case .signing: SigningSection(analysis: analysis)
            case .privacy: PrivacySection(analysis: analysis)
            case .insights: InsightsSection(analysis: analysis)
            case .metadata: MetadataSection(analysis: analysis)
            case .anatomy: AnatomySection(analysis: analysis)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if let analysis = state.analysis {
                HStack(spacing: 9) {
                    if let icon = analysis.app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    }
                    Text(analysis.app.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(analysis.app.shortVersion)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
                .padding(.trailing, 8)
                // Toolbar items are sized from the proposal, not the content,
                // so the version was being clipped. Pin the intrinsic width.
                .fixedSize()
                .help("\(analysis.app.displayName) \(analysis.app.shortVersion) (\(analysis.app.buildNumber))")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { state.isSearchPresented = true } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Find files, libraries, sections and keys (⌘F)")

            Button { state.openPanel() } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open another IPA (⌘O)")

            Button { state.close() } label: {
                Label("Close", systemImage: "xmark.circle")
            }
            .help("Close the current archive")
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List(selection: Binding(get: { state.section }, set: { state.section = $0 ?? .overview })) {
            if let analysis = state.analysis {
                Section {
                    AppHeaderCard(analysis: analysis)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 10, trailing: 4))
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(ExplorerSection.groups, id: \.name) { group in
                Section(group.name.uppercased()) {
                    ForEach(group.items) { item in
                        Label {
                            Text(item.title).font(.system(size: 12.5))
                        } icon: {
                            Image(systemName: item.symbol)
                                .foregroundStyle(item.tint)
                        }
                        .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.18))
        .safeAreaInset(edge: .bottom) {
            if let analysis = state.analysis {
                SidebarFooter(analysis: analysis)
            }
        }
    }
}

private struct AppHeaderCard: View {
    let analysis: IPAAnalysis

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.accentGradient(Theme.accentViolet).opacity(0.35))
                    .frame(width: 74, height: 74)
                    .blur(radius: 16)
                if let icon = analysis.app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14.5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14.5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 14.5, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 64, height: 64)
                        .overlay(Image(systemName: "app.dashed")
                            .font(.system(size: 22)).foregroundStyle(Theme.tertiaryText))
                }
            }
            VStack(spacing: 3) {
                Text(analysis.app.displayName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(analysis.app.bundleIdentifier)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                Chip(text: "v\(analysis.app.shortVersion)", tint: Theme.accent)
                Chip(text: "(\(analysis.app.buildNumber))", tint: Theme.accent.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SidebarFooter: View {
    let analysis: IPAAnalysis

    private var criticalCount: Int {
        analysis.insights.filter { $0.level == .critical || $0.level == .warning }.count
    }

    var body: some View {
        VStack(spacing: 6) {
            Divider().opacity(0.3)
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                Text(Format.bytes(analysis.archiveSize))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text("archive")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                if criticalCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("\(criticalCount)").font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.35))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Overlays

private struct LoadingOverlay: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 5)
                        .frame(width: 78, height: 78)
                    Circle()
                        .trim(from: 0, to: max(0.04, state.progress?.fraction ?? 0))
                        .stroke(Theme.accentGradient(Theme.accent),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 78, height: 78)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.25), value: state.progress?.fraction)
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.accent)
                }
                VStack(spacing: 5) {
                    Text(state.progress?.stage.rawValue ?? "Working")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("\(Int((state.progress?.fraction ?? 0) * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1))
        }
        .transition(.opacity)
    }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [10, 7]))
            .padding(14)
            .background(Theme.accent.opacity(0.07))
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}
