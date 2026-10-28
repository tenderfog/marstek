# Screenshots

These PNGs show VenusBar's actual SwiftUI views, rendered at 2× resolution for the repository. They are documentation examples, not readings from a physical station.

| File | View |
| :--- | :--- |
| `language.png` | Initial bilingual language selection before the station is connected. |
| `station.png`, `station-uk.png` | First onboarding step: open the station in MARSTEK. |
| `local-api.png`, `local-api-uk.png` | Second onboarding step: enable Local API and find the port. |
| `discovery.png`, `discovery-uk.png` | Automatic station discovery before a network request is made. |
| `overview.png` | English overview, daily outage intervals, battery estimate and one-hour power history. |
| `overview-uk.png` | The same overview in Ukrainian. |
| `notifications.png`, `notifications-uk.png` | Notification settings with an example 850 W threshold and new-version preference. |
| `settings.png`, `settings-uk.png` | Main settings grid with six sections and an About footer. |
| `onboarding.png`, `onboarding-uk.png` | Connection setup with the manual IP/port fields expanded. |
| `guide.png`, `guide-uk.png` | In-app connection-guide content, in English and Ukrainian. |
| `controls.png`, `controls-uk.png` | Station controls with a synthetic, valid device identity. No command is sent. |
| `updates.png`, `updates-uk.png` | App-update settings with a simulated available release. |
| `overview-update.png`, `overview-update-uk.png` | Main-panel update prompt using an illustrative future build 6. |

All readings and history are synthetic. The address is explicitly fictional: **Demo, Example Street, 12** / **Демо, Прикладова вулиця, 12**. No saved station connection, real address, Wi-Fi name, MAC address or personal desktop appears in these images.

The capture process mounts the production views in an offscreen `NSHostingView`, injects fixtures into temporary store copies and uses a neutral dark background in place of a desktop-dependent glass backdrop. It does not connect to a station, fetch an outage schedule or send a notification. The permission state on the notification example is simulated. The updater is replaced only in the capture harness by a no-network fixture; build 6 is an illustrative state, not an announcement of a published release. Times are generated for the capture day and are illustrative.

Refresh screenshots when the corresponding views change. Keep demo fixtures separate from user data and inspect the full image for private details before committing it.
