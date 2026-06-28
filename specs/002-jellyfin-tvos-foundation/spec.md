# Feature Specification: Jellyfin tvOS product foundation

**Feature Branch**: `[002-jellyfin-tvos-foundation]`

**Created**: 2026-06-21

**Status**: Draft

**Input**: Product direction for a Jellyfin tvOS application that follows Apple coding/design guidance, keeps native AVPlayer playback, adopts liquid-glass style alignment, and ensures Dolby Vision profile 5/7/8 playback, subtitle style controls, and Jellyfin server autodiscovery.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Watch content with native Apple tvOS playback behavior (Priority: P1)

A viewer starts playback and interacts with controls that feel and behave like native tvOS, while stream handling remains compatible with required Dolby Vision profiles.

**Independent Test**: Launch playback for qualifying media and verify native AVPlayer/AVKit behavior remains intact while profiles 5/7/8 are represented in capability and playback request logic.

**Acceptance Scenarios**:

1. **Given** a title playable in Dolby Vision profile 5, 7, or 8, **When** playback is prepared, **Then** stream selection and request generation preserve native-compatible direct play behavior when supported.
2. **Given** playback controls are shown, **When** the user navigates transport and info surfaces, **Then** focus/gesture behavior stays native to tvOS player interaction.

---

### User Story 2 - Adjust subtitle presentation for readability (Priority: P1)

A viewer can change subtitle presentation characteristics to improve readability during playback.

**Independent Test**: Play an item with subtitle streams and verify subtitle-related controls include styling/formatting configuration paths or explicit unsupported states.

**Acceptance Scenarios**:

1. **Given** subtitle streams are available, **When** the user opens subtitle controls, **Then** they can choose stream and subtitle presentation options (such as size/style/format preferences supported by platform and stream type).
2. **Given** a chosen subtitle presentation setting, **When** playback continues, **Then** visible subtitles follow the selected style behavior consistently.

---

### User Story 3 - Discover and connect to Jellyfin servers quickly (Priority: P1)

A user onboarding on tvOS can discover available Jellyfin servers and connect without manually typing server details unless needed.

**Independent Test**: Start from signed-out state, run discovery, select a discovered server, and proceed through authentication and initial content load.

**Acceptance Scenarios**:

1. **Given** one or more reachable Jellyfin servers on network, **When** discovery runs, **Then** servers appear as deduplicated, selectable options.
2. **Given** a discovered server is selected, **When** sign-in succeeds, **Then** the app transitions to signed-in state and loads baseline catalog/home content.
3. **Given** discovery fails or returns nothing, **When** the user continues, **Then** manual server entry remains available with explicit validation errors.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Playback implementation MUST remain native AVPlayer/AVKit based.
- **FR-002**: Product UX MUST align with Apple tvOS interaction and visual guidance, including system-material/liquid-glass aligned presentation patterns.
- **FR-003**: Playback capability and request generation MUST explicitly support Dolby Vision profile 5, 7, and 8 handling.
- **FR-004**: Subtitle controls MUST support user selection of subtitle stream and available subtitle styling/formatting preferences.
- **FR-005**: Jellyfin server autodiscovery MUST be supported and integrated into onboarding/server-selection flow.
- **FR-006**: Discovery results MUST be deduplicated and stably ordered with preferred-host prioritization where configured.
- **FR-007**: Server validation/authentication failures MUST produce explicit user-visible error states without silent fallback.
- **FR-008**: Spec artifacts for this capability MUST remain compatible with the repository's Spec Kit workflow.

### Key Entities *(include if feature involves data)*

- **PlaybackCapabilityProfile**: Device/media capability declaration including Dolby Vision profile support and subtitle feature support.
- **SubtitlePresentationPreference**: User-selected subtitle stream and style/format choices.
- **DiscoveredServerCandidate**: Server identity discovered from network and validated for connection.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Code review confirms playback remains AVPlayer/AVKit based with no custom playback engine introduced.
- **SC-002**: Capability/request paths include explicit profile 5/7/8 handling for Dolby Vision.
- **SC-003**: Subtitle workflows expose both stream selection and styling/format controls where supported.
- **SC-004**: Signed-out onboarding supports server autodiscovery and successful transition into signed-in content state.

## Assumptions

- Some subtitle style controls may rely on platform-level APIs and stream codec capabilities.
- Some Dolby Vision profile handling depends on media source metadata quality from Jellyfin.
