import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DiscoveredServer: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let address: URL

    public init(id: String, name: String, address: URL) {
        self.id = id
        self.name = name
        self.address = address.normalizedJellyfinServerURL()
    }
}

public struct QuickConnectCode: Codable, Equatable, Sendable {
    public let code: String
    public let secret: String
    public let expiresAt: Date?

    public init(code: String, secret: String, expiresAt: Date? = nil) {
        self.code = code
        self.secret = secret
        self.expiresAt = expiresAt
    }
}

public struct UserCredentials: Codable, Equatable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct JellyfinLibrary: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let collectionType: LibraryCollectionType

    public init(id: String, name: String, collectionType: LibraryCollectionType) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
    }
}

public enum LibraryCollectionType: String, Codable, Equatable, Sendable {
    case movies
    case tvshows = "tvshows"
    case music
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(String.self)) ?? ""
        self = LibraryCollectionType(rawValue: value.lowercased()) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct JellyfinSeason: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let indexNumber: Int?

    public init(id: String, name: String, indexNumber: Int? = nil) {
        self.id = id
        self.name = name
        self.indexNumber = indexNumber
    }
}

public struct JellyfinEpisode: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let seasonID: String?
    public let indexNumber: Int?

    public init(id: String, name: String, seasonID: String? = nil, indexNumber: Int? = nil) {
        self.id = id
        self.name = name
        self.seasonID = seasonID
        self.indexNumber = indexNumber
    }
}

public struct AuthenticationRequestBody: Codable, Equatable, Sendable {
    public let username: String
    public let pw: String

    public init(credentials: UserCredentials) {
        self.username = credentials.username
        self.pw = credentials.password
    }

    private enum CodingKeys: String, CodingKey {
        case username = "Username"
        case pw = "Pw"
    }
}

public struct CatalogResponse<Item: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

public struct JellyfinSignInClient: Sendable {
    public let server: JellyfinServer
    public let deviceID: String
    public let appVersion: String

    public init(server: JellyfinServer, deviceID: String, appVersion: String = JellyfinTVOS.appVersion) {
        self.server = server
        self.deviceID = deviceID
        self.appVersion = appVersion
    }

