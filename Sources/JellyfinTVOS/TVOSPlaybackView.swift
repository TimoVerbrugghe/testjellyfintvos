#if canImport(AVKit) && canImport(SwiftUI) && os(tvOS)
import AVKit
import SwiftUI

@MainActor
final class JellyfinPlayerViewModel: ObservableObject {
    let player: AVPlayer

    init(request: PlaybackRequest) {
        self.player = AVPlayer(url: request.url)
    }
}

public struct JellyfinPlaybackView: View {
    @StateObject private var model: JellyfinPlayerViewModel

    public init(request: PlaybackRequest) {
        _model = StateObject(wrappedValue: JellyfinPlayerViewModel(request: request))
    }

    public var body: some View {
        VideoPlayer(player: model.player)
            .ignoresSafeArea()
            .onAppear { model.player.play() }
            .onDisappear { model.player.pause() }
    }
}
#endif
