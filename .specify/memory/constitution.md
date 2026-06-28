# JellyfinTVOS Constitution

## Core Principles

### I. Native Playback First
All playback experiences MUST remain AVPlayer/AVKit driven. Features are implemented through native tvOS extension points and player customization APIs, never through a custom playback engine.

### II. Apple tvOS Design Alignment
UI and interaction changes MUST align with Apple tvOS design guidance, including focus behavior, motion, readability, and system material usage (including liquid-glass style where appropriate).

### III. Media Capability Fidelity
Playback and stream decisioning MUST explicitly preserve support for Dolby Vision profile 5, 7, and 8 where source + device capability allow. Subtitle handling MUST support user-facing formatting/style controls where feasible through native pathways and supported stream metadata.

### IV. Jellyfin Connectivity Reliability
The application MUST support robust Jellyfin server autodiscovery and resilient server/session flows (discovery, validation, sign-in, quick connect, catalog loading), with explicit error paths and no silent failures.

### V. Spec-Driven Change Management
Behavioral work MUST start from a spec in `specs/`, proceed through plan/tasks, and maintain tests that cover capability changes (request shape, selection logic, and app flow transitions).

## Technical and Product Constraints

- Language/runtime: Swift 6 package, tvOS-first with native Apple frameworks.
- Networking: request/response contracts MUST remain explicit and testable.
- UX consistency: transport controls, info panels, and navigation states MUST preserve native tvOS expectations.
- Backward behavior: unrelated API behavior and existing catalog/auth flows MUST remain stable unless a spec explicitly changes them.

## Workflow and Quality Gates

1. Define or update the relevant spec before implementation (`/speckit.specify` or manual spec update).
2. Create/refresh plan and tasks before broad implementation (`/speckit.plan`, `/speckit.tasks`).
3. Keep tests synchronized with behavior changes in `Tests/JellyfinTVOSTests`.
4. Validate with `swift test` before completion.

## Governance

This constitution governs repo-level product and implementation decisions. If a proposed change conflicts with a principle, the spec must explicitly document the exception, rationale, impact, and rollback path. Amendments require a pull request that updates this file and references impacted specs.

**Version**: 1.0.0 | **Ratified**: 2026-06-21 | **Last Amended**: 2026-06-21
