import Foundation

@MainActor
public final class JellyfinAppStateStore {
    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private let notificationCenter: NotificationCenter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let stateKey = "jellyfin.appState.v1"
    private let deviceIDKey = "jellyfin.deviceID.v1"
    private var syncHandler: ((JellyfinAppState) -> Void)?
    private var lastUpdatedAt: Date = .distantPast

    public init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore
        self.notificationCenter = notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(handleCloudStoreChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    public func loadState() -> JellyfinAppState? {
        let localEnvelope = defaults.data(forKey: stateKey).flatMap(decodeEnvelope)
        let cloudEnvelope = cloudStore.data(forKey: stateKey).flatMap(decodeEnvelope)

        let envelope: JellyfinPersistedAppStateEnvelope?
        if let localEnvelope, let cloudEnvelope {
            envelope = localEnvelope.updatedAt >= cloudEnvelope.updatedAt ? localEnvelope : cloudEnvelope
        } else {
            envelope = localEnvelope ?? cloudEnvelope
        }

        guard let envelope else {
            return nil
        }

        lastUpdatedAt = envelope.updatedAt
        return envelope.state
    }

    public func saveState(_ state: JellyfinAppState) {
        let envelope = JellyfinPersistedAppStateEnvelope(updatedAt: Date(), state: state)
        guard let data = try? encoder.encode(envelope) else {
            return
        }

        lastUpdatedAt = envelope.updatedAt
        defaults.set(data, forKey: stateKey)
        cloudStore.set(data, forKey: stateKey)
        cloudStore.synchronize()
    }

    public func persistentDeviceID() -> String {
        if let savedID = defaults.string(forKey: deviceIDKey), !savedID.isEmpty {
            return savedID
        }

        let newID = UUID().uuidString
        defaults.set(newID, forKey: deviceIDKey)
        cloudStore.set(newID, forKey: deviceIDKey)
        cloudStore.synchronize()
        return newID
    }

    public func startSync(handler: @escaping (JellyfinAppState) -> Void) {
        syncHandler = handler
    }

    @objc
    private func handleCloudStoreChange(_ notification: Notification) {
        guard
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
            changedKeys.contains(stateKey),
            let cloudData = cloudStore.data(forKey: stateKey),
            let cloudEnvelope = decodeEnvelope(cloudData),
            cloudEnvelope.updatedAt > lastUpdatedAt
        else {
            return
        }

        lastUpdatedAt = cloudEnvelope.updatedAt
        defaults.set(cloudData, forKey: stateKey)
        syncHandler?(cloudEnvelope.state)
    }

    private func decodeEnvelope(_ data: Data) -> JellyfinPersistedAppStateEnvelope? {
        try? decoder.decode(JellyfinPersistedAppStateEnvelope.self, from: data)
    }
}

private struct JellyfinPersistedAppStateEnvelope: Codable {
    let updatedAt: Date
    let state: JellyfinAppState
}
