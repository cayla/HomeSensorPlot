import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Display") {
                Picker("Temperature", selection: Binding(
                    get: { appState.settings.temperatureUnit },
                    set: { unit in
                        appState.settings.temperatureUnit = unit
                        Task { await appState.reloadCategoryChart() }
                    }
                )) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }

                Toggle("Outdoor weather on Temperature chart", isOn: Binding(
                    get: { appState.settings.showOutdoorWeather },
                    set: { enabled in
                        appState.settings.showOutdoorWeather = enabled
                        Task { await appState.reloadCategoryChart() }
                    }
                ))
                Text("Uses Open-Meteo (free, no key) and your Mac’s location for local outdoor °. Stored HomeKit values stay in Celsius for Prometheus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Collection") {
                Picker("Data source", selection: Binding(
                    get: { appState.settings.useMockData },
                    set: { useMock in
                        if useMock {
                            appState.enableMockDataAndReseed()
                        } else {
                            appState.useLiveHomeKit()
                        }
                    }
                )) {
                    Text("Live HomeKit").tag(false)
                    Text("Mock sensors").tag(true)
                }

                Toggle("Collect unknown HomeKit characteristics", isOn: Binding(
                    get: { appState.settings.collectUnknownCharacteristics },
                    set: { enabled in
                        appState.settings.collectUnknownCharacteristics = enabled
                        Task {
                            await appState.collector.forceCollectOnce()
                            await appState.refreshUI()
                        }
                    }
                ))
                Text("Off by default. When on, HomeSensorPlot also records numeric/bool HAP chars as homekit_auto_* (cameras, locks, vendor junk). Charts still only show known categories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Status", value: appState.status.shortLabel)

                if !appState.settings.useMockData {
                    LabeledContent("HomeKit auth", value: appState.homeKit.authorizationLabel)
                    LabeledContent("Homes / accessories") {
                        Text("\(appState.homeKit.homeCount) / \(appState.homeKit.accessoryCount)")
                    }
                    LabeledContent("Sensor candidates", value: "\(appState.homeKit.lastCandidateCount)")
                }

                Stepper(
                    value: Binding(
                        get: { appState.settings.scrapeIntervalSeconds },
                        set: { appState.settings.scrapeIntervalSeconds = max(15, $0) }
                    ),
                    in: 15...600,
                    step: 15
                ) {
                    Text("Scrape backstop: \(appState.settings.scrapeIntervalSeconds)s")
                }

                Stepper(
                    value: Binding(
                        get: { appState.settings.retentionDays },
                        set: { appState.settings.retentionDays = max(1, $0) }
                    ),
                    in: 1...365,
                    step: 1
                ) {
                    Text("Retention: \(appState.settings.retentionDays) days")
                }

                Button("Collect Now") {
                    Task {
                        await appState.collector.forceCollectOnce()
                        await appState.refreshUI()
                    }
                }
            }

            Section("Prometheus exporter") {
                Toggle("Enable localhost exporter", isOn: Binding(
                    get: { appState.settings.exporterEnabled },
                    set: { appState.setExporterEnabled($0) }
                ))
                Text("Off by default. When on, exposes gauges at 127.0.0.1 for Prometheus scrapes (sandboxed). Leave off unless you use /metrics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.settings.exporterEnabled {
                    Stepper(
                        value: Binding(
                            get: { appState.settings.exporterPort },
                            set: { appState.settings.exporterPort = max(1, min($0, 65535)) }
                        ),
                        in: 1024...65535,
                        step: 1
                    ) {
                        // Force String so SwiftUI doesn’t locale-group the port (9,105).
                        Text(verbatim: "Port: \(NumberFormatting.port(appState.settings.exporterPort))")
                    }

                    LabeledContent("Scrape URL") {
                        Text(verbatim: "http://\(appState.exporterAddress)/metrics")
                            .textSelection(.enabled)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button("Apply Port") {
                        appState.applyExporterPort()
                    }
                }
            }

            Section("Startup") {
                Toggle("Open at Login", isOn: Binding(
                    get: { appState.openAtLogin },
                    set: { appState.toggleOpenAtLogin($0) }
                ))
                Text("HomeSensorPlot lives in the menu bar (sensor icon). Open the window from that menu when you want charts. Enable Open at Login to keep collecting after reboot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("HomeKit") {
                Text("Needs Home data access. HomeKit is unavailable to native AppKit macOS apps, so HomeSensorPlot uses Mac Catalyst. If signing blocks the HomeKit entitlement on a free Personal Team, enroll in the Apple Developer Program and re-run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }
}
