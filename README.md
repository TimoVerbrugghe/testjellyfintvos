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

## Launch in tvOS Simulator

The package now includes a runnable `JellyfinTVOSDemoApp` tvOS target plus a helper script:

```bash
chmod +x scripts/launch-tvos-simulator.sh
./scripts/launch-tvos-simulator.sh
```

You can also pass a specific simulator UDID as the first argument.

The launch script includes a development ATS override in the generated app bundle so local `http://` Jellyfin servers can be tested from Simulator.

## Spec Kit workflow

This repository is initialized with [GitHub Spec Kit](https://github.com/github/spec-kit) for spec-driven development.

- Spec Kit state/config: `.specify/`
- Constitution: `.specify/memory/constitution.md`
- Specs: `specs/`
- Copilot slash command prompts: `.github/prompts/speckit.*.prompt.md`

If `specify` is not installed yet:

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.11.3
```

Common workflow:

```bash
/speckit.constitution
/speckit.specify
/speckit.plan
/speckit.tasks
/speckit.implement
```

## AI collaboration

This repository is configured for AI-assisted development with project-specific guidance in:

- `.github/copilot-instructions.md` for GitHub Copilot and Copilot Coding Agent context
- `AGENTS.md` for general AI coding agents (task workflow, coding boundaries, and validation expectations)

When working with an AI agent, start by sharing the task goal and ask it to follow the repository instructions before making edits.