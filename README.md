<p align="center">
  <img src="Assets/AppIcon/VenusBar-1024.png" width="96" alt="VenusBar app icon">
</p>

<h1 align="center">VenusBar</h1>

<p align="center">
  <strong>Your MARSTEK battery, a glance away.</strong><br>
  A native macOS menu bar app for charge, power and outage planning.
</p>

<p align="center">
  <a href="https://github.com/tenderfog/marstek/actions/workflows/build.yml"><img src="https://github.com/tenderfog/marstek/actions/workflows/build.yml/badge.svg" alt="Build status"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-24262D?logo=apple&amp;logoColor=white" alt="macOS 13 or newer">
  <img src="https://img.shields.io/badge/Apple_Silicon_%2B_Intel-Universal-24262D" alt="Universal build for Apple Silicon and Intel">
  <img src="https://img.shields.io/badge/version-0.1_alpha-EC8759" alt="Version 0.1 alpha">
</p>

<p align="center">
  <a href="https://github.com/tenderfog/marstek/releases"><strong>Download</strong></a> ·
  <a href="CHANGELOG.md">What's new</a> ·
  <a href="#get-started">Get started</a> ·
  <a href="https://github.com/tenderfog/marstek/issues">Report an issue</a> ·
  <a href="docs/README.uk.md">Українська</a>
</p>

<p align="center">
  <img src="docs/images/overview.png" width="520" alt="VenusBar overview showing 76% battery, 284 W discharge, today's outage intervals and power history">
  <br><sub>Actual app views with sample readings and a fictional address. See <a href="docs/images/README.md">screenshot details</a>.</sub>
</p>

VenusBar keeps your battery in the menu bar. Hover for a quick look; click for the full view. It talks directly to the station over your local network, without asking for your MARSTEK account credentials.

**Early alpha.** Reading has been tested on a physical **Venus E 3.0, firmware 150**. Venus A support is implemented but still needs hardware testing. Current builds are **not Apple notarized**, so macOS may block the first launch. [Installation notes →](docs/FIRST-RUN.txt)

## A clear view of your energy

| | What you can do |
| :--- | :--- |
| **At a glance** | See battery percentage in the menu bar and a compact hover panel with active power readings, temperature and an optional daily outage timeline. |
| **Charge & discharge** | Separate power readings, remaining energy in kWh, battery temperature and load relative to a known output rating. Green means charging; red means discharging. |
| **Power history** | Explore 1 hour, 3 hours, 5 hours or a full day. Longer periods scroll horizontally. Between responses, the chart holds the last reading and shows its original time. |
| **Outage schedules** | Find your street and building through YASNO, then see today's intervals and the current time. Skip this entirely if you do not need it. |
| **Battery estimates** | Estimate time to full charge or whether the battery should last until scheduled power restoration, when sufficient battery data is available. |
| **High-load alerts** | Choose a threshold in watts and get a local notification when consumption rises above it. Notifications are off until you enable them and allow them in macOS. |
| **Station controls** | Access the model's supported API commands for modes, charging schedules and settings. Physical execution still needs hardware validation. |
| **Made for macOS** | SwiftUI and AppKit, dark translucent surfaces, optional launch at login, and Ukrainian, English or the playful “Surzhyk” interface. |

<p align="center">
  <img src="docs/images/notifications.png" width="460" alt="Notification settings with a high-consumption alert threshold set to 850 W">
  <br><sub>Set the consumption threshold that matters to you. This example uses simulated notification permission.</sub>
</p>

## Get started

