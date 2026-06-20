import Foundation

public enum JellyfinSignInMethod: String, CaseIterable, Codable, Identifiable, Sendable {
    case autodiscovery
    case usernamePassword
    case quickConnect

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .autodiscovery:
            "Auto-discover"
        case .usernamePassword:
            "Username / Password"
        case .quickConnect:
            "Quick Connect"
        }
    }
}

public enum JellyfinLaunchState: Equatable, Sendable {
    case firstLaunch
    case signedOut
    case signedIn
}

public enum JellyfinOnboardingStep: Equatable, Sendable {
    case welcome
    case discoveringServers
    case selectServer
    case manualServerEntry
    case signIn
}

public enum JellyfinNavigationItem: String, CaseIterable, Identifiable, Sendable {
    case home
    case movies
    case tvShows
    case music
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home:
            "Home"
        case .movies:
            "Movies"
        case .tvShows:
            "TV Shows"
        case .music:
            "Music"
        case .settings:
            "Settings"
        }
    }
}

public struct JellyfinPosterItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?

    public init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

public struct JellyfinHomeSectionContent: Equatable, Sendable {
    public var upNext: [JellyfinPosterItem]
    public var recentlyAddedTVShows: [JellyfinPosterItem]
    public var recentlyAddedMovies: [JellyfinPosterItem]

    public init(
        upNext: [JellyfinPosterItem] = [],
        recentlyAddedTVShows: [JellyfinPosterItem] = [],
        recentlyAddedMovies: [JellyfinPosterItem] = []
    ) {
        self.upNext = upNext
        self.recentlyAddedTVShows = recentlyAddedTVShows
        self.recentlyAddedMovies = recentlyAddedMovies
    }
}

public struct JellyfinPosterSection: Equatable, Sendable {
    public let title: String
    public let items: [JellyfinPosterItem]

    public init(title: String, items: [JellyfinPosterItem]) {
        self.title = title
        self.items = items
    }
}

public struct JellyfinPosterCatalog: Equatable, Sendable {
    public private(set) var libraryItems: [String: [JellyfinPosterItem]]

    public init(libraryItems: [String: [JellyfinPosterItem]] = [:]) {
        self.libraryItems = libraryItems
    }

    public func items(for libraryID: String) -> [JellyfinPosterItem] {
        libraryItems[libraryID] ?? []
    }

    public mutating func setItems(_ items: [JellyfinPosterItem], for libraryID: String) {
        libraryItems[libraryID] = items
    }
}

public struct JellyfinAppState: Equatable, Sendable {
    public var launchState: JellyfinLaunchState
    public var onboardingStep: JellyfinOnboardingStep
    public var discoveredServers: [DiscoveredServer]
    public var selectedServer: DiscoveredServer?
    public var manualServerAddress: String
    public var signInMethod: JellyfinSignInMethod
    public var session: JellyfinSession?
    public var libraries: [JellyfinLibrary]
    public var homeContent: JellyfinHomeSectionContent
    public var posterCatalog: JellyfinPosterCatalog
    public var selectedNavigationItem: JellyfinNavigationItem

    public init(
        launchState: JellyfinLaunchState = .firstLaunch,
        onboardingStep: JellyfinOnboardingStep = .welcome,
        discoveredServers: [DiscoveredServer] = [],
        selectedServer: DiscoveredServer? = nil,
        manualServerAddress: String = "",
        signInMethod: JellyfinSignInMethod = .autodiscovery,
        session: JellyfinSession? = nil,
        libraries: [JellyfinLibrary] = [],
        homeContent: JellyfinHomeSectionContent = JellyfinHomeSectionContent(),
        posterCatalog: JellyfinPosterCatalog = JellyfinPosterCatalog(),
        selectedNavigationItem: JellyfinNavigationItem = .home
    ) {
        self.launchState = launchState
        self.onboardingStep = onboardingStep
        self.discoveredServers = discoveredServers
        self.selectedServer = selectedServer
        self.manualServerAddress = manualServerAddress
        self.signInMethod = signInMethod
        self.session = session
        self.libraries = libraries.sorted(by: librarySort)
        self.homeContent = homeContent
        self.posterCatalog = posterCatalog
        self.selectedNavigationItem = selectedNavigationItem
        normalizeSelection()
    }

    public var visibleNavigationItems: [JellyfinNavigationItem] {
        var items: [JellyfinNavigationItem] = [.home]
        if hasLibrary(of: .movies) {
            items.append(.movies)
        }
        if hasLibrary(of: .tvshows) {
            items.append(.tvShows)
        }
        if hasLibrary(of: .music) {
            items.append(.music)
        }
        items.append(.settings)
        return items
    }

    public var hasManualServerAddress: Bool {
        !trimmedManualServerAddress.isEmpty
    }

