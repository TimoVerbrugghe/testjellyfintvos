import Foundation

public struct JellyfinItem: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let type: JellyfinItemType
    public let mediaSources: [MediaSource]

    public init(id: String, name: String, type: JellyfinItemType, mediaSources: [MediaSource]) {
        self.id = id
        self.name = name
        self.type = type
        self.mediaSources = mediaSources
    }
}

public enum JellyfinItemType: String, Codable, Sendable {
    case movie = "Movie"
    case episode = "Episode"
    case series = "Series"
}

public struct MediaSource: Codable, Equatable, Sendable {
    public let id: String
    public let container: String
    public let videoCodec: String
    public let videoRange: VideoRange
    public let supportsDirectPlay: Bool
    public let subtitleStreams: [SubtitleStream]

    public init(
        id: String,
        container: String,
        videoCodec: String,
        videoRange: VideoRange,
        supportsDirectPlay: Bool,
        subtitleStreams: [SubtitleStream]
    ) {
        self.id = id
        self.container = container
        self.videoCodec = videoCodec
        self.videoRange = videoRange
        self.supportsDirectPlay = supportsDirectPlay
        self.subtitleStreams = subtitleStreams
    }
}

public enum VideoRange: String, Codable, CaseIterable, Sendable {
    case sdr = "SDR"
    case hdr10 = "HDR10"
    case dolbyVisionProfile5 = "DOVIProfile5"
    case dolbyVisionProfile8 = "DOVIProfile8"
}

public struct SubtitleStream: Codable, Equatable, Sendable {
    public let index: Int
    public let codec: SubtitleCodec
    public let languageCode: String
    public let isDefault: Bool
    public let isForced: Bool
    public let isSDH: Bool
    public let isExternal: Bool

    public init(
        index: Int,
        codec: SubtitleCodec,
        languageCode: String,
        isDefault: Bool = false,
        isForced: Bool = false,
        isSDH: Bool = false,
        isExternal: Bool = false
    ) {
        self.index = index
        self.codec = codec
        self.languageCode = languageCode
        self.isDefault = isDefault
        self.isForced = isForced
        self.isSDH = isSDH
        self.isExternal = isExternal
    }
}

public enum SubtitleCodec: String, Codable, CaseIterable, Sendable {
    case ass
    case srt
    case subrip
    case webvtt
    case subgen
}

public struct SubtitlePreferences: Equatable, Sendable {
    public let preferredLanguages: [String]
    public let prefersSDH: Bool
    public let prefersASS: Bool
    public let prefersSubgen: Bool

    public init(
        preferredLanguages: [String] = ["en"],
        prefersSDH: Bool = true,
        prefersASS: Bool = true,
        prefersSubgen: Bool = true
    ) {
        self.preferredLanguages = preferredLanguages
        self.prefersSDH = prefersSDH
        self.prefersASS = prefersASS
        self.prefersSubgen = prefersSubgen
    }

    public func selectSubtitle(from streams: [SubtitleStream]) -> SubtitleStream? {
        streams.max { score(for: $0) < score(for: $1) }
    }

    private func score(for stream: SubtitleStream) -> Int {
        // Prioritize preferred language matches first, then accessibility
        // variants like SDH, followed by subtitle codec preferences.
        var score = stream.isDefault ? 5 : 0

        if let languageIndex = preferredLanguages.firstIndex(of: stream.languageCode) {
            score += 100 - languageIndex
        }

        if stream.isForced {
            score += 2
        }

        if prefersSDH && stream.isSDH {
            score += 20
        }

        if prefersASS && stream.codec == .ass {
            score += 15
        }

        if prefersSubgen && stream.codec == .subgen {
            score += 10
        }

        if stream.isExternal {
            score += 1
        }

        return score
    }
}

public struct PlaybackProfile: Equatable, Sendable {
    public let supportedVideoRanges: Set<VideoRange>
    public let supportedSubtitleCodecs: Set<SubtitleCodec>
    public let maximumBitrate: Int
    public let supportsTranscoding: Bool

