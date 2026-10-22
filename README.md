# HomeSensorPlot

Always-on Mac app (Mac Catalyst) that discovers HomeKit sensors, stores readings locally, charts them with time ranges, and optionally exposes a localhost Prometheus exporter.

## Why Mac Catalyst?

Apple marks the HomeKit framework `API_UNAVAILABLE` for **native** macOS AppKit apps. HomeSensorPlot is a **Mac Catalyst** host (HomeKit + charts) plus a small native **`macOSBridge`** plugin that owns the menu bar status item — same split [ItsyHome](https://github.com/nickustinov/itsyhome-macos) uses. The window stays hidden until you choose **Open HomeSensorPlot** from the menu bar. Enable Open at Login to keep collecting after reboot.

## Features

- Auto-selects HomeKit characteristics with sensor-like data (temp, humidity, light, contact, motion, air quality, battery, plus numeric/bool fallbacks)
- Inventory controls: **hide** (still collect, omit from charts; still appears in `/metrics` if the exporter is on) and **block** (no collect / no export)
- Background collection via HomeKit notifications + a slow scrape backstop
- Built-in Swift Charts with 1h / 24h / 7d / 30d / custom time boxing
- Optional outdoor temperature overlay (Open-Meteo) using Location; optional IP geolocation fallback is **off by default**
- Optional Prometheus scrape endpoint on loopback only (opt-in in Settings; default port `9105`)
- Mock sensor mode for UI/exporter development without HomeKit access

## Requirements

- macOS 14+
- Xcode 27.1
- Home data access permission
- HomeKit entitlement (may require [Apple Developer Program](https://developer.apple.com/programs/) if Personal Team cannot enable it)

## Build & run

```bash
cd /path/to/HomeSensorPlot
xcodegen generate
open HomeSensorPlot.xcodeproj
```

In Xcode:

1. Select the **HomeSensorPlot** scheme destination **My Mac (Mac Catalyst)**
2. Signing & Capabilities → choose your Team
3. Confirm **HomeKit** capability / entitlement is present
4. Run (⌘R)

First launch should prompt for HomeKit / Home data access.

If HomeKit signing fails on a free account: enroll in the paid Developer Program, re-select the team, then run again. Meanwhile, Settings → **Mock sensors** seeds demo data so charts and `/metrics` still work.

## Tests

```bash
xcodegen generate
xcodebuild -scheme HomeSensorPlot -destination 'platform=macOS,variant=Mac Catalyst' test
```

GitHub Actions runs the HomeSensorPlot scheme tests on pull requests with Xcode 27.1.

## Prometheus scrape

Enable **Settings → Enable localhost exporter** (off by default). The listener binds **loopback only**; if that bind fails, the exporter stays off (no LAN fallback).

```bash
curl -s http://127.0.0.1:9105/metrics
```

Example scrape config:

```yaml
scrape_configs:
  - job_name: homesensorplot
    scrape_interval: 30s
    static_configs:
      - targets: ["127.0.0.1:9105"]
```

`/metrics` includes hidden sensors (still collected) but omits blocked ones. Labels include home/room/accessory names — keep the exporter off on shared networks.

## Outdoor weather

Temperature charts can overlay Open-Meteo outdoor ° (uses Location). Free Open-Meteo history is capped at **7 days**. If Location fails, Settings → **Allow IP geolocation fallback** (off by default) may call geojs.io for approximate coordinates.

## Data location

SQLite database (WAL), one file per signing channel:

`~/Library/Containers/com.cayla.HomeSensorPlot/Data/Library/Application Support/HomeSensorPlot/homesensorplot-<channel>.sqlite`

`<channel>` is `development`, `testflight`, `app-store`, `developer-id`, or `unknown`. A development build and a TestFlight build do not share rows. The first launch of a channel copies the old shared `homesensorplot.sqlite` into that channel's file once, if it is still there, and leaves the original in place.

(or Application Support directly if the container path differs on your system)

Retention defaults to 60 days (configurable in Settings).

## Open at Login

Toggle in Settings. Uses `SMAppService` for the main app login item.

## Regenerating the Xcode project

Sources are listed via [`project.yml`](project.yml). After adding/removing files:

```bash
xcodegen generate
```

## Notes

- Exporter is opt-in and **fail-closed** on loopback bind (App Sandbox with `network.server` / `network.client` for TestFlight / App Store Connect)
- HomeKit blocks **Developer ID / Direct Distribution**; use **TestFlight Internal** or the **Mac App Store** (including unlisted) to install on another Mac
- SQLite lives in the app container’s Application Support
- After install, look for the **sensor** icon in the menu bar (not the Dock)
- Export compliance: uses only standard HTTPS / OS crypto (`ITSAppUsesNonExemptEncryption` = NO)
