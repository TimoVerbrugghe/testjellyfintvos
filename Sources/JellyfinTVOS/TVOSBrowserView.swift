#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

@MainActor
public final class JellyfinAppModel: ObservableObject {
    @Published public var appState: JellyfinAppState {
        didSet {
            appStateStore?.saveState(appState)
        }
    }
    @Published public var playbackErrorMessage: String?
    @Published public private(set) var isWorking = false
    @Published public private(set) var isPollingQuickConnect = false
    @Published public private(set) var quickConnectCode: QuickConnectCode?

    private let catalogClient: JellyfinCatalogClient
    private let playbackBuilder: PlaybackRequestBuilder
    private let liveService: JellyfinLiveService
    private let appStateStore: JellyfinAppStateStore?
    private let deviceID: String
    private let appVersion: String
    private var quickConnectTask: Task<Void, Never>?

    public init(
        catalogClient: JellyfinCatalogClient,
        playbackBuilder: PlaybackRequestBuilder,
        appState: JellyfinAppState = JellyfinAppState(),
        liveService: JellyfinLiveService = JellyfinLiveService(),
        appStateStore: JellyfinAppStateStore? = nil,
        deviceID: String? = nil,
        appVersion: String = JellyfinTVOS.appVersion
    ) {
        self.catalogClient = catalogClient
        self.playbackBuilder = playbackBuilder
        self.appState = appState
        self.liveService = liveService
        self.appStateStore = appStateStore
        self.deviceID = deviceID ?? playbackBuilder.client.session.deviceID
        self.appVersion = appVersion
        self.appStateStore?.startSync { [weak self] syncedState in
            guard let self, self.appState != syncedState else {
                return
            }
            self.appState = syncedState
        }
        self.appStateStore?.saveState(self.appState)
    }

    deinit {
        quickConnectTask?.cancel()
    }

