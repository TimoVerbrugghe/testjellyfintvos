#if canImport(AVKit) && canImport(SwiftUI) && os(tvOS)
import AVKit
import SwiftUI

@MainActor
final class JellyfinPlayerViewModel: ObservableObject {
    let player: AVPlayer
    let request: PlaybackRequest

    @Published private(set) var mediaSelectionVersion: Int = 0
    @Published var isDialogueEnhancementEnabled: Bool

    private var playerItemStatusObservation: NSKeyValueObservation?

    init(request: PlaybackRequest) {
        self.request = request
        self.player = AVPlayer(url: request.url)
        self.isDialogueEnhancementEnabled = request.presentation.dialogueOptions.isEnabledByDefault

        configureCurrentItem()
        observeCurrentItem()
    }

    func selectMediaOption(_ option: AVMediaSelectionOption?, in group: AVMediaSelectionGroup) {
        player.currentItem?.select(option, in: group)
        mediaSelectionVersion += 1
    }

    func setDialogueEnhancement(enabled: Bool) {
        isDialogueEnhancementEnabled = enabled
    }

    func mediaSelectionState(for characteristic: AVMediaCharacteristic) -> MediaSelectionState? {
        guard
            let playerItem = player.currentItem,
            let group = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic)
        else {
            return nil
        }

        let selectedOption = playerItem.currentMediaSelection.selectedMediaOption(in: group)
        return MediaSelectionState(group: group, options: group.options, selectedOption: selectedOption)
    }

    private func configureCurrentItem() {
        guard let playerItem = player.currentItem else {
            return
        }

        playerItem.externalMetadata = makeExternalMetadata()
        let chapterMarkerGroups = makeNavigationMarkerGroups()
        if !chapterMarkerGroups.isEmpty {
            playerItem.navigationMarkerGroups = chapterMarkerGroups
        }
    }

    private func observeCurrentItem() {
        playerItemStatusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.mediaSelectionVersion += 1
            }
        }
    }

    private func makeExternalMetadata() -> [AVMetadataItem] {
        var items = [AVMetadataItem]()
        let presentation = request.presentation

        items.append(makeMetadataItem(.commonIdentifierTitle, value: presentation.title))

        if let subtitle = presentation.subtitle, !subtitle.isEmpty {
            items.append(makeMetadataItem(.iTunesMetadataTrackSubTitle, value: subtitle))
        }

        if let overview = presentation.overview, !overview.isEmpty {
            items.append(makeMetadataItem(.commonIdentifierDescription, value: overview))
        }

        items.append(makeMetadataItem(.commonIdentifierCreationDate, value: ""))

        return items
    }

    private func makeNavigationMarkerGroups() -> [AVNavigationMarkersGroup] {
        let chapters = request.presentation.chapters.sorted { $0.startTime < $1.startTime }
        guard !chapters.isEmpty else {
            return []
        }

        let timedMarkers = chapters.enumerated().map { index, chapter in
            let nextChapterStart = chapters.indices.contains(index + 1) ? chapters[index + 1].startTime : nil
            let endTime = max(chapter.endTime ?? nextChapterStart ?? (chapter.startTime + 1), chapter.startTime + 1)
            let timeRange = CMTimeRange(
                start: CMTime(seconds: chapter.startTime, preferredTimescale: 600),
                end: CMTime(seconds: endTime, preferredTimescale: 600)
            )

            return AVTimedMetadataGroup(
                items: [makeMetadataItem(.commonIdentifierTitle, value: chapter.title)],
                timeRange: timeRange
            )
        }

        return [AVNavigationMarkersGroup(title: nil, timedNavigationMarkers: timedMarkers)]
    }

    private func makeMetadataItem(_ identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
}

struct MediaSelectionState {
    let group: AVMediaSelectionGroup
    let options: [AVMediaSelectionOption]
    let selectedOption: AVMediaSelectionOption?
}

