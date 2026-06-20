import Foundation
import Testing
@testable import JellyfinTVOS

@Test func authorizationHeaderIncludesNativeAppIdentity() async throws {
    let session = JellyfinSession(accessToken: "token", userID: "user", deviceID: "device")

    #expect(session.authorizationHeaderValue.contains("Client=\"JellyfinTVOS\""))
    #expect(session.authorizationHeaderValue.contains("Device=\"Apple TV\""))
    #expect(session.authorizationHeaderValue.contains("Token=\"token\""))
}

@Test func playbackProfileAdvertisesDolbyVisionAndSubtitleSupport() async throws {
    let profile = PlaybackProfile.nativeTVOS

    #expect(profile.supportedVideoRanges.contains(.dolbyVisionProfile5))
    #expect(profile.supportedVideoRanges.contains(.dolbyVisionProfile8))
    #expect(profile.supportedSubtitleCodecs.contains(.ass))
    #expect(profile.supportedSubtitleCodecs.contains(.subgen))
    #expect(profile.supportsTranscoding)
}

@Test func subtitleSelectionPrefersMatchingLanguageSDHAndASS() async throws {
    let preferences = SubtitlePreferences(preferredLanguages: ["en"], prefersSDH: true, prefersASS: true, prefersSubgen: false)
    let subtitles = [
        SubtitleStream(index: 0, codec: .srt, languageCode: "en"),
        SubtitleStream(index: 1, codec: .ass, languageCode: "en", isSDH: true),
        SubtitleStream(index: 2, codec: .subgen, languageCode: "en")
    ]

    let selected = preferences.selectSubtitle(from: subtitles)

    #expect(selected?.index == 1)
}

@Test func directPlayUsesStaticStreamURLWhenSupported() async throws {
    let builder = PlaybackRequestBuilder(client: makeClient())
    let item = JellyfinItem(
        id: "item-1",
        name: "Movie",
        type: .movie,
        mediaSources: [
            MediaSource(
                id: "source-1",
                container: "mp4",
                videoCodec: "hevc",
                videoRange: .dolbyVisionProfile8,
                supportsDirectPlay: true,
                subtitleStreams: [SubtitleStream(index: 3, codec: .ass, languageCode: "en")]
            )
        ]
    )

    let request = try builder.makeRequest(for: item)

    #expect(request.mode == .directPlay)
    #expect(request.url.absoluteString.contains("/Videos/item-1/stream"))
    #expect(request.url.query?.contains("static=true") == true)
    #expect(request.subtitle?.codec == .ass)
}

@Test func transcodingFallsBackForUnsupportedVideoRangeAndUsesSubgenExternally() async throws {
    let builder = PlaybackRequestBuilder(client: makeClient())
    let item = JellyfinItem(
        id: "item-2",
        name: "Episode",
        type: .episode,
        mediaSources: [
            MediaSource(
                id: "source-2",
                container: "mkv",
                videoCodec: "av1",
                videoRange: .hdr10,
                supportsDirectPlay: false,
                subtitleStreams: [SubtitleStream(index: 4, codec: .subgen, languageCode: "en")]
            )
        ]
    )

    let request = try builder.makeRequest(for: item)

    #expect(request.mode == .transcode)
    #expect(request.url.absoluteString.contains("/Videos/item-2/master.m3u8"))
    #expect(request.url.query?.contains("SubtitleMethod=External") == true)
}

@Test func credentialAuthenticationUsesJellyfinPayloadShape() async throws {
    let signInClient = JellyfinSignInClient(
        server: JellyfinServer(baseURL: URL(string: "https://demo.jellyfin.org/")!),
        deviceID: "device"
    )

    let request = try signInClient.makeAuthenticateByNameRequest(
        credentials: UserCredentials(username: "tim", password: "secret")
    )
    let payload = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: payload) as? [String: String])

    #expect(request.url?.absoluteString == "https://demo.jellyfin.org/Users/AuthenticateByName")
    #expect(request.httpMethod == "POST")
    #expect(json["Username"] == "tim")
    #expect(json["Pw"] == "secret")
}

