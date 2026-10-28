# Screenshots

These PNGs show VenusBar's actual SwiftUI views, rendered at 2× resolution for the repository. They are documentation examples, not readings from a physical station.

| File | View |
| :--- | :--- |
| `overview.png` | English overview, daily outage intervals, battery estimate and one-hour power history. |
| `overview-uk.png` | The same overview in Ukrainian. |
| `notifications.png` | Notification settings with an example 850 W threshold. |
| `settings.png` | Main settings navigation. |
| `onboarding.png`, `onboarding-uk.png` | Connection setup with the manual IP/port fields expanded. |
| `guide.png`, `guide-uk.png` | In-app connection-guide content, in English and Ukrainian. |

All readings and history are synthetic. The address is explicitly fictional: **Demo, Example Street, 12** / **Демо, Прикладова вулиця, 12**. No saved station connection, real address, Wi-Fi name, MAC address or personal desktop appears in these images.

The capture process mounts the production views in an offscreen `NSHostingView`, injects fixtures into temporary store copies and uses a neutral dark background in place of a desktop-dependent glass backdrop. It does not connect to a station, fetch an outage schedule or send a notification. The permission state on the notification example is simulated. Times are generated for the capture day and are illustrative.

Refresh screenshots when the corresponding views change. Keep demo fixtures separate from user data and inspect the full image for private details before committing it.