    public init(
        supportedVideoRanges: Set<VideoRange>,
        supportedSubtitleCodecs: Set<SubtitleCodec>,
        maximumBitrate: Int,
        supportsTranscoding: Bool
    ) {
        self.supportedVideoRanges = supportedVideoRanges
        self.supportedSubtitleCodecs = supportedSubtitleCodecs
        self.maximumBitrate = maximumBitrate
        self.supportsTranscoding = supportsTranscoding
    }

    public static let nativeTVOS = PlaybackProfile(
        supportedVideoRanges: [.sdr, .hdr10, .dolbyVisionProfile5, .dolbyVisionProfile8],
        supportedSubtitleCodecs: [.ass, .srt, .subrip, .webvtt, .subgen],
        maximumBitrate: 120_000_000,
        supportsTranscoding: true
    )

    public var deviceProfile: DeviceProfile {
        DeviceProfile(
            name: JellyfinTVOS.deviceName,
            maxStreamingBitrate: maximumBitrate,
            supportedVideoRanges: supportedVideoRanges.map(\.rawValue).sorted(),
            supportedSubtitleCodecs: supportedSubtitleCodecs.map(\.rawValue).sorted(),
            supportsTranscoding: supportsTranscoding
        )
    }

    public func supportsDirectPlay(of mediaSource: MediaSource, subtitle: SubtitleStream?) -> Bool {
        guard mediaSource.supportsDirectPlay else {
            return false
        }

        guard supportedVideoRanges.contains(mediaSource.videoRange) else {
            return false
        }

        guard let subtitle else {
            return true
        }

        return supportedSubtitleCodecs.contains(subtitle.codec)
    }
}

public struct DeviceProfile: Codable, Equatable, Sendable {
    public let name: String
    public let maxStreamingBitrate: Int
    public let supportedVideoRanges: [String]
    public let supportedSubtitleCodecs: [String]
    public let supportsTranscoding: Bool
}

public struct PlaybackContributor: Equatable, Sendable {
    public let name: String
    public let role: String

    public init(name: String, role: String) {
        self.name = name
        self.role = role
    }
}

public struct PlaybackChapter: Equatable, Sendable {
    public let title: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval?

    public init(title: String, startTime: TimeInterval, endTime: TimeInterval? = nil) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct DialogueOptions: Equatable, Sendable {
    public let isAvailable: Bool
    public let isEnabledByDefault: Bool

    public init(isAvailable: Bool = false, isEnabledByDefault: Bool = false) {
        self.isAvailable = isAvailable
        self.isEnabledByDefault = isEnabledByDefault
    }
}

public struct PlaybackPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let overview: String?
    public let badges: [String]
    public let castAndCrew: [PlaybackContributor]
    public let chapters: [PlaybackChapter]
    public let dialogueOptions: DialogueOptions

    public init(
        title: String,
        subtitle: String? = nil,
        overview: String? = nil,
        badges: [String] = [],
        castAndCrew: [PlaybackContributor] = [],
        chapters: [PlaybackChapter] = [],
        dialogueOptions: DialogueOptions = DialogueOptions()
    ) {
        self.title = title
        self.subtitle = subtitle
        self.overview = overview
        self.badges = badges
        self.castAndCrew = castAndCrew
        self.chapters = chapters
        self.dialogueOptions = dialogueOptions
    }
}

public struct PlaybackRequest: Equatable, Sendable {
    public let mode: PlaybackMode
    public let url: URL
    public let subtitle: SubtitleStream?
    public let availableSubtitles: [SubtitleStream]
    public let presentation: PlaybackPresentation

    public init(
        mode: PlaybackMode,
        url: URL,
        subtitle: SubtitleStream? = nil,
        availableSubtitles: [SubtitleStream] = [],
        presentation: PlaybackPresentation = PlaybackPresentation(title: "Now Playing")
    ) {
        self.mode = mode
        self.url = url
        self.subtitle = subtitle
        self.availableSubtitles = availableSubtitles
        self.presentation = presentation
    }
}

public enum PlaybackMode: String, Equatable, Sendable {
    case directPlay
    case transcode
}

public struct PlaybackRequestBuilder: Sendable {
    public let client: JellyfinClient

    public init(client: JellyfinClient) {
        self.client = client
    }

