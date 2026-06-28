# AI agent guide

## Mission

Extend and maintain this package as native tvOS Jellyfin building blocks with AVPlayer-first playback behavior.

## Non-negotiables

1. Keep playback native (AVPlayer/AVKit).
2. Avoid unrelated refactors.
3. Preserve API behavior unless the task explicitly changes it.
4. Surface errors explicitly; do not add silent fallbacks.

## Implementation workflow

1. Read relevant files in `Sources/JellyfinTVOS` and matching tests.
2. Apply minimal, complete changes for the requested behavior.
3. Update/add tests in `Tests/JellyfinTVOSTests` for behavior changes.
4. Run package tests with `swift test`.

## Task handoff format

When finishing a task, include:

- what changed,
- why it changed,
- any known limitations or follow-ups.
