# Security

VenusBar is an experimental macOS app. Its code and release checks reduce specific
risks; they are not a security certification.

## Report a vulnerability privately

Email **tenderfog.site@gmail.com** with the affected version, what happened and
steps to reproduce. Do not open a public issue containing passwords, keys,
station MAC addresses, private IP addresses, home addresses or an unredacted
diagnostic archive. Use synthetic values in examples.

If a credential was exposed, revoke or rotate it through its provider. Deleting
a file or making a new commit does not remove a secret from Git history.

## Trust boundaries

- The MARSTEK Local API uses unauthenticated UDP. Use it only on a trusted private
  network and do not forward its port to the internet. VenusBar checks packet
  size, JSON shape, source IP/port and request identifiers. Physical commands also
  require a matching previously observed Wi-Fi or Bluetooth MAC identifier.
  MAC matching helps prevent commands reaching a replacement station; it does
  not protect against a malicious device impersonating that identity.
- Station connection details, readings, energy history and outage address are
  stored separately from the app under the user's Application Support directory.
  They must not be included in Git, screenshots, build archives or public reports.
  YASNO receives the address search needed for its public schedule service.
- Sparkle **2.10.1** is pinned, and its downloaded distribution is checked against
  the SHA-256 in `Config/Sparkle.json`. Updates require a signed appcast and an
  EdDSA-signed archive verified before extraction. Only the public update key is
  committed. The developer's private key stays in macOS Keychain. CI verifies
  locally signed release manifests with the public key; it receives no private
  signing key. Never commit or log private keys.
- Current alpha builds are signed ad hoc, **without Apple Developer ID signing
  or notarization**. Sparkle signatures do not replace Apple's first-install
  checks. Do not disable Gatekeeper globally to install VenusBar.

## Repository checks

The Secret scan workflow uses checksum-pinned Gitleaks 8.30.1 to scan complete
Git history on pushes and pull requests. It has read-only repository permission,
uses no repository secrets, redacts findings and does not accept inline ignore
comments or a repository-wide allowlist. A clean scan does not prove that every
possible secret or vulnerability has been detected.

See [the dated code review](docs/SECURITY-REVIEW.md) and
[release instructions](docs/RELEASING.md) for checks and remaining limits.
