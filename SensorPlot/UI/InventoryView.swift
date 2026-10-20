import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: String = ""

    /// Fixed columns sized so Latest fits values like `5,047.13`; Accessory takes the rest.
    private enum ColumnWidth {
        static let location: CGFloat = 140
        static let metric: CGFloat = 170
        static let latest: CGFloat = 88
        static let toggle: CGFloat = 60
    }

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

            // SwiftUI `Table` on Mac Catalyst draws column headers on top of the first row.
            // Use an explicit header + List instead.
            VStack(spacing: 0) {
                columnHeader
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .background(.background)

                Divider()

                List(filtered) { sensor in
                    sensorRow(sensor)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                        .listRowSeparator(.visible)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var columnHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Accessory")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Location")
                .frame(width: ColumnWidth.location, alignment: .leading)
            Text("Metric")
                .frame(width: ColumnWidth.metric, alignment: .leading)
            Text("Latest")
                .frame(width: ColumnWidth.latest, alignment: .trailing)
            Text("Hidden")
                .frame(width: ColumnWidth.toggle, alignment: .center)
            Text("Blocked")
                .frame(width: ColumnWidth.toggle, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func sensorRow(_ sensor: SensorRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sensor.accessoryName)
                        .lineLimit(2)
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
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)

            Text(sensor.locationLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: ColumnWidth.location, alignment: .leading)

            Text(sensor.metricName)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .frame(width: ColumnWidth.metric, alignment: .leading)

            Group {
                if let value = sensor.lastValue {
                    Text(NumberFormatting.measurement(value))
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: ColumnWidth.latest, alignment: .trailing)

            Toggle(
                "Hidden",
                isOn: Binding(
                    get: { sensor.isHidden },
                    set: { appState.setHidden(sensorID: sensor.id, hidden: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .frame(width: ColumnWidth.toggle)

            Toggle(
                "Blocked",
                isOn: Binding(
                    get: { sensor.isBlocked },
                    set: { appState.setBlocked(sensorID: sensor.id, blocked: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .frame(width: ColumnWidth.toggle)
        }
    }
}
