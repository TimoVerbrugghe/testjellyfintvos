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

private func makeClient() -> JellyfinClient {
    JellyfinClient(
        server: JellyfinServer(baseURL: URL(string: "https://demo.jellyfin.org/")!),
        session: JellyfinSession(accessToken: "token", userID: "user", deviceID: "device")
    )
}