public struct JellyfinPlaybackView: View {
    @StateObject private var model: JellyfinPlayerViewModel

    public init(request: PlaybackRequest) {
        _model = StateObject(wrappedValue: JellyfinPlayerViewModel(request: request))
    }

    public var body: some View {
        NativeJellyfinPlayerView(model: model)
            .ignoresSafeArea()
            .onAppear { model.player.play() }
            .onDisappear { model.player.pause() }
    }
}

private struct NativeJellyfinPlayerView: UIViewControllerRepresentable {
    @ObservedObject var model: JellyfinPlayerViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = model.player
        controller.delegate = context.coordinator
        controller.showsPlaybackControls = true
        controller.playbackControlsIncludeInfoViews = true

        context.coordinator.configureInfoTabsIfNeeded(on: controller, model: model)
        updateTransportBar(on: controller, coordinator: context.coordinator)

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== model.player {
            controller.player = model.player
        }

        context.coordinator.configureInfoTabsIfNeeded(on: controller, model: model)
        context.coordinator.updateInfoTabs(model: model)
        updateTransportBar(on: controller, coordinator: context.coordinator)
    }

    private func updateTransportBar(on controller: AVPlayerViewController, coordinator: Coordinator) {
        guard #available(tvOS 16.0, *) else {
            return
        }

        let menuItems = [
            makeSubtitleMenu(),
            makeAudioTrackMenu(),
            makeDialogueMenu()
        ]

        let token = menuItems.map(\.title).joined(separator: "|")
            + "|\(model.mediaSelectionVersion)|\(model.isDialogueEnhancementEnabled)"

        guard coordinator.transportBarToken != token else {
            return
        }

        controller.transportBarCustomMenuItems = menuItems
        coordinator.transportBarToken = token
    }

    @available(tvOS 16.0, *)
    private func makeSubtitleMenu() -> UIMenu {
        makeMediaSelectionMenu(
            title: "Subtitle Select",
            systemImageName: "captions.bubble",
            characteristic: .legible,
            emptyStateTitle: model.request.availableSubtitles.isEmpty ? "No subtitles available" : "Subtitle options unavailable"
        )
    }

    @available(tvOS 16.0, *)
    private func makeAudioTrackMenu() -> UIMenu {
        makeMediaSelectionMenu(
            title: "Audio Track Select",
            systemImageName: "speaker.wave.2",
            characteristic: .audible,
            emptyStateTitle: "No alternate audio tracks available"
        )
    }

    @available(tvOS 16.0, *)
    private func makeMediaSelectionMenu(
        title: String,
        systemImageName: String,
        characteristic: AVMediaCharacteristic,
        emptyStateTitle: String
    ) -> UIMenu {
        guard let selectionState = model.mediaSelectionState(for: characteristic) else {
            return UIMenu(
                title: title,
                image: UIImage(systemName: systemImageName),
                children: [disabledAction(title: emptyStateTitle)]
            )
        }

        let offAction = UIAction(
            title: "Off",
            state: selectionState.selectedOption == nil ? .on : .off
        ) { _ in
            model.selectMediaOption(nil, in: selectionState.group)
        }

        let optionActions = selectionState.options.map { option in
            UIAction(
                title: option.displayName,
                state: option == selectionState.selectedOption ? .on : .off
            ) { _ in
                model.selectMediaOption(option, in: selectionState.group)
            }
        }

        return UIMenu(
            title: title,
            image: UIImage(systemName: systemImageName),
            children: [
                UIMenu(
                    title: "",
                    options: [.displayInline, .singleSelection],
                    children: [offAction] + optionActions
                )
            ]
        )
    }

    @available(tvOS 16.0, *)
    private func makeDialogueMenu() -> UIMenu {
        let dialogueOptions = model.request.presentation.dialogueOptions

        guard dialogueOptions.isAvailable else {
            return UIMenu(
                title: "Dialogue Options",
                image: UIImage(systemName: "captions.bubble.fill"),
                children: [disabledAction(title: "Enhance dialogue unavailable")]
            )
        }

        let offAction = UIAction(
            title: "Enhance Dialogue Off",
            state: model.isDialogueEnhancementEnabled ? .off : .on
        ) { _ in
            model.setDialogueEnhancement(enabled: false)
        }

        let onAction = UIAction(
            title: "Enhance Dialogue On",
            state: model.isDialogueEnhancementEnabled ? .on : .off
        ) { _ in
            model.setDialogueEnhancement(enabled: true)
        }

        return UIMenu(
            title: "Dialogue Options",
            image: UIImage(systemName: "captions.bubble.fill"),
            children: [
                UIMenu(
                    title: "",
                    options: [.displayInline, .singleSelection],
                    children: [offAction, onAction]
                )
            ]
        )
    }

    @available(tvOS 16.0, *)
    private func disabledAction(title: String) -> UIAction {
        let action = UIAction(title: title) { _ in }
        action.attributes = [.disabled]
        return action
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var transportBarToken: String?
        private var castAndCrewController: UIHostingController<CastAndCrewPanelView>?
        private var chaptersController: UIHostingController<ChaptersPanelView>?

        func configureInfoTabsIfNeeded(on controller: AVPlayerViewController, model: JellyfinPlayerViewModel) {
            if castAndCrewController == nil {
                let castController = UIHostingController(rootView: CastAndCrewPanelView(contributors: model.request.presentation.castAndCrew))
                castController.title = "Cast & Crew"
                castController.preferredContentSize = CGSize(width: 0, height: 460)
                castAndCrewController = castController
            }

            if chaptersController == nil {
                let chaptersTab = UIHostingController(rootView: ChaptersPanelView(chapters: model.request.presentation.chapters))
                chaptersTab.title = "Chapters"
                chaptersTab.preferredContentSize = CGSize(width: 0, height: 460)
                chaptersController = chaptersTab
            }

            guard let castAndCrewController, let chaptersController else {
                return
            }

            if controller.customInfoViewControllers.isEmpty {
                controller.customInfoViewControllers = [castAndCrewController, chaptersController]
            }
        }

        func updateInfoTabs(model: JellyfinPlayerViewModel) {
            castAndCrewController?.rootView = CastAndCrewPanelView(contributors: model.request.presentation.castAndCrew)
            chaptersController?.rootView = ChaptersPanelView(chapters: model.request.presentation.chapters)
        }
    }
}

