import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct JellyfinServer: Equatable, Sendable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL.normalizedJellyfinServerURL()
    }
}

public struct JellyfinSession: Equatable, Sendable {
    public let accessToken: String
    public let userID: String
    public let deviceID: String
    public let appVersion: String

    public init(
        accessToken: String,
        userID: String,
        deviceID: String,
        appVersion: String = "1.0.0"
    ) {
        self.accessToken = accessToken
        self.userID = userID
        self.deviceID = deviceID
        self.appVersion = appVersion
    }

    public var authorizationHeaderValue: String {
        """
        MediaBrowser Client="\(JellyfinTVOS.clientName)", Device="\(JellyfinTVOS.deviceName)", DeviceId="\(deviceID)", Version="\(appVersion)", Token="\(accessToken)"
        """
    }
}

public struct JellyfinClient: Sendable {
    public enum Endpoint: Equatable, Sendable {
        case authenticateByName
        case userViews(String)
        case userItems(String)
        case latest(userID: String)
        case item(String)
        case playbackInfo(String)
        case showSeasons(String)
        case showEpisodes(String)
        case directStream(String)
        case transcodedStream(String)
    }

    public let server: JellyfinServer
    public let session: JellyfinSession
    public let decoder: JSONDecoder

    public init(server: JellyfinServer, session: JellyfinSession, decoder: JSONDecoder = JSONDecoder()) {
        self.server = server
        self.session = session
        self.decoder = decoder
    }

    public func makeRequest(
        for endpoint: Endpoint,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let url = try makeURL(for: endpoint, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(session.authorizationHeaderValue, forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func makePlaybackInfoRequest(
        itemID: String,
        profile: PlaybackProfile = .nativeTVOS
    ) throws -> URLRequest {
        var request = try makeRequest(for: .playbackInfo(itemID), method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(profile.deviceProfile)
        return request
    }

    public func makeURL(for endpoint: Endpoint, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false)
        components?.path = server.baseURL.path + endpoint.path
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw JellyfinClientError.invalidURL
        }

        return url
    }
}

public enum JellyfinClientError: Error, Equatable {
    case invalidURL
    case missingMediaSource
}

extension JellyfinClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The Jellyfin server URL is invalid."
        case .missingMediaSource:
            "This item does not have a playable media source."
        }
    }
}

private extension JellyfinClient.Endpoint {
    var path: String {
        switch self {
        case .authenticateByName:
            "/Users/AuthenticateByName"
        case .userViews(let userID):
            "/Users/\(userID)/Views"
        case .userItems(let userID):
            "/Users/\(userID)/Items"
        case .latest(let userID):
            "/Users/\(userID)/Items/Latest"
        case .item(let itemID):
            "/Items/\(itemID)"
        case .playbackInfo(let itemID):
            "/Items/\(itemID)/PlaybackInfo"
        case .showSeasons(let seriesID):
            "/Shows/\(seriesID)/Seasons"
        case .showEpisodes(let seriesID):
            "/Shows/\(seriesID)/Episodes"
        case .directStream(let itemID):
            "/Videos/\(itemID)/stream"
        case .transcodedStream(let itemID):
            "/Videos/\(itemID)/master.m3u8"
        }
    }
}

extension URL {
    func normalizedJellyfinServerURL() -> URL {
        let value = absoluteString

        guard value.hasSuffix("/"), value.count > 1 else {
            return self
        }

        return URL(string: String(value.dropLast())) ?? self
    }
}