    public func makeDiscoveryValidationRequest() throws -> URLRequest {
        var request = URLRequest(url: try makeURL(path: "/System/Info/Public"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func makeAuthenticateByNameRequest(credentials: UserCredentials) throws -> URLRequest {
        var request = URLRequest(url: try makeURL(path: "/Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonymousAuthorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONEncoder().encode(AuthenticationRequestBody(credentials: credentials))
        return request
    }

    public func makeQuickConnectInitiateRequest() throws -> URLRequest {
        var request = URLRequest(url: try makeURL(path: "/QuickConnect/Initiate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonymousAuthorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")
        return request
    }

    public func makeQuickConnectAuthenticateRequest(code: String) throws -> URLRequest {
        var request = URLRequest(url: try makeURL(path: "/QuickConnect/Authenticate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonymousAuthorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONEncoder().encode(["Code": code])
        return request
    }

    public func makeQuickConnectConnectRequest(secret: String) throws -> URLRequest {
        var request = URLRequest(
            url: try makeURL(
                path: "/QuickConnect/Connect",
                queryItems: [URLQueryItem(name: "Secret", value: secret)]
            )
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public var anonymousAuthorizationHeader: String {
        """
        MediaBrowser Client="\(JellyfinTVOS.clientName)", Device="\(JellyfinTVOS.deviceName)", DeviceId="\(deviceID)", Version="\(appVersion)"
        """
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false)
        components?.path = server.baseURL.path + path
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw JellyfinClientError.invalidURL
        }

        return url
    }
}

public struct JellyfinDiscovery: Sendable {
    public init() {}

    public func deduplicate(_ servers: [DiscoveredServer]) -> [DiscoveredServer] {
        var seen = Set<String>()
        return servers.filter { server in
            let key = server.address.absoluteString.lowercased()
            return seen.insert(key).inserted
        }
    }

    public func prioritizeReachableServers(_ servers: [DiscoveredServer], preferredHost: String? = nil) -> [DiscoveredServer] {
        deduplicate(servers).sorted { lhs, rhs in
            let lhsPreferred = preferredHost.map { lhs.address.host() == $0 } ?? false
            let rhsPreferred = preferredHost.map { rhs.address.host() == $0 } ?? false

            if lhsPreferred != rhsPreferred {
                return lhsPreferred
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

public struct JellyfinCatalogClient: Sendable {
    public let client: JellyfinClient

    public init(client: JellyfinClient) {
        self.client = client
    }

    public func makeLibrariesRequest() throws -> URLRequest {
        try client.makeRequest(for: .userViews(client.session.userID))
    }

    public func makeLibraryItemsRequest(libraryID: String, include itemTypes: [JellyfinItemType]) throws -> URLRequest {
        try makeLibraryItemsRequest(
            libraryID: libraryID,
            includeItemTypes: itemTypes.map(\.rawValue),
            recursive: false
        )
    }

    public func makeLibraryItemsRequest(
        libraryID: String,
        includeItemTypes: [String],
        recursive: Bool,
        limit: Int? = nil
    ) throws -> URLRequest {
        var queryItems = [
            URLQueryItem(name: "ParentId", value: libraryID),
            URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes.joined(separator: ",")),
            URLQueryItem(name: "Recursive", value: recursive ? "true" : "false")
        ]
        if let limit {
            queryItems.append(URLQueryItem(name: "Limit", value: String(limit)))
        }

        return try client.makeRequest(
            for: .userItems(client.session.userID),
            queryItems: queryItems
        )
    }

    public func makeSeasonsRequest(seriesID: String) throws -> URLRequest {
        try client.makeRequest(for: .showSeasons(seriesID))
    }

    public func makeEpisodesRequest(seriesID: String, seasonID: String) throws -> URLRequest {
        try client.makeRequest(
            for: .showEpisodes(seriesID),
            queryItems: [URLQueryItem(name: "SeasonId", value: seasonID)]
        )
    }

    public func makeLatestRequest(includeItemTypes: [String], limit: Int = 12) throws -> URLRequest {
        try client.makeRequest(
            for: .latest(userID: client.session.userID),
            queryItems: [
                URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes.joined(separator: ",")),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "GroupItems", value: "true")
            ]
        )
    }

    public func makeResumeRequest(limit: Int = 12) throws -> URLRequest {
        try client.makeRequest(
            for: .resume(client.session.userID),
            queryItems: [URLQueryItem(name: "Limit", value: String(limit))]
        )
    }

    public func nextSelection(
        for item: JellyfinItem,
        seasons: [JellyfinSeason] = [],
        episodes: [JellyfinEpisode] = []
    ) -> LibrarySelection {
        switch item.type {
        case .movie, .episode:
            return LibrarySelection.readyToPlay(item.id)
        case .series:
            let sortedEpisodes = episodes.sorted { lhs, rhs in
                episodeSort(lhs: lhs, rhs: rhs)
            }

            if let firstEpisode = sortedEpisodes.first {
                return LibrarySelection.episodeList(
                    seriesID: item.id,
                    seasonID: firstEpisode.seasonID,
                    episodes: sortedEpisodes
                )
            }

            return LibrarySelection.seasonList(
                seriesID: item.id,
                seasons: seasons.sorted { lhs, rhs in
                    seasonSort(lhs: lhs, rhs: rhs)
                }
            )
        }
    }

    private func seasonSort(lhs: JellyfinSeason, rhs: JellyfinSeason) -> Bool {
        switch (lhs.indexNumber, rhs.indexNumber) {
        case let (lhs?, rhs?):
            lhs < rhs
        case (.some, .none):
            true
        case (.none, .some):
            false
        case (.none, .none):
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func episodeSort(lhs: JellyfinEpisode, rhs: JellyfinEpisode) -> Bool {
        switch (lhs.indexNumber, rhs.indexNumber) {
        case let (lhs?, rhs?):
            lhs < rhs
        case (.some, .none):
            true
        case (.none, .some):
            false
        case (.none, .none):
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

public enum LibrarySelection: Equatable, Sendable {
    case seasonList(seriesID: String, seasons: [JellyfinSeason])
    case episodeList(seriesID: String, seasonID: String?, episodes: [JellyfinEpisode])
    case readyToPlay(String)
}

extension DiscoveredServer {
    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case address = "Address"
    }
}

extension QuickConnectCode {
    private enum CodingKeys: String, CodingKey {
        case code = "Code"
        case secret = "Secret"
        case expiresAt = "ExpiresAt"
    }
}

extension JellyfinLibrary {
    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case collectionType = "CollectionType"
    }
}

extension JellyfinSeason {
    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case indexNumber = "IndexNumber"
    }
}

extension JellyfinEpisode {
    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case seasonID = "SeasonId"
        case indexNumber = "IndexNumber"
    }
}