@Test func quickConnectRequestsUseExpectedEndpoints() async throws {
    let signInClient = JellyfinSignInClient(
        server: JellyfinServer(baseURL: URL(string: "https://demo.jellyfin.org")!),
        deviceID: "device"
    )

    let initiate = try signInClient.makeQuickConnectInitiateRequest()
    let authenticate = try signInClient.makeQuickConnectAuthenticateRequest(code: "ABCD")
    let connect = try signInClient.makeQuickConnectConnectRequest(secret: "secret")

    #expect(initiate.url?.absoluteString == "https://demo.jellyfin.org/QuickConnect/Initiate")
    #expect(authenticate.url?.absoluteString == "https://demo.jellyfin.org/QuickConnect/Authenticate")
    #expect(connect.url?.absoluteString == "https://demo.jellyfin.org/QuickConnect/Connect?Secret=secret")
}

@Test func catalogRequestsCoverLibrariesSeasonsAndEpisodes() async throws {
    let catalog = JellyfinCatalogClient(client: makeClient())

    let libraries = try catalog.makeLibrariesRequest()
    let libraryItems = try catalog.makeLibraryItemsRequest(libraryID: "library-1", include: [.movie, .series])
    let seasons = try catalog.makeSeasonsRequest(seriesID: "series-1")
    let episodes = try catalog.makeEpisodesRequest(seriesID: "series-1", seasonID: "season-1")

    #expect(libraries.url?.absoluteString == "https://demo.jellyfin.org/Users/user/Views")
    #expect(libraryItems.url?.absoluteString.contains("/Users/user/Items") == true)
    #expect(libraryItems.url?.query?.contains("ParentId=library-1") == true)
    #expect(libraryItems.url?.query?.contains("IncludeItemTypes=Movie,Series") == true)
    #expect(seasons.url?.absoluteString == "https://demo.jellyfin.org/Shows/series-1/Seasons")
    #expect(episodes.url?.absoluteString == "https://demo.jellyfin.org/Shows/series-1/Episodes?SeasonId=season-1")
}

@Test func discoveryDeduplicatesAndPrioritizesPreferredHost() async throws {
    let discovery = JellyfinDiscovery()
    let prioritized = discovery.prioritizeReachableServers(
        [
            DiscoveredServer(id: "2", name: "Remote", address: URL(string: "https://remote.example.com/")!),
            DiscoveredServer(id: "1", name: "Local", address: URL(string: "https://local.example.com/")!),
            DiscoveredServer(id: "3", name: "Remote Duplicate", address: URL(string: "https://remote.example.com/")!)
        ],
        preferredHost: "local.example.com"
    )

    #expect(prioritized.count == 2)
    #expect(prioritized.first?.name == "Local")
}

@Test func seriesSelectionReturnsSortedSeasonsOrEpisodes() async throws {
    let catalog = JellyfinCatalogClient(client: makeClient())
    let show = JellyfinItem(id: "show-1", name: "Show", type: .series, mediaSources: [])

    let seasonSelection = catalog.nextSelection(
        for: show,
        seasons: [
            JellyfinSeason(id: "season-2", name: "Season 2", indexNumber: 2),
            JellyfinSeason(id: "season-1", name: "Season 1", indexNumber: 1)
        ]
    )
    let episodeSelection = catalog.nextSelection(
        for: show,
        episodes: [
            JellyfinEpisode(id: "episode-2", name: "Episode 2", seasonID: "season-1", indexNumber: 2),
            JellyfinEpisode(id: "episode-1", name: "Episode 1", seasonID: "season-1", indexNumber: 1)
        ]
    )

    if case let .seasonList(_, seasons) = seasonSelection {
        #expect(seasons.map(\.id) == ["season-1", "season-2"])
    } else {
        Issue.record("Expected a season list for a series without episode data")
    }

    if case let .episodeList(_, seasonID, episodes) = episodeSelection {
        #expect(seasonID == "season-1")
        #expect(episodes.map(\.id) == ["episode-1", "episode-2"])
    } else {
        Issue.record("Expected an episode list for a series with episode data")
    }
}

private func makeClient() -> JellyfinClient {
    JellyfinClient(
        server: JellyfinServer(baseURL: URL(string: "https://demo.jellyfin.org/")!),
        session: JellyfinSession(accessToken: "token", userID: "user", deviceID: "device")
    )
}
