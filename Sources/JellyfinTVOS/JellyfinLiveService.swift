import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct JellyfinHTTPTransport: Sendable {
    public typealias Response = (Data, HTTPURLResponse)

    private let execute: @Sendable (URLRequest) async throws -> Response

    public init(execute: @escaping @Sendable (URLRequest) async throws -> Response) {
        self.execute = execute
    }

    public func send(_ request: URLRequest) async throws -> Response {
        try await execute(request)
    }

    public static func urlSession(_ session: URLSession = .shared) -> JellyfinHTTPTransport {
        JellyfinHTTPTransport { request in
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JellyfinLiveServiceError.invalidResponse
            }

            return (data, httpResponse)
        }
    }
}

public struct JellyfinSignedInContent: Equatable, Sendable {
    public let libraries: [JellyfinLibrary]
    public let homeContent: JellyfinHomeSectionContent
    public let posterCatalog: JellyfinPosterCatalog

    public init(
        libraries: [JellyfinLibrary],
        homeContent: JellyfinHomeSectionContent,
        posterCatalog: JellyfinPosterCatalog
    ) {
        self.libraries = libraries
        self.homeContent = homeContent
        self.posterCatalog = posterCatalog
    }
}

public struct JellyfinLiveService: Sendable {
    public let transport: JellyfinHTTPTransport

    public init(transport: JellyfinHTTPTransport = .urlSession()) {
        self.transport = transport
    }

    public func validateServer(
        url: URL,
        deviceID: String,
        appVersion: String = JellyfinTVOS.appVersion
    ) async throws -> DiscoveredServer {
        let server = JellyfinServer(baseURL: url)
        let client = JellyfinSignInClient(server: server, deviceID: deviceID, appVersion: appVersion)
        let request = try client.makeDiscoveryValidationRequest()
        let info: JellyfinPublicSystemInfo = try await sendDecoding(request)
        return DiscoveredServer(
            id: server.baseURL.absoluteString,
            name: info.serverName ?? server.baseURL.host() ?? server.baseURL.absoluteString,
            address: server.baseURL
        )
    }

    public func authenticate(
        server: DiscoveredServer,
        credentials: UserCredentials,
        deviceID: String,
        appVersion: String = JellyfinTVOS.appVersion
    ) async throws -> JellyfinSession {
        let client = JellyfinSignInClient(
            server: JellyfinServer(baseURL: server.address),
            deviceID: deviceID,
            appVersion: appVersion
        )
        let request = try client.makeAuthenticateByNameRequest(credentials: credentials)
        let response: JellyfinAuthenticationResponse = try await sendDecoding(request)
        return JellyfinSession(
            accessToken: response.accessToken,
            userID: response.user.id,
            deviceID: deviceID,
            appVersion: appVersion
        )
    }

    public func beginQuickConnect(
        server: DiscoveredServer,
        deviceID: String,
        appVersion: String = JellyfinTVOS.appVersion
    ) async throws -> QuickConnectCode {
        let client = JellyfinSignInClient(
            server: JellyfinServer(baseURL: server.address),
            deviceID: deviceID,
            appVersion: appVersion
        )
        let request = try client.makeQuickConnectInitiateRequest()
        return try await sendDecoding(request)
    }

    public func completeQuickConnect(
        server: DiscoveredServer,
        secret: String,
        deviceID: String,
        appVersion: String = JellyfinTVOS.appVersion,
        pollIntervalNanoseconds: UInt64 = 2_000_000_000,
        maxAttempts: Int = 150
    ) async throws -> JellyfinSession {
        let client = JellyfinSignInClient(
            server: JellyfinServer(baseURL: server.address),
            deviceID: deviceID,
            appVersion: appVersion
        )

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            let request = try client.makeQuickConnectConnectRequest(secret: secret)
            let (data, response) = try await transport.send(request)

            switch response.statusCode {
            case 200:
                let authenticationResponse = try makeDecoder().decode(JellyfinAuthenticationResponse.self, from: data)
                return JellyfinSession(
                    accessToken: authenticationResponse.accessToken,
                    userID: authenticationResponse.user.id,
                    deviceID: deviceID,
                    appVersion: appVersion
                )
            case 204, 401, 404:
                if attempt + 1 < maxAttempts {
                    try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                }
            default:
                throw try liveServiceError(for: response, data: data)
            }
        }