1. Download **VenusBar.zip** from [Releases](https://github.com/tenderfog/marstek/releases), unzip it and move **VenusBar.app** to **Applications**.
2. Open it and choose your language. VenusBar lives in the menu bar, without a Dock icon.
3. Connect your Mac and station to the same local network. In the official MARSTEK app, enable **Local API** and check **Ports**. Use that exact UDP port; `30000` is only the default.
4. Allow Local Network access if macOS asks, then choose **Find automatically**. You can also enter the station's IP address and port manually.
5. Add an address for outage schedules, or choose **Set up later**. The schedule stays hidden until configured.

If discovery fails, check the port and **System Settings → Privacy & Security → Local Network** on macOS 15 or newer. Manual IP entry needs the same network permission. Guest Wi-Fi or client isolation can also prevent the Mac and station from communicating.

<details>
  <summary>Preview setup and the connection guide</summary>
  <p align="center">
    <img src="docs/images/onboarding.png" width="460" alt="Setup with manual IP address and Local API port fields expanded">
    <br><sub>Automatic discovery or a manual connection, with the same port as the station.</sub>
  </p>
  <p align="center">
    <img src="docs/images/guide.png" width="420" alt="Built-in guide explaining where to find the station IP address and Local API port">
    <br><sub>The in-app guide links to the official Venus E3 and Venus A manuals.</sub>
  </p>
</details>

### Updating

Starting with **build 4**, VenusBar uses [Sparkle](https://sparkle-project.org/) for in-app updates. Open **Settings → App updates → Check for Updates**, or enable automatic checks. Review the changes, then choose whether to download, install and restart. Your station connection, address, history and preferences are kept.

Older builds need **one manual installation** of a build with the updater. Public updates are distributed through GitHub Releases; downloading them does not require a GitHub account. The updater's signatures do not replace Apple notarization or remove the first-launch restriction.

For maintainers: [how releases and signed updates are published →](docs/RELEASING.md)

## Compatibility

| | Current status |
| :--- | :--- |
| **macOS** | 13 or newer; universal build for Apple Silicon and Intel. |
| **Venus E 3.0** | Local API reading verified on firmware 150. Other firmware and wiring arrangements need testing. |
| **Venus A** | Protocol support implemented, including solar inputs when returned by the station. Real-device testing is still needed. |
| **System settings** | Require a recognized E3/A and firmware 150 or newer. Controls also require a matching known Wi-Fi/Bluetooth station identifier. An accepted API command does not confirm its physical execution. |
| **Outage schedules** | Regions and operators returned by YASNO's public service. Availability depends on that service. |

### What the readings mean

- **The outage schedule is a plan.** It is separate from station telemetry and cannot confirm that mains electricity is physically present. Zero watts alone cannot confirm it either.
- **Estimates depend on the load.** Runtime uses usable battery energy and recent battery power or an energy trend. A local reserve, initially 20%, affects the estimate; it does not change the station's discharge-depth setting.
- **Last known values remain visible.** A failed request does not erase the dashboard. Source timestamps and stale states distinguish saved readings from fresh responses.
- **LEDs are an interpretation.** The API does not expose each physical indicator directly. The drawing uses the available readings and conservative estimates.
- **Temperature colours are advisory.** The 45 / 50 / 55°C levels are VenusBar attention markers, not verified BMS shutdown thresholds. Internal battery temperature is not ambient temperature.

## Your data

Station settings, the last reading, local power history and the selected outage address live in:

```text
~/Library/Application Support/VenusBar/
```

They are not included in the app archive. Station requests stay on the local network. If you enable outage schedules, address lookup goes to YASNO. Update checks and downloads use GitHub and do not upload your station readings or saved address.

## Build from source

Use macOS 13+ with Xcode Command Line Tools and a compatible Swift/macOS SDK:

```sh
git clone https://github.com/tenderfog/marstek.git
cd marstek
zsh scripts/build_venusbar.sh
```

The script fetches a pinned, checksum-verified Sparkle release, builds the app, signs the local build ad hoc, runs offline checks and creates:

```text
build/VenusBar.app
build/VenusBar.zip
```

Run the checks again with:

```sh
build/VenusBar.app/Contents/MacOS/VenusBar --self-check
```

These checks cover protocol parsing, command limits, timestamps and application logic. They do not search your network or send commands to a station. Python may be used during packaging for a toolchain workaround; the finished app needs no Python runtime.

## Help make it better

Found a bug? [Open an issue](https://github.com/tenderfog/marstek/issues) with your macOS version, VenusBar build, station model, firmware and the exact error. Remove addresses, IP/MAC addresses, Wi-Fi names and other private details from screenshots or logs before posting.

Small fixes, clearer translations and results from Venus A testing are welcome. See [the changelog](CHANGELOG.md) for development history and [release instructions](docs/RELEASING.md) for the publishing process.

---

**Зроблено в Україні · Made in Ukraine**

Developed by [tenderfog](https://github.com/tenderfog) · [tenderfog.site@gmail.com](mailto:tenderfog.site@gmail.com)

VenusBar is an independent, unofficial project and is not affiliated with MARSTEK. The app icon uses the manufacturer's mark; [source and attribution](Assets/AppIcon/SOURCE.md). Third-party components and their licences are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