    public func hasLibrary(of collectionType: LibraryCollectionType) -> Bool {
        libraries.contains { $0.collectionType == collectionType }
    }

    public func libraries(for collectionType: LibraryCollectionType) -> [JellyfinLibrary] {
        libraries.filter { $0.collectionType == collectionType }
    }

    public mutating func beginDiscovery() {
        launchState = .signedOut
        onboardingStep = .discoveringServers
    }

    public mutating func applyDiscoveredServers(
        _ servers: [DiscoveredServer],
        discovery: JellyfinDiscovery = JellyfinDiscovery(),
        preferredHost: String? = nil
    ) {
        launchState = .signedOut
        discoveredServers = discovery.prioritizeReachableServers(servers, preferredHost: preferredHost)
        onboardingStep = discoveredServers.isEmpty ? .manualServerEntry : .selectServer
    }

    public mutating func selectServer(_ server: DiscoveredServer) {
        launchState = .signedOut
        selectedServer = server
        manualServerAddress = server.address.absoluteString
        onboardingStep = .signIn
    }

    public mutating func showManualServerEntry() {
        launchState = .signedOut
        onboardingStep = .manualServerEntry
    }

    public mutating func updateManualServerAddress(_ value: String) {
        manualServerAddress = value
    }

    public func resolvedManualServer() throws -> DiscoveredServer {
        let trimmed = trimmedManualServerAddress
        guard hasManualServerAddress else {
            throw JellyfinClientError.invalidURL
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.host() != nil else {
            throw JellyfinClientError.invalidURL
        }

        return DiscoveredServer(
            id: url.absoluteString,
            name: url.host() ?? candidate,
            address: url
        )
    }

    public mutating func commitManualServer(_ server: DiscoveredServer) {
        launchState = .signedOut
        selectedServer = server
        manualServerAddress = server.address.absoluteString
        onboardingStep = .signIn
    }

    public mutating func commitManualServer() throws {
        commitManualServer(try resolvedManualServer())
    }

    public mutating func updateSignInMethod(_ method: JellyfinSignInMethod) {
        signInMethod = method
    }

    public mutating func completeSignIn(
        session: JellyfinSession,
        libraries: [JellyfinLibrary],
        homeContent: JellyfinHomeSectionContent = JellyfinHomeSectionContent(),
        posterCatalog: JellyfinPosterCatalog = JellyfinPosterCatalog()
    ) {
        self.session = session
        self.libraries = libraries.sorted(by: librarySort)
        self.homeContent = homeContent
        self.posterCatalog = posterCatalog
        launchState = .signedIn
        selectedNavigationItem = .home
        normalizeSelection()
    }

    public mutating func updateLibraries(_ libraries: [JellyfinLibrary]) {
        self.libraries = libraries.sorted(by: librarySort)
        normalizeSelection()
    }

    public mutating func updateHomeContent(_ homeContent: JellyfinHomeSectionContent) {
        self.homeContent = homeContent
    }

    public mutating func signOut() {
        launchState = .signedOut
        onboardingStep = .welcome
        selectedServer = nil
        session = nil
        libraries = []
        homeContent = JellyfinHomeSectionContent()
        posterCatalog = JellyfinPosterCatalog()
        selectedNavigationItem = .home
    }

    public mutating func updateSelectedNavigationItem(_ item: JellyfinNavigationItem) {
        selectedNavigationItem = item
        normalizeSelection()
    }

    public mutating func setPosterItems(_ items: [JellyfinPosterItem], for libraryID: String) {
        posterCatalog.setItems(items, for: libraryID)
    }

    private mutating func normalizeSelection() {
        if !visibleNavigationItems.contains(selectedNavigationItem) {
            selectedNavigationItem = .home
        }
    }

    private var trimmedManualServerAddress: String {
        manualServerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct JellyfinPosterBrowser: Sendable {
    public init() {}

    public func sections(for items: [JellyfinPosterItem]) -> [JellyfinPosterSection] {
        let grouped = Dictionary(grouping: items.sorted(by: posterSort)) { item in
            sectionTitle(for: item.title)
        }

        return grouped.keys.sorted().map { key in
            JellyfinPosterSection(
                title: key,
                items: grouped[key, default: []].sorted(by: posterSort)
            )
        }
    }

    public func indexTitles(for items: [JellyfinPosterItem]) -> [String] {
        sections(for: items).map(\.title)
    }

    private func sectionTitle(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstScalar = trimmed.unicodeScalars.first else {
            return "#"
        }

        return CharacterSet.alphanumerics.contains(firstScalar)
            ? String(firstScalar).uppercased()
            : "#"
    }

    private func posterSort(lhs: JellyfinPosterItem, rhs: JellyfinPosterItem) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private func librarySort(lhs: JellyfinLibrary, rhs: JellyfinLibrary) -> Bool {
    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
}
