import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: String = ""

    private var filtered: [SensorRecord] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appState.sensors }
        return appState.sensors.filter {
            $0.displayName.lowercased().contains(q)
                || $0.locationLabel.lowercased().contains(q)
                || $0.metricName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Filter sensors", text: $filter)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hide keeps collecting but omits charts. Block stops collection and export.")
                Text("HomePod temperature and humidity won’t show up — Apple doesn’t expose those readings to third‑party apps.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Table(filtered) {
                TableColumn("Accessory") { sensor in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(sensor.accessoryName)
                            if sensor.autoDiscovered {
                                Text("auto")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.blue.opacity(0.15), in: Capsule())
                            }
                        }
                        Text(sensor.friendlyCharacteristic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 160, ideal: 200)

                TableColumn("Location") { sensor in
                    Text(sensor.locationLabel)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Metric") { sensor in
                    Text(sensor.metricName)
                        .font(.system(.caption, design: .monospaced))
                }
                .width(min: 160, ideal: 220)

                TableColumn("Latest") { sensor in
                    if let value = sensor.lastValue {
                        Text(NumberFormatting.measurement(value))
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(70)

                TableColumn("Hidden") { sensor in
                    Toggle(
                        "Hidden",
                        isOn: Binding(
                            get: { sensor.isHidden },
                            set: { appState.setHidden(sensorID: sensor.id, hidden: $0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .width(70)

                TableColumn("Blocked") { sensor in
                    Toggle(
                        "Blocked",
                        isOn: Binding(
                            get: { sensor.isBlocked },
                            set: { appState.setBlocked(sensorID: sensor.id, blocked: $0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .width(70)
            }
        }
    }
}
