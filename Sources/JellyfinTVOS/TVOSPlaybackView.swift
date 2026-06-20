#if canImport(AVKit) && canImport(SwiftUI) && os(tvOS)
import AVKit
import SwiftUI

public struct JellyfinPlaybackView: View {
    @State private var player: AVPlayer

    public init(request: PlaybackRequest) {
        _player = State(initialValue: AVPlayer(url: request.url))
    }

    public var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}
#endif
