#if os(tvOS)
import Foundation
import SwiftUI
import JellyfinTVOS

@main
struct JellyfinTVOSDemoApp: App {
    @StateObject private var model = JellyfinTVOSDemoFactory.makeModel()

    var body: some Scene {
        WindowGroup {
            JellyfinBrowserView(model: model)
        }
    }
}

@MainActor
private enum JellyfinTVOSDemoFactory {
    static func makeModel() -> JellyfinAppModel {
        let appStateStore = JellyfinAppStateStore()
        let restoredState = appStateStore.loadState()
        let deviceID = restoredState?.session?.deviceID ?? appStateStore.persistentDeviceID()
        let serverURL = restoredState?.selectedServer?.address ?? URL(string: "https://demo.jellyfin.org/stable")!
        let server = JellyfinServer(baseURL: serverURL)
        let session = restoredState?.session ?? JellyfinSession(
            accessToken: "",
            userID: "",
            deviceID: deviceID
        )
        let client = JellyfinClient(server: server, session: session)

        return JellyfinAppModel(
            catalogClient: JellyfinCatalogClient(client: client),
            playbackBuilder: PlaybackRequestBuilder(client: client),
            appState: restoredState ?? JellyfinAppState(),
            appStateStore: appStateStore,
            deviceID: deviceID
        )
    }
}
#endif
