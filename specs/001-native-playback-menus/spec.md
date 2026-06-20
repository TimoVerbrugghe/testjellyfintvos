# Feature Specification: Native tvOS playback menus and info panels

**Feature Branch**: `[001-native-playback-menus]`

**Created**: 2026-06-20

**Status**: Draft

**Input**: User description: "During playback of media, add subtitle selection, audio track selection, and dialogue options above the seek bar, plus separate Info, Cast & Crew, and Chapters panels below the seek bar. Keep playback native AVPlayer-based, align with Apple's tvOS and liquid-glass design guidance, and do not build a custom video playback engine."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Access playback controls from the native player chrome (Priority: P1)

While video is playing, the viewer can open subtitle, audio-track, and dialogue-related controls from the playback transport area without leaving the native tvOS player experience.

**Why this priority**: Track and dialogue controls are the most immediate playback adjustments and need to remain discoverable in the standard playback UI.

**Independent Test**: Start playback, reveal the native transport controls, and verify the playback transport exposes subtitle, audio-track, and dialogue-related menu entry points without replacing AVPlayer.

**Acceptance Scenarios**:

1. **Given** a playable item with available subtitle tracks, **When** the user reveals the transport controls, **Then** subtitle selection is available from the native playback chrome.
2. **Given** a playable item with multiple audio tracks, **When** the user reveals the transport controls, **Then** audio-track selection is available from the native playback chrome.
3. **Given** dialogue enhancement is supported for the item, **When** the user reveals the transport controls, **Then** a dialogue options control is available and exposes on/off choices.

---

### User Story 2 - Browse contextual playback details below the seek bar (Priority: P1)

While paused on or navigating the transport controls, the viewer can move down into separate Info, Cast & Crew, and Chapters panels that feel like native tvOS playback surfaces.

**Why this priority**: The supporting panels are a core part of the requested playback experience and should remain reachable through familiar remote gestures rather than a separate custom overlay.

**Independent Test**: Start playback, reveal the transport controls, press down, and verify that Info, Cast & Crew, and Chapters panels are available as separate playback info tabs.

**Acceptance Scenarios**:

1. **Given** playback is active, **When** the user presses down from the transport controls, **Then** the player exposes an Info panel in the native info area.
2. **Given** playback is active, **When** the user navigates between playback info tabs, **Then** Cast & Crew and Chapters appear as separate panels alongside Info.
3. **Given** chapters are available, **When** the user opens the Chapters panel, **Then** each chapter is presented as an individually readable entry aligned with the current tvOS player layout.

---

### User Story 3 - Preserve Apple-native playback behavior and styling (Priority: P1)

The playback experience continues to use native AVPlayer and AVKit behavior, follows Apple's tvOS interaction model, and uses system-first visual treatments instead of a bespoke playback engine.

**Why this priority**: The user explicitly requires the playback flow to remain native and to align with Apple’s platform guidance.

**Independent Test**: Review the playback implementation and verify it is based on AVPlayer/AVPlayerViewController, keeps system playback gestures intact, and uses Apple-native info/transport surfaces rather than a custom full-screen control system.

**Acceptance Scenarios**:

1. **Given** the playback feature is implemented, **When** the code is reviewed, **Then** playback is still driven by AVPlayer and AVPlayerViewController rather than a custom video playback engine.
2. **Given** playback controls or panels are shown, **When** the user navigates with the Siri Remote, **Then** the interaction model follows native tvOS focus, transport, and info-panel behavior.
3. **Given** custom panels are rendered, **When** they appear over video, **Then** they use system-aligned materials and spacing that fit Apple’s tvOS design language.

### Edge Cases

- If an item has no alternate subtitle tracks, the subtitle control should remain understandable and must not imply unavailable choices can be selected.
- If an item has no alternate audio tracks, the audio-track control should communicate that limitation without breaking playback.
- If cast, crew, or chapter metadata is unavailable, the related panels should still open and present an explicit empty state.
- If dialogue enhancement is unsupported for the current stream, the dialogue options entry should communicate that the option is unavailable.
- If chapters are available, chapter markers should remain aligned with the seek bar as well as the dedicated chapters panel.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tvOS playback experience MUST continue to use native AVPlayer-based playback and MUST NOT introduce a custom video playback engine.
- **FR-002**: The playback UI MUST use AVPlayerViewController-native customization points to expose playback controls and info panels.
- **FR-003**: The playback transport MUST expose entry points for subtitle selection, audio-track selection, and dialogue options while the player chrome is visible.
- **FR-004**: The playback info area below the seek bar MUST expose three panels: Info, Cast & Crew, and Chapters.
- **FR-005**: The Info panel MUST use native playback metadata so it participates in the standard tvOS player information flow.
- **FR-006**: The Cast & Crew panel MUST present available cast and crew metadata and MUST show a clear empty state when that metadata is absent.
- **FR-007**: The Chapters panel MUST present chapter entries and SHOULD align those chapters with native seek-bar chapter markers when chapter metadata exists.
- **FR-008**: The implementation MUST preserve native tvOS focus behavior, transport gestures, and dismissal behavior.
- **FR-009**: The visual design of any custom playback panel content MUST align as closely as possible with Apple’s documented tvOS design guidance, including system materials, readable spacing, and system-first styling.
- **FR-010**: The implementation MUST remain compatible with the repository’s existing Swift package validation flow.

### Key Entities *(include if feature involves data)*

- **PlaybackPresentation**: Presentation metadata for the player, including the Info panel content, Cast & Crew entries, Chapters, and dialogue-option availability.
- **PlaybackContributor**: A person associated with the playing item, including a display name and role.
- **PlaybackChapter**: A chapter marker associated with the playing item, including a title and time boundaries.
- **DialogueOptions**: Capability metadata describing whether dialogue enhancement is available and whether it should default to enabled.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Playback continues to launch and render through native AVPlayer/AVPlayerViewController code paths with no custom playback engine introduced.
- **SC-002**: A reviewer can reveal the player chrome and find subtitle, audio-track, and dialogue-related playback controls from the native transport experience.
- **SC-003**: A reviewer can navigate down from the seek bar and find Info, Cast & Crew, and Chapters as distinct playback panels.
- **SC-004**: When playback metadata is incomplete, the related panels remain usable and communicate missing data through clear empty states instead of failing silently.

## Assumptions

- The package will continue to provide tvOS playback building blocks rather than a full end-user app-level Jellyfin metadata ingestion flow.
- Some playback metadata, such as cast, crew, chapters, and dialogue-enhancement support, may be supplied by higher-level Jellyfin integration code rather than discovered solely inside the current package.
- Apple-native AVKit controls and system materials are preferred over custom focusable overlays whenever the platform provides an official extension point.