        throw JellyfinLiveServiceError.quickConnectTimedOut
    }

    public func loadSignedInContent(
        server: DiscoveredServer,
        session: JellyfinSession,
        posterLimit: Int = 200,
        homeLimit: Int = 12
    ) async throws -> JellyfinSignedInContent {
        let catalogClient = JellyfinCatalogClient(
            client: JellyfinClient(
                server: JellyfinServer(baseURL: server.address),
                session: session
            )
        )

        async let librariesTask = loadLibraries(using: catalogClient)
        async let upNextTask = loadResume(using: catalogClient, limit: homeLimit)
        async let showsTask = loadLatest(
            using: catalogClient,
            includeItemTypes: ["Series", "Episode"],
            limit: homeLimit
        )
        async let moviesTask = loadLatest(
            using: catalogClient,
            includeItemTypes: ["Movie"],
            limit: homeLimit
        )

        let libraries = try await librariesTask
        let posterCatalog = try await loadPosterCatalog(
            using: catalogClient,
            libraries: libraries,
            limit: posterLimit
        )

        return JellyfinSignedInContent(
            libraries: libraries,
            homeContent: JellyfinHomeSectionContent(
                upNext: try await upNextTask,
                recentlyAddedTVShows: try await showsTask,
                recentlyAddedMovies: try await moviesTask
            ),
            posterCatalog: posterCatalog
        )
    }

    private func loadLibraries(using client: JellyfinCatalogClient) async throws -> [JellyfinLibrary] {
        let response: CatalogResponse<JellyfinLibrary> = try await sendDecoding(client.makeLibrariesRequest())
        return response.items.filter { $0.collectionType != .unknown }
    }

    private func loadLatest(
        using client: JellyfinCatalogClient,
        includeItemTypes: [String],
        limit: Int
    ) async throws -> [JellyfinPosterItem] {
        let response: [JellyfinMediaListItem] = try await sendDecoding(
            client.makeLatestRequest(includeItemTypes: includeItemTypes, limit: limit)
        )
        return response.map(\.posterItem)
    }

    private func loadResume(using client: JellyfinCatalogClient, limit: Int) async throws -> [JellyfinPosterItem] {
        let response: CatalogResponse<JellyfinMediaListItem> = try await sendDecoding(
            client.makeResumeRequest(limit: limit)
        )
        return response.items.map(\.posterItem)
    }

    private func loadPosterCatalog(
        using client: JellyfinCatalogClient,
        libraries: [JellyfinLibrary],
        limit: Int
    ) async throws -> JellyfinPosterCatalog {
        let results = try await withThrowingTaskGroup(of: (String, [JellyfinPosterItem]).self) { group in
            for library in libraries {
                guard let itemTypes = itemTypes(for: library.collectionType) else {
                    continue
                }

                group.addTask {
                    let response: CatalogResponse<JellyfinMediaListItem> = try await sendDecoding(
                        client.makeLibraryItemsRequest(
                            libraryID: library.id,
                            includeItemTypes: itemTypes,
                            recursive: true,
                            limit: limit
                        )
                    )
                    return (library.id, response.items.map(\.posterItem))
                }
            }

            var loaded = [(String, [JellyfinPosterItem])]()
            for try await entry in group {
                loaded.append(entry)
            }
            return loaded
        }

        var catalog = JellyfinPosterCatalog()
        for (libraryID, items) in results {
            catalog.setItems(items, for: libraryID)
        }
        return catalog
    }

    private func itemTypes(for collectionType: LibraryCollectionType) -> [String]? {
        switch collectionType {
        case .movies:
            ["Movie"]
        case .tvshows:
            ["Series"]
        case .music:
            ["MusicAlbum", "MusicArtist", "Audio"]
        case .unknown:
            nil
        }
    }

    private func sendDecoding<T: Decodable>(_ request: @autoclosure () throws -> URLRequest) async throws -> T {
        let builtRequest = try request()
        let (data, response) = try await transport.send(builtRequest)
        guard (200...299).contains(response.statusCode) else {
            throw try liveServiceError(for: response, data: data)
        }
        return try makeDecoder().decode(T.self, from: data)
    }

    private func liveServiceError(for response: HTTPURLResponse, data: Data) throws -> JellyfinLiveServiceError {
        if
            let payload = try? makeDecoder().decode(JellyfinErrorPayload.self, from: data),
            let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines),
            !message.isEmpty
        {
            return .api(message)
        }

        if
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        {
            return .statusCode(response.statusCode, text)
        }

        return .statusCode(response.statusCode, nil)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum JellyfinLiveServiceError: Error, Equatable {
    case invalidResponse
    case statusCode(Int, String?)
    case api(String)
    case quickConnectTimedOut
}

extension JellyfinLiveServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The Jellyfin server returned an invalid response."
        case .statusCode(let code, let message):
            if let message, !message.isEmpty {
                "Jellyfin returned HTTP \(code): \(message)"
            } else {
                "Jellyfin returned HTTP \(code)."
            }
        case .api(let message):
            message
        case .quickConnectTimedOut:
            "Quick Connect timed out before the device was approved."
        }
    }
}

struct JellyfinPublicSystemInfo: Codable, Equatable {
    let serverName: String?

    private enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
    }
}

struct JellyfinAuthenticationResponse: Codable, Equatable {
    let accessToken: String
    let user: JellyfinAuthenticatedUser

    private enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

struct JellyfinAuthenticatedUser: Codable, Equatable {
    let id: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}

struct JellyfinErrorPayload: Codable, Equatable {
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case message = "Message"
    }
}

struct JellyfinMediaListItem: Codable, Equatable {
    let id: String
    let name: String
    let type: String?
    let seriesName: String?
    let productionYear: Int?
    let albumArtist: String?
    let artists: [String]?

    var posterItem: JellyfinPosterItem {
        JellyfinPosterItem(
            id: id,
            title: name,
            subtitle: subtitle
        )
    }

    private var subtitle: String? {
        if let seriesName, !seriesName.isEmpty, seriesName != name {
            return seriesName
        }

        if let albumArtist, !albumArtist.isEmpty {
            return albumArtist
        }

        if let artist = artists?.first, !artist.isEmpty {
            return artist
        }

        if let productionYear {
            return String(productionYear)
        }

        guard let type else {
            return nil
        }

        switch type {
        case "Movie":
            return "Movie"
        case "Series":
            return "TV Show"
        case "Episode":
            return "Episode"
        case "MusicAlbum":
            return "Album"
        case "MusicArtist":
            return "Artist"
        case "Audio":
            return "Track"
        default:
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case seriesName = "SeriesName"
        case productionYear = "ProductionYear"
        case albumArtist = "AlbumArtist"
        case artists = "Artists"
    }
}