    public func makeRequest(
        for item: JellyfinItem,
        profile: PlaybackProfile = .nativeTVOS,
        subtitlePreferences: SubtitlePreferences = SubtitlePreferences()
    ) throws -> PlaybackRequest {
        guard let candidate = selectBestCandidate(
            from: item.mediaSources,
            profile: profile,
            subtitlePreferences: subtitlePreferences
        ) else {
            throw JellyfinClientError.missingMediaSource
        }

        let mediaSource = candidate.mediaSource
        let subtitle = candidate.subtitle
        let presentation = PlaybackPresentation(
            title: item.name,
            subtitle: item.type.presentationSubtitle,
            badges: makePresentationBadges(
                for: mediaSource,
                subtitle: subtitle,
                profile: profile
            )
        )

        if profile.supportsDirectPlay(of: mediaSource, subtitle: subtitle) {
            return PlaybackRequest(
                mode: .directPlay,
                url: try client.makeURL(
                    for: .directStream(item.id),
                    queryItems: [
                        URLQueryItem(name: "mediaSourceId", value: mediaSource.id),
                        URLQueryItem(name: "static", value: "true"),
                        URLQueryItem(name: "api_key", value: client.session.accessToken)
                    ]
                ),
                subtitle: subtitle,
                availableSubtitles: mediaSource.subtitleStreams,
                presentation: presentation
            )
        }

        var queryItems = [
            URLQueryItem(name: "mediaSourceId", value: mediaSource.id),
            URLQueryItem(name: "VideoCodec", value: "hevc,h264"),
            URLQueryItem(name: "AudioCodec", value: "aac,ac3,eac3"),
            URLQueryItem(name: "MaxStreamingBitrate", value: String(profile.maximumBitrate)),
            URLQueryItem(name: "api_key", value: client.session.accessToken)
        ]

        if let subtitle {
            queryItems.append(URLQueryItem(name: "SubtitleStreamIndex", value: String(subtitle.index)))
            queryItems.append(
                URLQueryItem(
                    name: "SubtitleMethod",
                    value: subtitle.codec == .subgen ? "External" : "Encode"
                )
            )
        }

        return PlaybackRequest(
            mode: .transcode,
            url: try client.makeURL(for: .transcodedStream(item.id), queryItems: queryItems),
            subtitle: subtitle,
            availableSubtitles: mediaSource.subtitleStreams,
            presentation: presentation
        )
    }

    private func selectBestCandidate(
        from mediaSources: [MediaSource],
        profile: PlaybackProfile,
        subtitlePreferences: SubtitlePreferences
    ) -> (mediaSource: MediaSource, subtitle: SubtitleStream?)? {
        mediaSources
            .map { mediaSource in
                let subtitle = subtitlePreferences.selectSubtitle(from: mediaSource.subtitleStreams)
                let isDirectPlayable = profile.supportsDirectPlay(of: mediaSource, subtitle: subtitle)
                var score = isDirectPlayable ? 1_000 : 0
                score += mediaSource.supportsDirectPlay ? 100 : 0
                score += profile.supportedVideoRanges.contains(mediaSource.videoRange) ? 50 : 0
                if let subtitle {
                    score += profile.supportedSubtitleCodecs.contains(subtitle.codec) ? 25 : 5
                }

                return (mediaSource: mediaSource, subtitle: subtitle, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                return lhs.mediaSource.id < rhs.mediaSource.id
            }
            .first
            .map { ($0.mediaSource, $0.subtitle) }
    }

    private func makePresentationBadges(
        for mediaSource: MediaSource,
        subtitle: SubtitleStream?,
        profile: PlaybackProfile
    ) -> [String] {
        var badges = [mediaSource.container.uppercased(), mediaSource.videoRange.rawValue]
        badges.append(profile.supportsDirectPlay(of: mediaSource, subtitle: subtitle) ? "Direct Play" : "Transcode")
        return badges
    }
}

private extension JellyfinItemType {
    var presentationSubtitle: String {
        switch self {
        case .movie:
            "Feature Film"
        case .episode:
            "TV Episode"
        case .series:
            "Series"
        }
    }
}
