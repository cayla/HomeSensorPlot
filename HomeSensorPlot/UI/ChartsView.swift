import Charts
import SwiftUI

struct ChartsView: View {
    @EnvironmentObject private var appState: AppState

    private var presentCategories: [SensorCategory] {
        SensorCategory.categoriesPresent(in: appState.sensors)
    }

    var body: some View {
        Group {
            if let category = appState.selectedCategory {
                CategoryDetailView(category: category)
            } else {
                categoryGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Categories")
                .font(.headline)
            Text("Pick a sensor type to chart every matching accessory together.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if presentCategories.isEmpty {
                ContentUnavailableView(
                    "No chartable sensors",
                    systemImage: "square.grid.2x2",
                    description: Text(appState.settings.useMockData
                        ? "Seed mock data or wait for collection."
                        : "Live HomeKit is up, but no known categories yet (temp, humidity, contact, lock, …). Noisy auto-* characteristics stay out of this grid.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(presentCategories) { category in
                        let count = category.sensors(from: appState.sensors).count
                        Button {
                            appState.openCategory(category)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: category.systemImage)
                                    .font(.system(size: 28))
                                    .symbolRenderingMode(.hierarchical)
                                Text(category.title)
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                Text(category.unitHint(temperatureUnit: appState.settings.temperatureUnit))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(count == 1 ? "1 sensor" : "\(count) sensors")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .padding(12)
                            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct CategoryDetailView: View {
    @EnvironmentObject private var appState: AppState
    let category: SensorCategory

    @State private var selectedTime: Date?
    @State private var hoverRows: [HoverRow] = []
    @State private var tipPosition: CGPoint?
    @State private var indexedSeries: [String: [ChartSeriesPoint]] = [:]

    private struct HoverRow: Identifiable {
        var id: String
        var label: String
        var valueText: String
        var color: Color
    }

    private var categorySensors: [SensorRecord] {
        category.sensors(from: appState.sensors)
    }

    private var enabledPoints: [ChartSeriesPoint] {
        appState.categoryChartPoints.filter { point in
            if point.sensorID == AppState.outdoorWeatherSeriesID {
                return appState.settings.showOutdoorWeather && appState.outdoorChartEnabled
            }
            return appState.categoryEnabledSensorIDs.contains(point.sensorID)
        }
    }

    private var seriesLabels: [String] {
        Array(Set(enabledPoints.map(\.label))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    appState.closeCategory()
                } label: {
                    Label("Categories", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                HStack(spacing: 8) {
                    Label(category.title, systemImage: category.systemImage)
                        .font(.headline)
                    if category == .temperature {
                        Text(appState.settings.temperatureUnit.shortSymbol)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Picker("Range", selection: Binding(
                    get: { appState.timeBox },
                    set: { newValue in
                        appState.timeBox = newValue
                        Task { await appState.reloadCategoryChart() }
                    }
                )) {
                    ForEach(TimeBox.allCases) { box in
                        Text(box.rawValue).tag(box)
                    }
                }
                .frame(width: 120)
            }

            if appState.timeBox == .custom {
                DatePicker(
                    "From",
                    selection: Binding(
                        get: { appState.customStart },
                        set: { newValue in
                            appState.customStart = newValue
                            Task { await appState.reloadCategoryChart() }
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
            }

            if let weatherError = appState.outdoorWeatherError, category == .temperature {
                Text(weatherError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack(alignment: .top, spacing: 0) {
                sensorSidebar
                    .frame(width: 260)
                    .padding(.trailing, 12)

                Divider()

                chartPane
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: appState.categoryChartPoints) { _, _ in
            rebuildIndex()
        }
        .onChange(of: appState.categoryEnabledSensorIDs) { _, _ in
            rebuildIndex()
            clearHover()
        }
        .onChange(of: appState.outdoorChartEnabled) { _, _ in
            rebuildIndex()
            clearHover()
        }
        .onAppear {
            rebuildIndex()
        }
    }

    private var sensorSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Keep outside the List — Catalyst Lists often steal taps from views stacked above them.
            HStack(alignment: .center, spacing: 0) {
                Text("Sensors")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    Button {
                        appState.setAllCategorySensors(enabled: true)
                    } label: {
                        Text("All")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        appState.setAllCategorySensors(enabled: false)
                    } label: {
                        Text("None")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.leading, 4)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(.background)
            .zIndex(1)

            if categorySensors.isEmpty, !(category == .temperature && appState.settings.showOutdoorWeather) {
                Text("No sensors in this category.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                List {
                    if category == .temperature, appState.settings.showOutdoorWeather {
                        Toggle(isOn: Binding(
                            get: { appState.outdoorChartEnabled },
                            set: { enabled in
                                appState.outdoorChartEnabled = enabled
                                Task { await appState.reloadCategoryChart() }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Outdoor (weather)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(outdoorNameColor)
                                Text(outdoorSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let outdoorLatestText {
                                    Text(outdoorLatestText)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 28))
                    }

                    ForEach(categorySensors) { sensor in
                        Toggle(isOn: Binding(
                            get: { appState.categoryEnabledSensorIDs.contains(sensor.id) },
                            set: { appState.setCategorySensor(sensor.id, enabled: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sensor.accessoryName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .foregroundStyle(nameColor(for: sensor))
                                Text(sensor.roomName.isEmpty ? sensor.homeName : sensor.roomName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if category != .temperature, !category.isStateCategory {
                                    Text(sensor.unit)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                if let last = sensor.lastValue {
                                    Text(formatSidebarValue(last, unit: sensor.unit))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 28))
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .clipped() // keep List hit-testing from swallowing All/None above
            }
        }
    }

    private var chartPane: some View {
        Group {
            if enabledPoints.isEmpty {
                ContentUnavailableView(
                    categorySensors.isEmpty ? "No sensors" : "No series enabled",
                    systemImage: "chart.xyaxis.line",
                    description: Text(categorySensors.isEmpty
                        ? "Nothing in this category yet."
                        : "Toggle sensors on in the sidebar, or widen the time range.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topLeading) {
                    Chart(enabledPoints) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Value", point.value)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(by: .value("Sensor", point.label))
                        .lineStyle(StrokeStyle(
                            lineWidth: point.sensorID == AppState.outdoorWeatherSeriesID ? 2.5 : 1.5,
                            dash: point.sensorID == AppState.outdoorWeatherSeriesID ? [6, 4] : []
                        ))
                        .opacity(lineOpacity(for: point.sensorID))

                        if let selectedTime {
                            RuleMark(x: .value("Selected", selectedTime))
                                .foregroundStyle(.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                    .chartForegroundStyleScale(
                        domain: seriesLabels,
                        range: seriesLabels.map { stableColor(for: $0) }
                    )
                    .chartYScale(domain: yAxisDomain)
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6))
                    }
                    .chartYAxis {
                        yAxisMarks
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            // DragGesture needs a mouse-down; use continuous hover on Catalyst/macOS.
                            Color.clear
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        updatePrometheusHover(
                                            at: location,
                                            proxy: proxy,
                                            geometry: geo
                                        )
                                    case .ended:
                                        clearHover()
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if selectedTime == nil {
                        Text("Hover a line to inspect")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .allowsHitTesting(false)
                    }

                    if let selectedTime, let tipPosition, !hoverRows.isEmpty {
                        hoverCard(time: selectedTime, rows: hoverRows)
                            .position(tipPosition)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func hoverCard(time: Date, rows: [HoverRow]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 8, height: 8)
                    Text(row.label)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(row.valueText)
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .font(.caption2)
            }
        }
        .padding(8)
        .frame(width: 280, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    private func lineOpacity(for sensorID: String) -> Double {
        guard !hoverRows.isEmpty else { return 1 }
        return hoverRows.contains(where: { $0.id == sensorID }) ? 1 : 0.18
    }

    private func clearHover() {
        selectedTime = nil
        hoverRows = []
        tipPosition = nil
    }

    private func updatePrometheusHover(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let x = location.x - frame.origin.x
        let y = location.y - frame.origin.y
        guard x >= 0, y >= 0, x <= frame.width, y <= frame.height else {
            clearHover()
            return
        }
        guard let time: Date = proxy.value(atX: x) else { return }
        guard let yValue: Double = proxy.value(atY: y) else { return }

        selectedTime = time

        struct Candidate {
            var id: String
            var point: ChartSeriesPoint
            var distance: Double
        }

        var candidates: [Candidate] = []
        for (sensorID, series) in indexedSeries {
            guard let closest = nearest(in: series, to: time) else { continue }
            guard abs(closest.timestamp.timeIntervalSince(time)) <= 45 * 60 else { continue }
            candidates.append(
                Candidate(id: sensorID, point: closest, distance: abs(closest.value - yValue))
            )
        }
        candidates.sort { $0.distance < $1.distance }
        guard let best = candidates.first else {
            hoverRows = []
            tipPosition = nil
            return
        }

        // Include ties / near-ties (overlapping lines), Prometheus-style — no hard row cap.
        let threshold = max(best.distance * 1.25, yValueMagnitudeThreshold(yValue))
        let picked = candidates.filter { $0.distance <= threshold }

        hoverRows = picked.map { candidate in
            HoverRow(
                id: candidate.id,
                label: candidate.point.label,
                valueText: formatHoverValue(candidate.point.value),
                color: color(for: candidate.point.label)
            )
        }

        // Keep tip inside the plot, offset from the cursor like Prometheus.
        let tipWidth: CGFloat = 280
        let tipHeight: CGFloat = 28 + CGFloat(hoverRows.count) * 20
        var tipX = location.x + tipWidth / 2 + 16
        var tipY = location.y
        if tipX + tipWidth / 2 > geometry.size.width {
            tipX = location.x - tipWidth / 2 - 16
        }
        tipY = min(max(tipHeight / 2 + 8, tipY), geometry.size.height - tipHeight / 2 - 8)
        tipPosition = CGPoint(x: tipX, y: tipY)
    }

    private func yValueMagnitudeThreshold(_ y: Double) -> Double {
        if category.isStateCategory { return 0.35 }
        return max(abs(y) * 0.04, 0.75)
    }

    /// Percent metrics keep a fixed 0…100 domain; states stay on 0/1; everything else zooms to data.
    private var yAxisDomain: ClosedRange<Double> {
        switch category {
        case .humidity, .battery, .filterLife:
            return 0...100
        case .contact, .lock, .motion, .occupancy, .leak, .smoke:
            return -0.05...1.05
        default:
            return paddedValueDomain(enabledPoints.map(\.value))
        }
    }

    private var yAxisMarks: some AxisContent {
        switch category {
        case .humidity, .battery, .filterLife:
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(NumberFormatting.measurement(v))
                    }
                }
            }
        case .contact, .lock, .motion, .occupancy, .leak, .smoke:
            AxisMarks(values: [0, 1]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatHoverValue(v))
                    }
                }
            }
        default:
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(NumberFormatting.measurement(v))
                    }
                }
            }
        }
    }

    private func paddedValueDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let minV = values.min(), let maxV = values.max() else {
            return 0...1
        }
        if minV == maxV {
            let pad = max(abs(minV) * 0.08, 1)
            return (minV - pad)...(maxV + pad)
        }
        let pad = (maxV - minV) * 0.12
        return (minV - pad)...(maxV + pad)
    }

    /// Accessory name only. Off, or no samples in range, stays gray.
    private func nameColor(for sensor: SensorRecord) -> Color {
        guard appState.categoryEnabledSensorIDs.contains(sensor.id),
              let label = enabledPoints.first(where: { $0.sensorID == sensor.id })?.label
        else { return .secondary }
        return stableColor(for: label)
    }

    private var outdoorNameColor: Color {
        guard appState.outdoorChartEnabled,
              let label = enabledPoints.first(where: { $0.sensorID == AppState.outdoorWeatherSeriesID })?.label
        else { return .secondary }
        return stableColor(for: label)
    }

    private func color(for label: String) -> Color {
        guard seriesLabels.contains(label) else { return .secondary }
        return stableColor(for: label)
    }

    /// Pinned to the series label so toggling another sensor does not reshuffle colors.
    private func stableColor(for label: String) -> Color {
        var hash: UInt32 = 2166136261
        for byte in label.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16777619
        }
        return chartColors[Int(hash % UInt32(chartColors.count))]
    }

    private func rebuildIndex() {
        let grouped = Dictionary(grouping: enabledPoints, by: \.sensorID)
        indexedSeries = grouped.mapValues { points in
            points.sorted { $0.timestamp < $1.timestamp }
        }
    }

    /// Binary search nearest sample in a time-sorted series.
    private func nearest(in series: [ChartSeriesPoint], to time: Date) -> ChartSeriesPoint? {
        guard !series.isEmpty else { return nil }
        var low = 0
        var high = series.count - 1
        let target = time.timeIntervalSince1970
        while low < high {
            let mid = (low + high) / 2
            if series[mid].timestamp.timeIntervalSince1970 < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let idx = low
        if idx == 0 { return series[0] }
        let prev = series[idx - 1]
        let curr = series[idx]
        let prevDelta = abs(prev.timestamp.timeIntervalSince1970 - target)
        let currDelta = abs(curr.timestamp.timeIntervalSince1970 - target)
        return prevDelta <= currDelta ? prev : curr
    }

    private var chartColors: [Color] {
        [
            .blue, .orange, .green, .pink, .purple, .teal, .red, .yellow,
            .indigo, .mint, .cyan, .brown,
        ]
    }

    private var outdoorSubtitle: String {
        if let source = appState.weather.coordinateSource {
            return source == "ip" ? "Open-Meteo · IP location" : "Open-Meteo · device"
        }
        return "Open-Meteo · local"
    }

    private var outdoorLatestText: String? {
        guard let latest = appState.categoryChartPoints
            .filter({ $0.sensorID == AppState.outdoorWeatherSeriesID })
            .max(by: { $0.timestamp < $1.timestamp })
        else { return nil }
        return NumberFormatting.measurement(latest.value)
    }

    /// Chart points are already in display units for temperature — no second conversion.
    private func formatHoverValue(_ value: Double) -> String {
        switch category {
        case .contact:
            return value >= 0.5 ? "open" : "closed"
        case .lock:
            if value >= 0.5, value < 1.5 { return "secured" }
            if value < 0.5 { return "unsecured" }
            return NumberFormatting.measurement(value)
        case .motion, .occupancy, .leak, .smoke:
            return value >= 0.5 ? "detected" : "clear"
        default:
            return NumberFormatting.measurement(value)
        }
    }

    /// Sidebar uses storage units (Celsius, raw bools).
    private func formatSidebarValue(_ value: Double, unit: String) -> String {
        switch category {
        case .contact:
            return value >= 0.5 ? "open" : "closed"
        case .lock:
            if value >= 0.5, value < 1.5 { return "secured" }
            if value < 0.5 { return "unsecured" }
            return NumberFormatting.measurement(value)
        case .motion, .occupancy, .leak, .smoke:
            return value >= 0.5 ? "detected" : "clear"
        case .temperature:
            let display = appState.settings.temperatureUnit.display(fromCelsius: value)
            return NumberFormatting.measurement(display)
        default:
            if unit == "bool" {
                return value >= 0.5 ? "on" : "off"
            }
            return "\(NumberFormatting.measurement(value)) \(unit)"
        }
    }
}
