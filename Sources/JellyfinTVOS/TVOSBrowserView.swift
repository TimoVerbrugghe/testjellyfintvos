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
    @Published public var selectedSeason: JellyfinSeason?
    @Published public var selectedEpisode: JellyfinEpisode?
    @Published public var seasons: [JellyfinSeason] = []
    @Published public var episodes: [JellyfinEpisode] = []
    @Published public var pendingPlayback: PlaybackRequest?
    @Published public var playbackErrorMessage: String?

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
            do {
                pendingPlayback = try playbackBuilder.makeRequest(for: item)
                playbackErrorMessage = nil
            } catch {
                playbackErrorMessage = String(describing: error)
            }
        case .seasonList(_, let seasons):
            self.seasons = seasons
            self.episodes = []
        case .episodeList(_, _, let episodes):
            self.episodes = episodes
        }
    }

    public func select(season: JellyfinSeason) {
        selectedSeason = season
        selectedEpisode = nil
    }

    public func select(episode: JellyfinEpisode) {
        selectedEpisode = episode
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
                            Button(season.name) {
                                model.select(season: season)
                            }
                        }
                    }
                }

                if !model.episodes.isEmpty {
                    Section("Episodes") {
                        ForEach(model.episodes, id: \.id) { episode in
                            Button(episode.name) {
                                model.select(episode: episode)
                            }
                        }
                    }
                }

                if let playbackErrorMessage = model.playbackErrorMessage {
                    Section("Playback") {
                        Text(playbackErrorMessage)
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
