# SensorPlot

Always-on Mac app (Mac Catalyst) that discovers HomeKit sensors, stores readings locally, charts them with time ranges, and exposes a localhost Prometheus exporter.

## Why Mac Catalyst?

Apple marks the HomeKit framework `API_UNAVAILABLE` for **native** macOS AppKit apps. HomeKit on the Mac is supported via **Mac Catalyst** (and iOS). SensorPlot therefore builds as a Catalyst app so live HomeKit collection works. Use Open at Login if you want collection after reboot.

## Features

- Auto-selects HomeKit characteristics with sensor-like data (temp, humidity, light, contact, motion, air quality, battery, plus numeric/bool fallbacks)
- Inventory controls: **hide** (still collect, omit from charts) and **block** (no collect / no export)
- Background collection via HomeKit notifications + a slow scrape backstop
- Built-in Swift Charts with 1h / 24h / 7d / 30d / custom time boxing
- Prometheus scrape endpoint on `127.0.0.1` (default port `9105`)
- Mock sensor mode for UI/exporter development without HomeKit access

## Requirements

- macOS 14+
- Xcode 16+
- Home data access permission
- HomeKit entitlement (may require [Apple Developer Program](https://developer.apple.com/programs/) if Personal Team cannot enable it)

## Build & run

```bash
cd /path/to/sensorplot
xcodegen generate
open SensorPlot.xcodeproj
```

In Xcode:

1. Select the **SensorPlot** scheme destination **My Mac (Mac Catalyst)**
2. Signing & Capabilities → choose your Team
3. Confirm **HomeKit** capability / entitlement is present
4. Run (⌘R)

First launch should prompt for HomeKit / Home data access.

If HomeKit signing fails on a free account: enroll in the paid Developer Program, re-select the team, then run again. Meanwhile, Settings → **Mock sensors** seeds demo data so charts and `/metrics` still work.

## Prometheus scrape

```bash
curl -s http://127.0.0.1:9105/metrics
```

Example scrape config:

```yaml
scrape_configs:
  - job_name: sensorplot
    scrape_interval: 30s
    static_configs:
      - targets: ["127.0.0.1:9105"]
```

## Data location

SQLite database (WAL):

`~/Library/Containers/com.cayla.SensorPlot/Data/Library/Application Support/SensorPlot/sensorplot.sqlite`

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

- Exporter binds to **localhost only** (App Sandbox with `network.server` / `network.client` for TestFlight / App Store Connect)
- HomeKit blocks **Developer ID / Direct Distribution**; use **TestFlight Internal** (or the Mac App Store) to install on another Mac
- SQLite lives in the app container’s Application Support
