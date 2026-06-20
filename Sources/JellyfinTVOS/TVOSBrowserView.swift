#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

@MainActor
public final class JellyfinAppModel: ObservableObject {
    @Published public var appState: JellyfinAppState
    @Published public var playbackErrorMessage: String?

    private let catalogClient: JellyfinCatalogClient
    private let playbackBuilder: PlaybackRequestBuilder

    public init(
        catalogClient: JellyfinCatalogClient,
        playbackBuilder: PlaybackRequestBuilder,
        appState: JellyfinAppState = JellyfinAppState()
    ) {
        self.catalogClient = catalogClient
        self.playbackBuilder = playbackBuilder
        self.appState = appState
    }

    public func beginDiscovery() {
        appState.beginDiscovery()
    }

    public func applyDiscoveredServers(_ servers: [DiscoveredServer], preferredHost: String? = nil) {
        appState.applyDiscoveredServers(servers, preferredHost: preferredHost)
    }

    public func showManualServerEntry() {
        appState.showManualServerEntry()
    }

    public func updateManualServerAddress(_ value: String) {
        appState.updateManualServerAddress(value)
    }

    public func commitManualServer() {
        do {
            try appState.commitManualServer()
            playbackErrorMessage = nil
        } catch {
            playbackErrorMessage = error.localizedDescription
        }
    }

    public func selectServer(_ server: DiscoveredServer) {
        appState.selectServer(server)
    }

    public func updateSignInMethod(_ method: JellyfinSignInMethod) {
        appState.updateSignInMethod(method)
    }

    public func applyLibraries(_ libraries: [JellyfinLibrary]) {
        appState.updateLibraries(libraries)
    }

    public func applyHomeContent(_ homeContent: JellyfinHomeSectionContent) {
        appState.updateHomeContent(homeContent)
    }

    public func applyPosterItems(_ items: [JellyfinPosterItem], for libraryID: String) {
        appState.setPosterItems(items, for: libraryID)
    }

    public func updateSelectedNavigationItem(_ item: JellyfinNavigationItem) {
        appState.updateSelectedNavigationItem(item)
    }

    public func completePreviewSignIn() {
        let server = appState.selectedServer?.address.absoluteString ?? "https://demo.jellyfin.org"
        let session = JellyfinSession(accessToken: "preview-token", userID: "preview-user", deviceID: "preview-device")
        let libraries = [
            JellyfinLibrary(id: "movies", name: "Movies", collectionType: .movies),
            JellyfinLibrary(id: "shows", name: "TV Shows", collectionType: .tvshows),
            JellyfinLibrary(id: "music", name: "Music", collectionType: .music)
        ]
        var catalog = JellyfinPosterCatalog()
        catalog.setItems(previewItems(prefix: "Movies", count: 12), for: "movies")
        catalog.setItems(previewItems(prefix: "Series", count: 12), for: "shows")
        catalog.setItems(previewItems(prefix: "Albums", count: 12), for: "music")
        appState.completeSignIn(
            session: session,
            libraries: libraries,
            homeContent: JellyfinHomeSectionContent(
                upNext: previewItems(prefix: "Up Next", count: 10),
                recentlyAddedTVShows: previewItems(prefix: "Recently Added Show", count: 10),
                recentlyAddedMovies: previewItems(prefix: "Recently Added Movie", count: 10)
            ),
            posterCatalog: catalog
        )
        playbackErrorMessage = "Preview mode connected to \(server). Replace preview sign-in with live requests when wiring networking."
    }

    public func signOut() {
        appState.signOut()
    }

    private func previewItems(prefix: String, count: Int) -> [JellyfinPosterItem] {
        (1...count).map { index in
            JellyfinPosterItem(
                id: "\(prefix)-\(index)",
                title: "\(prefix) \(index)",
                subtitle: index.isMultiple(of: 2) ? "Jellyfin" : nil
            )
        }
    }
}

public struct JellyfinBrowserView: View {
    @ObservedObject private var model: JellyfinAppModel

    public init(model: JellyfinAppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.appState.launchState == .signedIn {
                SignedInShellView(model: model)
            } else {
                OnboardingFlowView(model: model)
            }
        }
        .alert("Status", isPresented: .constant(model.playbackErrorMessage != nil), actions: {
            Button("OK") {
                model.playbackErrorMessage = nil
            }
        }, message: {
            Text(model.playbackErrorMessage ?? "")
        })
    }
}

private struct OnboardingFlowView: View {
    @ObservedObject var model: JellyfinAppModel

