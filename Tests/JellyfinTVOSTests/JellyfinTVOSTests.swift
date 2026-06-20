import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
    #expect(request.availableSubtitles.map(\.index) == [3])
    #expect(request.presentation.title == "Movie")
    #expect(request.presentation.subtitle == "Feature Film")
    #expect(request.presentation.badges.contains("Direct Play"))
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
    #expect(request.presentation.badges.contains("Transcode"))
}

@Test func playbackPrefersBestDirectPlayableMediaSource() async throws {
    let builder = PlaybackRequestBuilder(client: makeClient())
    let item = JellyfinItem(
        id: "item-3",
        name: "Movie",
        type: .movie,
        mediaSources: [
            MediaSource(
                id: "source-a",
                container: "mkv",
                videoCodec: "av1",
                videoRange: .hdr10,
                supportsDirectPlay: false,
                subtitleStreams: []
            ),
            MediaSource(
                id: "source-b",
                container: "mp4",
                videoCodec: "hevc",
                videoRange: .dolbyVisionProfile5,
                supportsDirectPlay: true,
                subtitleStreams: []
            )
        ]
    )

    let request = try builder.makeRequest(for: item)

    #expect(request.mode == .directPlay)
    #expect(request.url.query?.contains("mediaSourceId=source-b") == true)
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

@Test func visibleNavigationItemsDependOnLibraryContentTypes() async throws {
    let state = JellyfinAppState(
        launchState: .signedIn,
        libraries: [
            JellyfinLibrary(id: "movies", name: "Movies", collectionType: .movies),
            JellyfinLibrary(id: "music", name: "Music", collectionType: .music)
        ]
    )

    #expect(state.visibleNavigationItems == [.home, .movies, .music, .settings])
}

@Test func onboardingStateTransitionsThroughDiscoverySelectionAndSignIn() async throws {
    var state = JellyfinAppState()
    let localServer = DiscoveredServer(
        id: "1",
        name: "Local",
        address: URL(string: "https://local.example.com")!
    )

    state.beginDiscovery()
    #expect(state.launchState == .signedOut)
    #expect(state.onboardingStep == .discoveringServers)

    state.applyDiscoveredServers([localServer])
    #expect(state.onboardingStep == .selectServer)
    #expect(state.discoveredServers == [localServer])

    state.selectServer(localServer)
    #expect(state.onboardingStep == .signIn)
    #expect(state.selectedServer == localServer)

    state.completeSignIn(
        session: JellyfinSession(accessToken: "token", userID: "user", deviceID: "device"),
        libraries: [JellyfinLibrary(id: "movies", name: "Movies", collectionType: .movies)]
    )
    #expect(state.launchState == .signedIn)
    #expect(state.visibleNavigationItems == [.home, .movies, .settings])
}

@Test func libraryFilteringRecognizesMusicLibraries() async throws {
    let state = JellyfinAppState(
        libraries: [
            JellyfinLibrary(id: "music-2", name: "Albums", collectionType: .music),
            JellyfinLibrary(id: "shows-1", name: "Shows", collectionType: .tvshows),
            JellyfinLibrary(id: "music-1", name: "Artists", collectionType: .music)
        ]
    )

    #expect(state.hasLibrary(of: .music))
    #expect(state.libraries(for: .music).map(\.name) == ["Albums", "Artists"])
}

@Test func alphabeticalGroupingBuildsLetterIndexForPosterItems() async throws {
    let browser = JellyfinPosterBrowser()
    let sections = browser.sections(
        for: [
            JellyfinPosterItem(id: "1", title: "Zebra"),
            JellyfinPosterItem(id: "2", title: "alpha"),
            JellyfinPosterItem(id: "3", title: "007"),
            JellyfinPosterItem(id: "4", title: "!special")
        ]
    )

    #expect(sections.map(\.title) == ["#", "0", "A", "Z"])
    #expect(sections.first?.items.map(\.title) == ["!special"])
    #expect(browser.indexTitles(for: sections.flatMap(\.items)) == ["#", "0", "A", "Z"])
}

@Test func manualServerResolutionNormalizesAddressBeforeCommit() async throws {
    var state = JellyfinAppState(manualServerAddress: "demo.jellyfin.org/")

    let server = try state.resolvedManualServer()
    state.commitManualServer(server)

    #expect(server.address.absoluteString == "https://demo.jellyfin.org")
    #expect(state.selectedServer?.address.absoluteString == "https://demo.jellyfin.org")
    #expect(state.onboardingStep == .signIn)
}

@Test func liveServiceValidatesAuthenticatesAndLoadsSignedInContent() async throws {
    let baseURL = "https://jellyfin.example.com"
    let responder = MockHTTPResponder(
        responses: [
            "\(baseURL)/System/Info/Public": [
                makeJSONResponse(url: "\(baseURL)/System/Info/Public", body: #"{"ServerName":"Living Room Jellyfin"}"#)
            ],
            "\(baseURL)/Users/AuthenticateByName": [
                makeJSONResponse(
                    url: "\(baseURL)/Users/AuthenticateByName",
                    body: #"{"AccessToken":"token-1","User":{"Id":"user-1"}}"#
                )
            ],
            "\(baseURL)/Users/user-1/Views": [
                makeJSONResponse(
                    url: "\(baseURL)/Users/user-1/Views",
                    body: #"{"Items":[{"Id":"movies","Name":"Movies","CollectionType":"movies"},{"Id":"shows","Name":"TV Shows","CollectionType":"tvshows"}]}"#
                )
            ],
            "\(baseURL)/Users/user-1/Items/Resume?Limit=12": [
                makeJSONResponse(
                    url: "\(baseURL)/Users/user-1/Items/Resume?Limit=12",
                    body: #"{"Items":[{"Id":"resume-1","Name":"Pilot","Type":"Episode","SeriesName":"Great Show"}]}"#
                )
            ],
            "\(baseURL)/Users/user-1/Items/Latest?IncludeItemTypes=Series,Episode&Limit=12&GroupItems=true": [
                makeJSONResponse(
                    url: "\(baseURL)/Users/user-1/Items/Latest?IncludeItemTypes=Series,Episode&Limit=12&GroupItems=true",
                    body: #"[{"Id":"show-1","Name":"Great Show","Type":"Series"}]"#
                )
            ],
            "\(baseURL)/Users/user-1/Items/Latest?IncludeItemTypes=Movie&Limit=12&GroupItems=true": [
                makeJSONResponse(
                    url: "\(baseURL)/Users/user-1/Items/Latest?IncludeItemTypes=Movie&Limit=12&GroupItems=true",
                    body: #"[{"Id":"movie-1","Name":"Movie Night","Type":"Movie","ProductionYear":2024}]"#
                )
            ],
            "\(baseURL)/Users/user-1/Items?ParentId=movies&IncludeItemTypes=Movie&Recursive=true&Limit=200": [
                makeJSONResponse(
                    url: "\(baseURL)/Users/user-1/Items?ParentId=movies&IncludeItemTypes=Movie&Recursive=true&Limit=200",
                    body: #"{"Items":[{"Id":"movie-a","Name":"Arrival","Type":"Movie"}]}"#
                )
            ],
            "\(baseURL)/Users/user-1/Items?ParentId=shows&IncludeItemTypes=Series&Recursive=true&Limit=200": [
                makeJSONResponse(
                    url: "\(baseURL)/Users/user-1/Items?ParentId=shows&IncludeItemTypes=Series&Recursive=true&Limit=200",
                    body: #"{"Items":[{"Id":"show-a","Name":"Severance","Type":"Series"}]}"#
                )
            ]
        ]
    )
    let service = JellyfinLiveService(
        transport: JellyfinHTTPTransport { request in
            try await responder.send(request)
        }
    )

    let server = try await service.validateServer(
        url: URL(string: "\(baseURL)/")!,
        deviceID: "device-1"
    )
    let session = try await service.authenticate(
        server: server,
        credentials: UserCredentials(username: "tim", password: "secret"),
        deviceID: "device-1"
    )
    let content = try await service.loadSignedInContent(server: server, session: session)

    #expect(server.name == "Living Room Jellyfin")
    #expect(session.accessToken == "token-1")
    #expect(content.libraries.map(\.id) == ["movies", "shows"])
    #expect(content.homeContent.upNext.map(\.title) == ["Pilot"])
    #expect(content.homeContent.recentlyAddedTVShows.map(\.title) == ["Great Show"])
    #expect(content.homeContent.recentlyAddedMovies.first?.subtitle == "2024")
    #expect(content.posterCatalog.items(for: "movies").map(\.title) == ["Arrival"])
    #expect(content.posterCatalog.items(for: "shows").map(\.title) == ["Severance"])
}

@Test func quickConnectPollingRetriesPendingResponses() async throws {
    let baseURL = "https://jellyfin.example.com"
    let connectURL = "\(baseURL)/QuickConnect/Connect?Secret=secret-1"
    let responder = MockHTTPResponder(
        responses: [
            "\(baseURL)/QuickConnect/Initiate": [
                makeJSONResponse(
                    url: "\(baseURL)/QuickConnect/Initiate",
                    body: #"{"Code":"ABCD","Secret":"secret-1"}"#
                )
            ],
            connectURL: [
                makeStatusResponse(url: connectURL, statusCode: 401),
                makeJSONResponse(
                    url: connectURL,
                    body: #"{"AccessToken":"token-quick","User":{"Id":"user-quick"}}"#
                )
            ]
        ]
    )
    let service = JellyfinLiveService(
        transport: JellyfinHTTPTransport { request in
            try await responder.send(request)
        }
    )
    let server = DiscoveredServer(
        id: baseURL,
        name: "Jellyfin",
        address: URL(string: baseURL)!
    )

    let code = try await service.beginQuickConnect(server: server, deviceID: "device-1")
    let session = try await service.completeQuickConnect(
        server: server,
        secret: code.secret,
        deviceID: "device-1",
        pollIntervalNanoseconds: 1,
        maxAttempts: 3
    )

    #expect(code.code == "ABCD")
    #expect(session.accessToken == "token-quick")
    #expect(await responder.requestCount(for: connectURL) == 2)
}

private func makeClient() -> JellyfinClient {
    JellyfinClient(
        server: JellyfinServer(baseURL: URL(string: "https://demo.jellyfin.org/")!),
        session: JellyfinSession(accessToken: "token", userID: "user", deviceID: "device")
    )
}

private actor MockHTTPResponder {
    private var responses: [String: [(Data, HTTPURLResponse)]]
    private var requestCounts: [String: Int] = [:]

    init(responses: [String: [(Data, HTTPURLResponse)]]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = try #require(request.url?.absoluteString)
        requestCounts[key, default: 0] += 1

        guard var entries = responses[key], !entries.isEmpty else {
            Issue.record("Missing mocked response for \(key)")
            throw JellyfinLiveServiceError.invalidResponse
        }

        let response = entries.removeFirst()
        responses[key] = entries
        return response
    }

    func requestCount(for url: String) -> Int {
        requestCounts[url, default: 0]
    }
}

private func makeJSONResponse(url: String, statusCode: Int = 200, body: String) -> (Data, HTTPURLResponse) {
    (
        Data(body.utf8),
        HTTPURLResponse(url: URL(string: url)!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    )
}

private func makeStatusResponse(url: String, statusCode: Int) -> (Data, HTTPURLResponse) {
    makeJSONResponse(url: url, statusCode: statusCode, body: "")
}
