# Changelog

Notable changes to VenusBar, starting with version **0.1**. Build numbers increase within a version. Entries below describe development builds; a downloadable release exists only when it appears in [GitHub Releases](https://github.com/tenderfog/marstek/releases).

## 0.1 · Build 4 — 2026-10-28

### Added

- In-app update checks and installation through Sparkle, beginning with build 4.
- An App updates page with a manual check and an automatic-check preference.
- A publishing workflow for signed update archives and a signed update feed.
- A visual repository introduction, English and Ukrainian guides, and screenshots using fictional demo data.
- An in-app connection guide explaining where to find the IP address and Local API port, with links to the official station manuals.

### Changed

- Version and build metadata now come from a shared release configuration.
- Release instructions explain the first manual installation, preserved preferences and the separate Apple signing requirement.
- Manual connection expands from a full-width row, brings the IP and port fields into view, and offers a clear retry path after discovery fails.

### Fixed

- Control commands recheck the selected station's known Wi-Fi/Bluetooth MAC identity before sending a write. Missing or changed identity blocks the command. This is covered by offline fixtures; no physical control command was used to validate it.

## 0.1 · Build 3 — 2026-10-27

### Fixed

- Accept the documented Venus A identity and firmware aliases while rejecting conflicting identity fields.
- Give identity and discovery responses more time and space requests relative to the latest matching reply.
- Preserve useful errors from discovery responses instead of reporting every failure as “no station found”.

### Changed

- Setup now asks for the exact port shown in MARSTEK's Local API settings.
- Connection guidance explains Local Network permission on recent macOS versions, including manual IP connections.

Source: [`f333394`](https://github.com/tenderfog/marstek/commit/f333394). Venus A still needs testing on real hardware.

## 0.1 · Build 2 — 2026-10-27

### Added

- App icon, also displayed in the About page.
- Optional local high-consumption notifications with an adjustable watt threshold, rearming margin and a five-minute repeat limit.

### Changed

- Adapted translucent outage cards with separate time intervals.
- Power history holds the last reading between responses, hides zero-value coloured lines and scrolls longer periods horizontally.

Source: [`793e332`](https://github.com/tenderfog/marstek/commit/793e332).

## 0.1 · Build 1 — 2026-10-27

### Added

- Native menu bar status, a hover preview and the main energy dashboard.
- Automatic station discovery and manual local IP/port setup.
- Charge, discharge, remaining energy, temperature and output-load indicators.
- Local reading cache, retry handling and a visible last-update time.
- YASNO street/building lookup, daily outage intervals and optional address setup.
- Runtime and charging estimates when sufficient battery data is available.
- Local power history for one, three, five or 24 hours.
- Station-control forms with model and firmware checks.
- Ukrainian, English and playful Surzhyk interfaces, language-first onboarding and optional launch at login.
- About page with version, developer, GitHub and email links, and “Made in Ukraine”.
- Universal app packaging and offline self-checks.

Sources: [`e39c4e7`](https://github.com/tenderfog/marstek/commit/e39c4e7), [`16000fd`](https://github.com/tenderfog/marstek/commit/16000fd).

The initial package used `0.1.0`; the visible version was then standardised to `0.1`. Local API reading was verified on Venus E 3.0 firmware 150. Builds are ad hoc signed and are not Apple notarized.