    var body: some View {
        NavigationStack {
            switch model.appState.onboardingStep {
            case .welcome:
                WelcomeScreen(model: model)
            case .discoveringServers:
                DiscoveringServersScreen(model: model)
            case .selectServer:
                ServerSelectionScreen(model: model)
            case .manualServerEntry:
                ManualServerEntryScreen(model: model)
            case .signIn:
                SignInScreen(model: model)
            }
        }
    }
}

private struct WelcomeScreen: View {
    @ObservedObject var model: JellyfinAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Welcome to Jellyfin")
                .font(.largeTitle.bold())
            Text("Find a Jellyfin server on your network or enter a server URL to get started.")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                Button("Search for Servers") {
                    model.beginDiscovery()
                }
                .buttonStyle(.borderedProminent)

                Button("Enter Server URL") {
                    model.showManualServerEntry()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(60)
        .navigationTitle("Welcome")
    }
}

private struct DiscoveringServersScreen: View {
    @ObservedObject var model: JellyfinAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ProgressView()
                .controlSize(.large)
            Text("Searching for Jellyfin servers on your network.")
                .font(.title2)

            if !model.appState.discoveredServers.isEmpty {
                Button("Review Discovered Servers") {
                    model.applyDiscoveredServers(model.appState.discoveredServers)
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Enter Server URL Manually") {
                model.showManualServerEntry()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(60)
        .navigationTitle("Searching")
    }
}

private struct ServerSelectionScreen: View {
    @ObservedObject var model: JellyfinAppModel

    var body: some View {
        List {
            Section("Discovered Servers") {
                ForEach(model.appState.discoveredServers, id: \.id) { server in
                    Button {
                        model.selectServer(server)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(server.name)
                            Text(server.address.absoluteString)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Use a Different Server URL") {
                    model.showManualServerEntry()
                }
            }
        }
        .navigationTitle("Choose Server")
    }
}

private struct ManualServerEntryScreen: View {
    @ObservedObject var model: JellyfinAppModel

