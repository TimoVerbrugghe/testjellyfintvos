# Copilot instructions for JellyfinTVOS

## Project context

- Swift Package that provides native tvOS building blocks for Jellyfin clients.
- Playback must stay AVPlayer/AVKit based; do not introduce custom playback engines.
- Package targets Swift 6 language mode.

## Architecture touchpoints

- `Sources/JellyfinTVOS/AuthCatalog.swift`: auth/discovery/catalog request builders and catalog models.
- `Sources/JellyfinTVOS/JellyfinLiveService.swift`: live network service, quick connect flow, signed-in content loading.
- `Sources/JellyfinTVOS/Playback.swift`: playback profile, subtitle selection, playback request generation.
- `Sources/JellyfinTVOS/AppFlow.swift`: app state, onboarding flow, navigation and poster browser shaping.
- `Sources/JellyfinTVOS/TVOS*.swift`: tvOS-specific SwiftUI playback and browser views.
- `Tests/JellyfinTVOSTests/JellyfinTVOSTests.swift`: integration-style package tests and expected request shapes.

## Coding expectations

- Make surgical edits only; do not refactor unrelated surfaces.
- Preserve native tvOS behavior and focus/navigation semantics.
- Reuse existing model/request builders and error types before adding new ones.
- Keep naming and API shape consistent with the current source conventions.

## Validation commands

```bash
swift test
```

If tests fail, treat failures as blockers and report exact failing areas instead of bypassing them.

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