private struct CastAndCrewPanelView: View {
    let contributors: [PlaybackContributor]

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 24)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Cast & Crew")
                    .font(.title2.weight(.semibold))

                if contributors.isEmpty {
                    EmptyPanelStateView(
                        title: "Cast and crew unavailable",
                        message: "Add Jellyfin people metadata to populate this panel."
                    )
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(Array(contributors.enumerated()), id: \.offset) { _, contributor in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(contributor.name)
                                    .font(.headline)
                                Text(contributor.role)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 64)
            .padding(.vertical, 40)
        }
        .background(Color.clear)
    }
}

private struct ChaptersPanelView: View {
    let chapters: [PlaybackChapter]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 24) {
                if chapters.isEmpty {
                    EmptyPanelStateView(
                        title: "No chapters available",
                        message: "Add Jellyfin chapter metadata to populate chapter cards and seek-bar markers."
                    )
                    .frame(width: 520, alignment: .leading)
                } else {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Chapter \(index + 1)")
                                .font(.headline)
                            Text(chapter.title)
                                .font(.title3.weight(.medium))
                                .lineLimit(2)
                            Text(chapter.timeRangeLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 360, height: 220, alignment: .leading)
                        .padding(28)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 40)
        }
        .background(Color.clear)
    }
}

private struct EmptyPanelStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private extension PlaybackChapter {
    var timeRangeLabel: String {
        let start = formatTime(startTime)
        if let endTime {
            return "\(start) · \(formatTime(endTime))"
        }

        return start
    }

    func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
