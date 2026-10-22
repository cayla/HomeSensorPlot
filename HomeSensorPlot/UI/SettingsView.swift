import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmReset = false
    @State private var exportDump = false
    @State private var dumpDocument = SupportDumpDocument(text: "")

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
                Text("Uses Open-Meteo (free, no key) and your Mac’s location for local outdoor °. Each hour is kept in this database. Open-Meteo backfills about \(WeatherService.maxHistoryDays) days. Stored HomeKit values stay in Celsius for Prometheus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.settings.showOutdoorWeather {
                    Toggle("Allow IP geolocation fallback", isOn: Binding(
                        get: { appState.settings.allowIPGeolocationFallback },
                        set: { enabled in
                            appState.settings.allowIPGeolocationFallback = enabled
                            appState.weather.configure(allowIPGeolocationFallback: enabled)
                            Task { await appState.reloadCategoryChart() }
                        }
                    ))
                    Text("Off by default. When on, if Location is denied or unavailable, HomeSensorPlot asks a third-party IP geolocation service (geojs.io) for approximate coords. Prefer enabling Location instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                        Task { await appState.collectNow() }
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
                    Task { await appState.collectNow() }
                }
                .disabled(appState.collector.isCollecting)
            }

            Section("Prometheus exporter") {
                Toggle("Enable localhost exporter", isOn: Binding(
                    get: { appState.settings.exporterEnabled },
                    set: { appState.setExporterEnabled($0) }
                ))
                Text("Off by default. When on, binds 127.0.0.1 only (loopback). If loopback bind fails, the exporter stays off — it will not listen on your LAN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.settings.exporterEnabled {
                    Stepper(
                        value: Binding(
                            get: { appState.settings.exporterPort },
                            set: { appState.setExporterPort($0) }
                        ),
                        in: 1024...65535,
                        step: 1
                    ) {
                        // Force String so SwiftUI doesn’t locale-group the port (9,105).
                        Text(verbatim: "Port: \(NumberFormatting.port(appState.settings.exporterPort))")
                    }

                    if appState.exporterAddress != "off" {
                        LabeledContent("Scrape URL") {
                            Text(verbatim: "http://\(appState.exporterAddress)/metrics")
                                .textSelection(.enabled)
                                .font(.system(.body, design: .monospaced))
                        }
                    } else {
                        Text("Not listening — see the error banner, then retry with Apply Port.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Apply Port") {
                            appState.applyExporterPort()
                        }
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

            Section("Data") {
                LabeledContent("Distribution", value: appState.store.channel.rawValue)
                LabeledContent("Database") {
                    Text(verbatim: appState.store.databaseURL.lastPathComponent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("Development, TestFlight, and App Store builds keep separate databases. A signing change no longer appends a second copy of every sensor into the same file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Export Support Dump") {
                    dumpDocument = SupportDumpDocument(text: appState.makeSupportDump())
                    exportDump = true
                }
                Text("JSON for debugging. Includes home, room, and accessory names, sensor ids, and the latest value for each sensor. Sample history stays in the database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset Collected Data", role: .destructive) {
                    confirmReset = true
                }
                .tint(.red)
                Text("Deletes every sample, outdoor hour, and sensor record in this database. Cannot be undone. Units, exporter, and login settings stay.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Section("HomeKit") {
                Text("Needs Home data access. HomeKit is unavailable to native AppKit macOS apps, so HomeSensorPlot uses Mac Catalyst. If signing blocks the HomeKit entitlement on a free Personal Team, enroll in the Apple Developer Program and re-run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "Delete all collected data?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Delete Collected Data", role: .destructive) {
                appState.resetCollectedData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Charts, inventory, and the Prometheus export lose this history. The next scrape starts over.")
        }
        .fileExporter(
            isPresented: $exportDump,
            document: dumpDocument,
            contentType: .json,
            defaultFilename: "HomeSensorPlot-support"
        ) { result in
            if case .failure(let error) = result {
                appState.lastRefreshError = error.localizedDescription
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }
}

struct SupportDumpDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
