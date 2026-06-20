# JellyfinTVOS

Native tvOS building blocks for a Jellyfin client that uses AVPlayer for playback and can execute live Jellyfin auth/catalog requests.

## Included

- Jellyfin sign-in request builders for server discovery validation, username/password auth, and Quick Connect
- A live networking service for validating servers, authenticating sessions, Quick Connect polling, and loading libraries/home catalog data
- Jellyfin catalog request builders for loading libraries, series seasons, and season episodes
- A playback profile that advertises Dolby Vision profile 5 and 8 support
- Subtitle selection logic for SDH, ASS, and Subgen subtitle streams
- Direct play vs. transcoding request generation for Jellyfin playback
- tvOS-only SwiftUI browser and playback views that wrap native `AVPlayer`

## Validation

```bash
swift test
```