    var body: some View {
        Form {
            Section("Server URL") {
                TextField(
                    "https://demo.jellyfin.org",
                    text: Binding(
                        get: { model.appState.manualServerAddress },
                        set: model.updateManualServerAddress
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Section {
                Button("Continue") {
                    model.commitManualServer()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Manual Setup")
    }
}

private struct SignInScreen: View {
    @ObservedObject var model: JellyfinAppModel
    @State private var username = ""
    @State private var password = ""
    @State private var quickConnectCode = ""

    var body: some View {
        Form {
            Section("Server") {
                Text(model.appState.selectedServer?.name ?? "Jellyfin Server")
                Text(model.appState.selectedServer?.address.absoluteString ?? "")
                    .foregroundStyle(.secondary)
            }

            Section("Sign In") {
                Picker(
                    "Method",
                    selection: Binding(
                        get: { model.appState.signInMethod },
                        set: model.updateSignInMethod
                    )
                ) {
                    ForEach(JellyfinSignInMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }

                switch model.appState.signInMethod {
                case .autodiscovery, .usernamePassword:
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                case .quickConnect:
                    TextField("Quick Connect Code", text: $quickConnectCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }

            Section {
                Button(connectButtonTitle) {
                    model.completePreviewSignIn()
                }
                .buttonStyle(.borderedProminent)
            } footer: {
                Text("This Swift package currently exposes request builders and view scaffolding, so the sign-in button completes a preview session until live networking is wired in.")
            }
        }
        .navigationTitle("Sign In")
    }

    private var connectButtonTitle: String {
        switch model.appState.signInMethod {
        case .autodiscovery, .usernamePassword:
            "Sign In"
        case .quickConnect:
            "Connect with Quick Connect"
        }
    }
}

private struct SignedInShellView: View {
    @ObservedObject var model: JellyfinAppModel

    var body: some View {
        TabView(
            selection: Binding(
                get: { model.appState.selectedNavigationItem },
                set: model.updateSelectedNavigationItem
            )
        ) {
            HomeScreen(homeContent: model.appState.homeContent)
                .tabItem { Text(JellyfinNavigationItem.home.title) }
                .tag(JellyfinNavigationItem.home)

            if model.appState.visibleNavigationItems.contains(.movies) {
                LibraryHubScreen(
                    title: JellyfinNavigationItem.movies.title,
                    libraries: model.appState.libraries(for: .movies),
                    posterCatalog: model.appState.posterCatalog
                )
                .tabItem { Text(JellyfinNavigationItem.movies.title) }
                .tag(JellyfinNavigationItem.movies)
            }

            if model.appState.visibleNavigationItems.contains(.tvShows) {
                LibraryHubScreen(
                    title: JellyfinNavigationItem.tvShows.title,
                    libraries: model.appState.libraries(for: .tvshows),
                    posterCatalog: model.appState.posterCatalog
                )
                .tabItem { Text(JellyfinNavigationItem.tvShows.title) }
                .tag(JellyfinNavigationItem.tvShows)
            }

            if model.appState.visibleNavigationItems.contains(.music) {
                LibraryHubScreen(
                    title: JellyfinNavigationItem.music.title,
                    libraries: model.appState.libraries(for: .music),
                    posterCatalog: model.appState.posterCatalog
                )
                .tabItem { Text(JellyfinNavigationItem.music.title) }
                .tag(JellyfinNavigationItem.music)
            }

            SettingsScreen(model: model)
                .tabItem { Text(JellyfinNavigationItem.settings.title) }
                .tag(JellyfinNavigationItem.settings)
        }
    }
}

private struct HomeScreen: View {
    let homeContent: JellyfinHomeSectionContent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    HomeRailSection(title: "Up Next", items: homeContent.upNext)
                    HomeRailSection(title: "Recently Added TV Shows", items: homeContent.recentlyAddedTVShows)
                    HomeRailSection(title: "Recently Added Movies", items: homeContent.recentlyAddedMovies)
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
            .navigationTitle("Home")
        }
    }
}

private struct HomeRailSection: View {
    let title: String
    let items: [JellyfinPosterItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.bold())

            if items.isEmpty {
                EmptyLibraryStateView(title: "No items yet", subtitle: "Content for this rail will appear here once it is loaded.")
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 28) {
                        ForEach(items) { item in
                            PosterCardView(item: item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct LibraryHubScreen: View {
    let title: String
    let libraries: [JellyfinLibrary]
    let posterCatalog: JellyfinPosterCatalog

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    ForEach(libraries, id: \.id) { library in
                        LibrarySectionView(
                            library: library,
                            items: posterCatalog.items(for: library.id)
                        )
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
            .navigationTitle(title)
        }
    }
}

private struct LibrarySectionView: View {
    let library: JellyfinLibrary
    let items: [JellyfinPosterItem]

    private let browser = JellyfinPosterBrowser()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(library.name)
                .font(.title2.bold())
            IndexedPosterBrowserView(sections: browser.sections(for: items))
        }
    }
}

private struct IndexedPosterBrowserView: View {
    let sections: [JellyfinPosterSection]

    var body: some View {
        if sections.isEmpty {
            EmptyLibraryStateView(
                title: "No posters loaded",
                subtitle: "This library view is ready for alphabetical poster browsing once content is supplied."
            )
        } else {
            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: 24) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            ForEach(sections, id: \.title) { section in
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(section.title)
                                        .font(.title3.bold())
                                        .id(section.title)

                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 220), spacing: 22)],
                                        alignment: .leading,
                                        spacing: 22
                                    ) {
                                        ForEach(section.items) { item in
                                            PosterCardView(item: item)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(sections, id: \.title) { section in
                            Button(section.title) {
                                withAnimation {
                                    proxy.scrollTo(section.title, anchor: .top)
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption.bold())
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}

private struct SettingsScreen: View {
    @ObservedObject var model: JellyfinAppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    if let server = model.appState.selectedServer {
                        LabeledContent("Server", value: server.name)
                        LabeledContent("Address", value: server.address.absoluteString)
                    } else {
                        Text("No server selected")
                    }
                }

                Section("Libraries") {
                    LabeledContent("Movies", value: model.appState.hasLibrary(of: .movies) ? "Available" : "Hidden")
                    LabeledContent("TV Shows", value: model.appState.hasLibrary(of: .tvshows) ? "Available" : "Hidden")
                    LabeledContent("Music", value: model.appState.hasLibrary(of: .music) ? "Available" : "Hidden")
                }

                Section("Sign In") {
                    LabeledContent("Method", value: model.appState.signInMethod.title)
                }

                Section {
                    Button("Sign Out") {
                        model.signOut()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct PosterCardView: View {
    let item: JellyfinPosterItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 18)
                .fill(.quaternary)
                .frame(width: 220, height: 320)
                .overlay {
                    Image(systemName: "film")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                }

            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 220, alignment: .leading)
    }
}

private struct EmptyLibraryStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
#endif
