#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

public enum JellyfinSignInMethod: String, CaseIterable, Identifiable, Sendable {
    case autodiscovery
    case usernamePassword
    case quickConnect

    public var id: String { rawValue }
}

@MainActor
public final class JellyfinAppModel: ObservableObject {
    @Published public var signInMethod: JellyfinSignInMethod = .autodiscovery
    @Published public var libraries: [JellyfinLibrary] = []
    @Published public var selectedLibrary: JellyfinLibrary?
    @Published public var selectedItem: JellyfinItem?
    @Published public var seasons: [JellyfinSeason] = []
    @Published public var episodes: [JellyfinEpisode] = []
    @Published public var pendingPlayback: PlaybackRequest?

    private let catalogClient: JellyfinCatalogClient
    private let playbackBuilder: PlaybackRequestBuilder

    public init(catalogClient: JellyfinCatalogClient, playbackBuilder: PlaybackRequestBuilder) {
        self.catalogClient = catalogClient
        self.playbackBuilder = playbackBuilder
    }

    public func applyLibraries(_ libraries: [JellyfinLibrary]) {
        self.libraries = libraries.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func select(item: JellyfinItem) {
        selectedItem = item
        switch catalogClient.nextSelection(for: item, seasons: seasons, episodes: episodes) {
        case .readyToPlay:
            pendingPlayback = try? playbackBuilder.makeRequest(for: item)
        case .seasonList(_, let seasons):
            self.seasons = seasons
            self.episodes = []
        case .episodeList(_, _, let episodes):
            self.episodes = episodes
        }
    }
}

public struct JellyfinBrowserView: View {
    @ObservedObject private var model: JellyfinAppModel

    public init(model: JellyfinAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Sign in") {
                    Picker("Method", selection: $model.signInMethod) {
                        ForEach(JellyfinSignInMethod.allCases) { method in
                            Text(title(for: method)).tag(method)
                        }
                    }
                }

                Section("Libraries") {
                    ForEach(model.libraries, id: \.id) { library in
                        Button(library.name) {
                            model.selectedLibrary = library
                        }
                    }
                }

                if !model.seasons.isEmpty {
                    Section("Seasons") {
                        ForEach(model.seasons, id: \.id) { season in
                            Text(season.name)
                        }
                    }
                }

                if !model.episodes.isEmpty {
                    Section("Episodes") {
                        ForEach(model.episodes, id: \.id) { episode in
                            Text(episode.name)
                        }
                    }
                }
            }
            .navigationTitle("Jellyfin")
        }
    }

    private func title(for method: JellyfinSignInMethod) -> String {
        switch method {
        case .autodiscovery:
            "Auto-discover"
        case .usernamePassword:
            "Username / Password"
        case .quickConnect:
            "Quick Connect"
        }
    }
}
#endif
