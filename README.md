# JellyfinTVOS

Native tvOS building blocks for a Jellyfin client that uses AVPlayer for playback.

## Included

- Jellyfin request/authentication helpers for server, library, and playback endpoints
- A playback profile that advertises Dolby Vision profile 5 and 8 support
- Subtitle selection logic for SDH, ASS, and Subgen subtitle streams
- Direct play vs. transcoding request generation for Jellyfin playback
- A tvOS-only `JellyfinPlaybackView` that wraps native `AVPlayer`

## Validation

```bash
swift test
```