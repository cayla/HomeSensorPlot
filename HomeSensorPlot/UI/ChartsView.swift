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
    /// Sidebar hover. Wins over the chart's nearest-line dimming while the pointer is in the list.
    @State private var sidebarHighlightID: String?

    private struct HoverRow: Identifiable {
        var id: String
        var label: String
        var valueText: String
        var color: Color
    }

    private var categorySensors: [SensorRecord] {
        category.sensors(from: appState.sensors)
    }

    private var presentCategories: [SensorCategory] {
        SensorCategory.categoriesPresent(in: appState.sensors)
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
            let chartSeries = seriesIndex
            HStack(alignment: .top, spacing: 0) {
                sensorSidebar(statsBySensorID: windowStatsBySensorID)
                    .frame(width: 300)
                    .padding(.trailing, 12)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    chartToolbar

                    if appState.timeBox == .custom {
                        HStack {
                            Spacer(minLength: 0)
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
                    }

                    if let weatherError = appState.outdoorWeatherError, category == .temperature {
                        Text(weatherError)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    chartPane(index: chartSeries)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: appState.categoryEnabledSensorIDs) { _, _ in
            clearHover()
            sidebarHighlightID = nil
        }
        .onChange(of: appState.outdoorChartEnabled) { _, _ in
            clearHover()
            sidebarHighlightID = nil
        }
    }

    private func sensorSidebar(statsBySensorID: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Keep outside the List — Catalyst Lists often steal taps from views stacked above them.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Sensor")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text("Current")
                        .font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 12) {
                    Button {
                        appState.setAllCategorySensors(enabled: true)
                    } label: {
                        Text("All")
                            .padding(.horizontal, 2)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Click a sensor to show or hide it. The first click keeps only that sensor.")
                    Button {
                        appState.setAllCategorySensors(enabled: false)
                    } label: {
                        Text("None")
                            .padding(.horizontal, 2)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Click a sensor to show or hide it. The first click keeps only that sensor.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
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
                        sidebarRow(id: AppState.outdoorWeatherSeriesID) {
                            sensorRow(
                                title: "Outdoor (weather)",
                                subtitle: outdoorSubtitle,
                                value: outdoorLatestText,
                                prominentValue: outdoorLatestText != nil,
                                stats: statsBySensorID[AppState.outdoorWeatherSeriesID],
                                color: activeColorBySensorID[AppState.outdoorWeatherSeriesID]
                            )
                        }
                    }

                    ForEach(categorySensors) { sensor in
                        let stats = statsBySensorID[sensor.id]
                        let reading = sensor.lastValue.map {
                            ChartInteraction.sidebarReading(
                                category: category,
                                value: $0,
                                unit: sensor.unit,
                                temperatureUnit: appState.settings.temperatureUnit
                            )
                        }
                        sidebarRow(id: sensor.id) {
                            sensorRow(
                                title: sensor.accessoryName,
                                subtitle: sensor.roomName.isEmpty ? sensor.homeName : sensor.roomName,
                                value: reading?.text,
                                prominentValue: reading?.prominent == true,
                                stats: stats,
                                color: activeColorBySensorID[sensor.id]
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .clipped() // keep List hit-testing from swallowing All/None above
            }
        }
    }

    /// Up to the category grid, and the category menu, centered on the chart. The time range stays at the trailing edge.
    private var chartToolbar: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Button {
                appState.closeCategory()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Categories")

            Menu {
                ForEach(presentCategories) { item in
                    Button {
                        guard item != category else { return }
                        appState.openCategory(item)
                    } label: {
                        if item == category {
                            Label(item.title, systemImage: "checkmark")
                        } else {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Label(category.title, systemImage: category.systemImage)
                    if category == .temperature {
                        Text(appState.settings.temperatureUnit.shortSymbol)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .trailing) {
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
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func chartPane(index: SeriesIndex) -> some View {
        Group {
            if enabledPoints.isEmpty {
                ContentUnavailableView(
                    categorySensors.isEmpty ? "No sensors" : "No series enabled",
                    systemImage: "chart.xyaxis.line",
                    description: Text(categorySensors.isEmpty
                        ? "Nothing in this category yet."
                        : "Click a sensor in the sidebar, or widen the time range.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topLeading) {
                    Chart {
                        ForEach(drawingOrder(index.plotted)) { item in
                            LineMark(
                                x: .value("Time", item.point.timestamp),
                                y: .value("Value", item.point.value),
                                series: .value("Segment", item.segmentID)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(by: .value("Sensor", item.point.label))
                            .lineStyle(StrokeStyle(
                                lineWidth: lineWidth(for: item.point.sensorID),
                                dash: item.point.sensorID == AppState.outdoorWeatherSeriesID ? [6, 4] : []
                            ))
                            .opacity(lineOpacity(for: item.point.sensorID))
                            if item.drawsMarker {
                                PointMark(
                                    x: .value("Time", item.point.timestamp),
                                    y: .value("Value", item.point.value)
                                )
                                .foregroundStyle(by: .value("Sensor", item.point.label))
                                .symbolSize(44)
                                .opacity(lineOpacity(for: item.point.sensorID))
                            }
                        }
                        if let selectedTime {
                            RuleMark(x: .value("Selected", selectedTime))
                                .foregroundStyle(.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                    .chartForegroundStyleScale(
                        domain: seriesLabels,
                        range: seriesLabels.map { paletteColor(for: $0) }
                    )
                    .chartXScale(domain: xDomain, range: .plotDimension(padding: 0))
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
                                            geometry: geo,
                                            buckets: index.buckets
                                        )
                                    case .ended:
                                        clearHover()
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if selectedTime == nil {
                        Text("Hover mouse over lines to inspect")
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
        if let sidebarHighlightID {
            return sensorID == sidebarHighlightID ? 1 : 0.18
        }
        guard !hoverRows.isEmpty else { return 1 }
        return hoverRows.contains(where: { $0.id == sensorID }) ? 1 : 0.18
    }

    private func lineWidth(for sensorID: String) -> CGFloat {
        let base: CGFloat = sensorID == AppState.outdoorWeatherSeriesID ? 2.5 : 1.5
        if sidebarHighlightID == sensorID {
            return base + 1
        }
        return base
    }

    private func clearHover() {
        selectedTime = nil
        hoverRows = []
        tipPosition = nil
    }

    private func updatePrometheusHover(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        buckets: [String: SeriesBucket]
    ) {
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

        let picks = ChartInteraction.resolvedPicks(
            plotted: buckets.map { entry in
                ChartInteraction.HoverSeries(
                    id: entry.key,
                    samples: entry.value.plotted,
                    matchWindow: entry.value.pickWindow
                )
            },
            full: buckets.map { entry in
                ChartInteraction.HoverSeries(
                    id: entry.key,
                    samples: entry.value.samples,
                    matchWindow: entry.value.matchWindow
                )
            },
            time: time,
            yValue: yValue,
            stateCategory: category.isStateCategory
        )
        guard !picks.isEmpty else {
            hoverRows = []
            tipPosition = nil
            return
        }

        hoverRows = picks.compactMap { pick in
            guard let bucket = buckets[pick.id], bucket.samples.indices.contains(pick.index) else { return nil }
            let sample = bucket.samples[pick.index]
            return HoverRow(
                id: pick.id,
                label: bucket.label,
                valueText: ChartInteraction.hoverText(category: category, value: sample.value),
                color: color(for: bucket.label)
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

    /// Preset start through now. The upcoming calendar boundary stays off the axis.
    private var xDomain: ClosedRange<Date> {
        appState.timeBox.window(customStart: appState.customStart).plottedDomain()
    }

    /// Percent metrics keep a fixed 0…100 domain. Lock uses the four HomeKit states.
    /// Other states stay on 0/1. Everything else zooms to data.
    private var yAxisDomain: ClosedRange<Double> {
        if category == .lock {
            return -0.05...3.05
        }
        return ChartAxisKind.of(category).domain(values: enabledPoints.map(\.value))
    }

    private var yAxisMarks: some AxisContent {
        switch ChartAxisKind.of(category) {
        case .percent:
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(NumberFormatting.measurement(v))
                    }
                }
            }
        case .state:
            AxisMarks(
                position: .leading,
                values: category == .lock ? [0.0, 1, 2, 3] : [0.0, 1]
            ) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(ChartInteraction.hoverText(category: category, value: v))
                    }
                }
            }
        case .continuous:
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
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

    /// Enabled series with samples in range. Missing means the row stays gray.
    private var activeColorBySensorID: [String: Color] {
        var colors: [String: Color] = [:]
        for point in enabledPoints where colors[point.sensorID] == nil {
            colors[point.sensorID] = paletteColor(for: point.label)
        }
        return colors
    }

    /// Full category order, so toggling a row does not repaint the others.
    private var paletteLabels: [String] {
        var labels = categorySensors.map { category.chartSeriesLabel(for: $0) }
        if category == .temperature, appState.settings.showOutdoorWeather {
            labels.append(AppState.outdoorWeatherSeriesLabel)
        }
        return Array(Set(labels)).sorted()
    }

    private func color(for label: String) -> Color {
        guard seriesLabels.contains(label) else { return .secondary }
        return paletteColor(for: label)
    }

    private func paletteColor(for label: String) -> Color {
        guard let position = paletteLabels.firstIndex(of: label) else { return .secondary }
        let rgb = ChartPalette.color(atAlphabeticalPosition: position)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private struct SeriesBucket {
        var label: String
        /// Drawn points. These decide which series is under the cursor.
        var plotted: [ChartInteraction.Sample]
        /// Every stored sample in the window. The tooltip reads this.
        var samples: [ChartInteraction.Sample]
        /// Time gate for the drawn points, which are farther apart.
        var pickWindow: TimeInterval
        /// Time gate from the full series, so a cursor in a hole does not match.
        var matchWindow: TimeInterval
    }

    private struct PlottedPoint: Identifiable {
        var point: ChartSeriesPoint
        var segmentID: String
        /// A series with one in-window sample. A line needs two points, so the sample is a dot.
        var drawsMarker: Bool
        var id: String { point.id }
    }

    private struct SeriesIndex {
        var plotted: [PlottedPoint]
        var buckets: [String: SeriesBucket]
    }

    /// Window summary for every loaded series, including rows toggled off the chart.
    /// Built from the full window, not the downsampled line, so a spike the chart
    /// skips still appears here. Hiding the line must not drop the caption.
    private var windowStatsBySensorID: [String: String] {
        var texts: [String: String] = [:]
        for (sensorID, samples) in appState.categoryWindowSamples {
            let ordered = samples.sorted { $0.timestamp < $1.timestamp }
            if let text = ChartInteraction.statsText(
                category: category,
                samples: ordered,
                symbol: measurementSymbol(for: sensorID)
            ) {
                texts[sensorID] = text
            }
        }
        return texts
    }

    private func measurementSymbol(for sensorID: String) -> String? {
        if sensorID == AppState.outdoorWeatherSeriesID {
            return "°"
        }
        let unit = categorySensors.first { $0.id == sensorID }?.unit ?? ""
        return category.measurementSymbol(unit: unit)
    }

    /// Time-sorted points, split where `SeriesGaps` says the line should stop.
    private var seriesIndex: SeriesIndex {
        var grouped: [String: [ChartSeriesPoint]] = [:]
        var order: [String] = []
        for point in enabledPoints {
            if grouped[point.sensorID] == nil {
                order.append(point.sensorID)
            }
            grouped[point.sensorID, default: []].append(point)
        }

        var visibleCount: [String: Int] = [:]
        for point in enabledPoints {
            visibleCount[point.sensorID, default: 0] += 1
        }

        var plotted: [PlottedPoint] = []
        plotted.reserveCapacity(enabledPoints.count)
        var buckets: [String: SeriesBucket] = [:]
        buckets.reserveCapacity(order.count)
        for sensorID in order {
            let sorted = grouped[sensorID, default: []].sorted { $0.timestamp < $1.timestamp }
            let full = (appState.categoryWindowSamples[sensorID] ?? [])
                .sorted { $0.timestamp < $1.timestamp }
            let gapTimestamps = full.isEmpty ? sorted.map(\.timestamp) : full.map(\.timestamp)
            let layout = SeriesGaps.layout(timestamps: gapTimestamps)
            let pickLayout = SeriesGaps.layout(timestamps: sorted.map(\.timestamp))
            buckets[sensorID] = SeriesBucket(
                label: sorted.first?.label ?? "",
                plotted: sorted.map {
                    ChartInteraction.Sample(timestamp: $0.timestamp, value: $0.value)
                },
                samples: full.isEmpty
                    ? sorted.map { ChartInteraction.Sample(timestamp: $0.timestamp, value: $0.value) }
                    : full,
                pickWindow: pickLayout.matchWindow,
                matchWindow: layout.matchWindow
            )
            let markLonelySample = visibleCount[sensorID] == 1
            for (offset, point) in sorted.enumerated() {
                let segment = SeriesGaps.segmentIndex(
                    at: point.timestamp,
                    timestamps: gapTimestamps,
                    segments: layout.segments
                )
                plotted.append(
                    PlottedPoint(
                        point: point,
                        segmentID: segment.map { "\(sensorID)#\($0)" } ?? "\(sensorID)#off-\(offset)",
                        drawsMarker: markLonelySample
                    )
                )
            }
        }
        return SeriesIndex(plotted: plotted, buckets: buckets)
    }

    /// Highlighted series last, so it paints over the lines it sits on.
    private func drawingOrder(_ points: [PlottedPoint]) -> [PlottedPoint] {
        guard let sidebarHighlightID else { return points }
        var rest: [PlottedPoint] = []
        var hot: [PlottedPoint] = []
        rest.reserveCapacity(points.count)
        for point in points {
            if point.point.sensorID == sidebarHighlightID {
                hot.append(point)
            } else {
                rest.append(point)
            }
        }
        rest.append(contentsOf: hot)
        return rest
    }

    private func sidebarRow<Content: View>(
        id: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            appState.tapCategoryChartRow(id)
        } label: {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 16))
        .listRowBackground(rowBackground(for: id))
        .onContinuousHover { phase in
            setSidebarHighlight(id, inside: hoverIsActive(phase))
        }
    }

    private func sensorRow(
        title: String,
        subtitle: String,
        value: String?,
        prominentValue: Bool,
        stats: String?,
        color: Color?
    ) -> some View {
        let active = color != nil
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                SeriesSwatch(color: color ?? Color.secondary.opacity(0.45))
                    .padding(.top, 4)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(active ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value)
                        .font(prominentValue
                            ? .title3.monospacedDigit().weight(.semibold)
                            : .subheadline.weight(.semibold))
                        .foregroundStyle(active ? .primary : .secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let stats {
                    Text(stats)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.leading, 16)
        }
    }

    private func rowBackground(for sensorID: String) -> Color {
        sidebarHighlightID == sensorID ? Color.primary.opacity(0.08) : Color.clear
    }

    private func hoverIsActive(_ phase: HoverPhase) -> Bool {
        if case .active = phase { return true }
        return false
    }

    private func setSidebarHighlight(_ sensorID: String, inside: Bool) {
        guard activeColorBySensorID[sensorID] != nil else {
            if sidebarHighlightID == sensorID {
                sidebarHighlightID = nil
            }
            return
        }
        if inside {
            if sidebarHighlightID != sensorID {
                clearHover()
            }
            sidebarHighlightID = sensorID
        } else if sidebarHighlightID == sensorID {
            sidebarHighlightID = nil
        }
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
        return NumberFormatting.withUnit(NumberFormatting.measurement(latest.value), "°")
    }

}

/// Color dab for a sidebar row. The name stays in the label color.
private struct SeriesSwatch: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}
