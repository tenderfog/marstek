# Building and releasing

Pushes, pull requests, and **Actions → Build VenusBar → Run workflow** build a
universal macOS app and run its offline self-checks. The `VenusBar-universal`
artifact contains `VenusBar.zip` and `SHA256SUMS.txt` and is retained for 30 days.
Downloading workflow artifacts requires a GitHub login.

To publish an alpha, push a new version tag such as `v0.1.0-alpha.1` on the commit
you intend to release. After the build passes, a separate job publishes a GitHub
**prerelease** with the ZIP and checksum. Branch pushes, pull requests, and manual
workflow runs never publish a release. Existing releases are not overwritten;
use a new tag for a new build.

On macOS, verify a download with `shasum -a 256 -c SHA256SUMS.txt` from the folder
containing both files. Checksums detect a changed download; they do not replace
Apple signing or notarization. Current builds use ad hoc signing and may require
approval in macOS Privacy & Security. No station data, connection settings, or
credentials are included in the app.

The build job has read-only repository access. Only the tag-only publication job
has `contents: write`, using GitHub's temporary `GITHUB_TOKEN`; no personal token
or Apple signing secret is needed. Official actions are pinned to verified release
commits: [checkout v7.0.1](https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1)
and [upload-artifact v7.0.2](https://github.com/actions/upload-artifact/commit/cf430e030ddbb5b0abf93d22962f4752f3646cd9).
Review and update these pins when adopting newer releases.
