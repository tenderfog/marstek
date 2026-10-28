# Security and code review — 2026-10-28

Scope: the VenusBar production source at baseline `f333394` plus the update and
security changes prepared with this review. Expected use is one desktop app per
Mac on a trusted home LAN, with optional YASNO access and GitHub-hosted updates.
This is a code audit and a set of targeted fixes, not a security certification.

## Confirmed finding and fix

Physical commands previously checked the station model but did not pin its MAC
identity. Another station of the same model responding at the configured IP
between a reading and a command could receive a setting or factory reset.

Commands now capture the selected station's identity before asynchronous work,
then compare every known Wi-Fi/Bluetooth MAC with a fresh device response before
the write. Changed or missing identifiers block the command. At least one valid
nonplaceholder identifier is required for controls; unidentified stations remain
readable. Factory-reset confirmation also includes the station identity.

Offline tests cover matching identifiers in different canonical formats, BLE-only
identification, changed or missing Wi-Fi/BLE identifiers, placeholder values and
reset-confirmation identity changes. The API's offline compilation and self-check
passed. Physical station writes were not used to test this fix.

## Secret scan evidence

Official [Gitleaks 8.30.1](https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1)
was downloaded from its release assets. The macOS arm64 archive passed both a
locally pinned SHA-256 check and the official release checksum check:

```text
b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5
```

- Full local Git history: **5 commits scanned; 0 findings**.
- Current source snapshot: **51 files scanned; 0 findings**. The snapshot contains tracked and
  nonignored pending files, including the new security workflow and documents.
  Ignored app builds, QA captures and private local data were excluded.
- Findings and logs were redacted. No private signing key or personal cache was
  printed, uploaded or included in this report. No ignore baseline was created.
- An offline synthetic credential-pattern fixture was correctly rejected with a
  failing scan result. The fixture was outside the repository and its value was
  not printed.

The CI workflow pins the Linux x64 archive to its official SHA-256:

```text
551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
```

It scans full history with the built-in rules, ignores inline allow comments,
uses an empty ignore file and has no write permission or repository secrets.

## Reviewed protections

- UDP reads and writes use strict bounded JSON parsing, peer IP/port and request
  checks. Only explicit private IPv4 destinations are accepted. Documented reads
  can retry timeouts; physical writes are never automatically retried.
- Command parameters, firmware gates and model power bounds are validated before
  a write. Factory reset requires explicit user confirmation.
- YASNO requests use a fixed HTTPS host, reject redirects and bound response size.
  Address identifiers are validated. Cached schedules retain their age and are
  not evidence of physical mains power.
- Local data is kept outside the app bundle and repository, with private file
  permissions. Notification permission is requested only after user interaction;
  stale or repeated readings do not trigger new high-load episodes.
- Sparkle 2.10.1 and release tooling are pinned. Appcast and archive signatures
  protect update integrity; private keys are excluded from source and artifacts.

## Remaining limits

- Local UDP has no cryptographic station authentication. A hostile LAN device
  can impersonate a station; MAC matching does not solve that protocol limit.
- Current builds have no Apple Developer ID signature or notarization. A clean
  secret scan and Sparkle signature do not prove that macOS will accept a first
  installation on another Mac.
- This review did not exercise physical control commands, real notification
  delivery or a complete two-version update on a separate user's Mac. Hardware,
  UI and release validation must be recorded separately.
- Gitleaks detects known patterns; a zero-finding result is not proof that no
  secret exists. It does not assess every dependency vulnerability or replace
  future review when code, providers or release tooling change.