    public func beginDiscovery() async {
        appState.beginDiscovery()
        isWorking = true
        defer { isWorking = false }

        let discoveredServers = await liveService.discoverServers()
        appState.applyDiscoveredServers(discoveredServers)

        if discoveredServers.isEmpty {
            playbackErrorMessage = "No Jellyfin servers were discovered automatically. Enter your server URL manually or try discovery again."
        }
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

    public func commitManualServer() async {
        isWorking = true
        defer { isWorking = false }

        do {
            let candidate = try appState.resolvedManualServer()
            let validatedServer = try await liveService.validateServer(
                url: candidate.address,
                deviceID: deviceID,
                appVersion: appVersion
            )
            appState.commitManualServer(validatedServer)
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

    public func signIn(username: String, password: String) async {
        isWorking = true
        defer { isWorking = false }

        do {
            let server = try selectedServer()
            let session = try await liveService.authenticate(
                server: server,
                credentials: UserCredentials(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                ),
                deviceID: deviceID,
                appVersion: appVersion
            )
            try await finishSignIn(server: server, session: session)
            playbackErrorMessage = nil
        } catch {
            playbackErrorMessage = error.localizedDescription
        }
    }

    public func startQuickConnect() async {
        quickConnectTask?.cancel()
        isWorking = true
        defer { isWorking = false }

        do {
            let server = try selectedServer()
            let code = try await liveService.beginQuickConnect(
                server: server,
                deviceID: deviceID,
                appVersion: appVersion
            )
            quickConnectCode = code
            isPollingQuickConnect = true
            playbackErrorMessage = nil

            quickConnectTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let session = try await self.liveService.completeQuickConnect(
                        server: server,
                        quickConnectCode: code,
                        deviceID: self.deviceID,
                        appVersion: self.appVersion
                    )
                    try await self.finishSignIn(server: server, session: session)
                    await MainActor.run {
                        self.isPollingQuickConnect = false
                        self.quickConnectCode = nil
                        self.playbackErrorMessage = nil
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.isPollingQuickConnect = false
                    }
                } catch {
                    await MainActor.run {
                        self.isPollingQuickConnect = false
                        self.playbackErrorMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            isPollingQuickConnect = false
            playbackErrorMessage = error.localizedDescription
        }
    }

    public func signOut() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        quickConnectCode = nil
        isPollingQuickConnect = false
        appState.signOut()
    }

    private func selectedServer() throws -> DiscoveredServer {
        if let selectedServer = appState.selectedServer {
            return selectedServer
        }

        return try appState.resolvedManualServer()
    }

    private func finishSignIn(server: DiscoveredServer, session: JellyfinSession) async throws {
        let signedInContent = try await liveService.loadSignedInContent(
            server: server,
            session: session
        )
        appState.selectServer(server)
        appState.completeSignIn(
            session: session,
            libraries: signedInContent.libraries,
            homeContent: signedInContent.homeContent,
            posterCatalog: signedInContent.posterCatalog
        )
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
        .alert("Status", isPresented: statusAlertPresented, actions: {
            Button("OK") {
                model.playbackErrorMessage = nil
            }
        }, message: {
            Text(model.playbackErrorMessage ?? "")
        })
        .overlay {
            if model.isWorking {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    ProgressView("Connecting…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private var statusAlertPresented: Binding<Bool> {
        Binding(
            get: { model.playbackErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.playbackErrorMessage = nil
                }
            }
        )
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
                    Task {
                        await model.beginDiscovery()
                    }
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

            Button("Search Again") {
                Task {
                    await model.beginDiscovery()
                }
            }
            .buttonStyle(.borderedProminent)

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
                        ServerSelectionRow(server: server)
                    }
                    .buttonStyle(.plain)
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

private struct ServerSelectionRow: View {
    let server: DiscoveredServer
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(server.name)
                .foregroundStyle(isFocused ? Color.black : Color.primary)
            Text(server.address.absoluteString)
                .font(.footnote)
                .foregroundStyle(isFocused ? Color.black.opacity(0.75) : Color.secondary)
        }
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
                    Task {
                        await model.commitManualServer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.appState.hasManualServerAddress || model.isWorking)
            }
        }
        .navigationTitle("Manual Setup")
    }
}

private struct SignInScreen: View {
    @ObservedObject var model: JellyfinAppModel
    @State private var username = ""
    @State private var password = ""
    private let availableMethods: [JellyfinSignInMethod] = [.usernamePassword, .quickConnect]

    var body: some View {
        Form {
            Section("Server") {
                Text(model.appState.selectedServer?.name ?? "Jellyfin Server")
                Text(model.appState.selectedServer?.address.absoluteString ?? "")
                    .foregroundStyle(.secondary)
            }

            Section("Sign In") {
                HStack(spacing: 18) {
                    ForEach(availableMethods) { method in
                        signInMethodButton(method)
                    }
                }

                switch model.appState.signInMethod {
                case .autodiscovery, .usernamePassword:
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                case .quickConnect:
                    VStack(alignment: .leading, spacing: 10) {
                        if let quickConnectCode = model.quickConnectCode {
                            Text(quickConnectCode.code)
                                .font(.system(.title2, design: .monospaced).bold())
                            Text("Open Jellyfin in another client, choose Quick Connect, and enter this code.")
                                .foregroundStyle(.secondary)
                            if model.isPollingQuickConnect {
                                ProgressView("Waiting for approval…")
                            }
                        } else {
                            Text("Generate a Quick Connect code, then approve this Apple TV from another Jellyfin client.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button(connectButtonTitle) {
                    Task {
                        switch model.appState.signInMethod {
                        case .autodiscovery, .usernamePassword:
                            await model.signIn(username: username, password: password)
                        case .quickConnect:
                            await model.startQuickConnect()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(connectButtonDisabled)
            } footer: {
                Text("Sign in with your live Jellyfin server credentials, or use Quick Connect to approve this Apple TV from another client.")
            }
        }
        .navigationTitle("Sign In")
    }

    private var connectButtonTitle: String {
        switch model.appState.signInMethod {
        case .autodiscovery, .usernamePassword:
            "Sign In"
        case .quickConnect:
            model.quickConnectCode == nil ? "Generate Quick Connect Code" : "Generate New Quick Connect Code"
        }
    }

    private var connectButtonDisabled: Bool {
        guard !model.isWorking else {
            return true
        }

        switch model.appState.signInMethod {
        case .autodiscovery, .usernamePassword:
            return username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
        case .quickConnect:
            return false
        }
    }

    @ViewBuilder
    private func signInMethodButton(_ method: JellyfinSignInMethod) -> some View {
        let button = Button(method.title) {
            model.updateSignInMethod(method)
        }

        if model.appState.signInMethod == method {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
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
            .navigationDestination(for: JellyfinPosterItem.self) { item in
                PosterDetailsPlaceholderView(item: item)
            }
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
                            PosterTileLink(item: item)
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
            .navigationDestination(for: JellyfinPosterItem.self) { item in
                PosterDetailsPlaceholderView(item: item)
            }
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
                                            PosterTileLink(item: item)
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
                            .buttonStyle(.plain)
                            .font(.caption.bold())
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}

private struct PosterTileLink: View {
    let item: JellyfinPosterItem

    var body: some View {
        NavigationLink(value: item) {
            PosterCardView(item: item)
        }
        .buttonStyle(.plain)
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
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PosterArtworkView(item: item)
                .frame(width: 220, height: 320)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(isFocused ? 0.85 : 0), lineWidth: 3)
                }

            Text(item.title)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 52, alignment: .topLeading)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Color.clear
                    .frame(height: 20)
            }
        }
        .frame(width: 220, alignment: .leading)
        .padding(.vertical, 8)
        .scaleEffect(isFocused ? 1.04 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: isFocused ? 16 : 0, y: 10)
        .zIndex(isFocused ? 1 : 0)
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

private struct PosterArtworkView: View {
    let item: JellyfinPosterItem

    var body: some View {
        Group {
            if let artworkURL = item.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "film")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
            }
    }
}

private struct PosterDetailsPlaceholderView: View {
    let item: JellyfinPosterItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.title)
                .font(.largeTitle.bold())
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("Detail playback screen is next.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(60)
        .navigationTitle("Details")
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
