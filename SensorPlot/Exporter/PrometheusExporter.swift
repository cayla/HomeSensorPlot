import Foundation
import Network

/// Minimal localhost HTTP server exposing Prometheus text exposition at `/metrics`.
final class PrometheusExporter: @unchecked Sendable {
    private let store: SampleStore
    private let queue = DispatchQueue(label: "com.cayla.SensorPlot.Exporter")
    private var listener: NWListener?
    private var port: UInt16 = 9105

    init(store: SampleStore) {
        self.store = store
    }

    func start(port: Int) throws {
        stop()
        self.port = UInt16(clamping: max(1, min(port, 65535)))
        guard let nwPort = NWEndpoint.Port(rawValue: self.port) else {
            throw NSError(
                domain: "SensorPlot.Exporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid exporter port"]
            )
        }

        // Catalyst rejects `requiredLocalEndpoint = 127.0.0.1` with NWError 22.
        // Prefer loopback interface; fall back to any-interface bind if needed.
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredInterfaceType = .loopback
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters, on: nwPort)
            NSLog("SensorPlot exporter: loopback bind failed (%@); listening on all interfaces", error.localizedDescription)
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("SensorPlot exporter failed: \(error)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func restart(port: Int) throws {
        try start(port: port)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                NSLog("SensorPlot exporter receive error: \(error)")
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            if let request = String(data: next, encoding: .utf8), request.contains("\r\n\r\n") || isComplete {
                self.respond(to: request, on: connection)
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: next)
        }
    }

    private func respond(to request: String, on connection: NWConnection) {
        let path = Self.requestPath(from: request)
        let body: String
        let status: String
        let contentType: String

        switch path {
        case "/metrics":
            do {
                body = try Self.renderMetrics(store: store)
                status = "200 OK"
                contentType = "text/plain; version=0.0.4; charset=utf-8"
            } catch {
                body = "# error \(error.localizedDescription)\n"
                status = "500 Internal Server Error"
                contentType = "text/plain; charset=utf-8"
            }
        case "/", "/health":
            body = "ok\n"
            status = "200 OK"
            contentType = "text/plain; charset=utf-8"
        default:
            body = "not found\n"
            status = "404 Not Found"
            contentType = "text/plain; charset=utf-8"
        }

        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func requestPath(from request: String) -> String {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: true).first
            ?? Substring(request)
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        let path = String(parts[1].split(separator: "?", maxSplits: 1)[0])
        return path.isEmpty ? "/" : path
    }

    static func renderMetrics(store: SampleStore) throws -> String {
        let samples = try store.latestSamples(includeHidden: true)
        var grouped: [String: [LatestSample]] = [:]
        for sample in samples {
            grouped[sample.metricName, default: []].append(sample)
        }

        var lines: [String] = []
        lines.append("# SensorPlot HomeKit exporter")
        for metricName in grouped.keys.sorted() {
            lines.append("# HELP \(metricName) HomeKit sensor reading exported by SensorPlot")
            lines.append("# TYPE \(metricName) gauge")
            for sample in grouped[metricName] ?? [] {
                let labels = [
                    ("home", sample.homeName),
                    ("room", sample.roomName.isEmpty ? "none" : sample.roomName),
                    ("accessory", sample.accessoryName),
                    ("characteristic", sample.characteristicType),
                    ("unit", sample.unit),
                    ("sensor_id", sample.sensorID),
                ]
                let labelText = labels
                    .map { "\($0.0)=\"\(escapeLabel($0.1))\"" }
                    .joined(separator: ",")
                lines.append("\(metricName){\(labelText)} \(formatValue(sample.value))")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func escapeLabel(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func formatValue(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value > 0 ? "+Inf" : "-Inf" }
        return String(format: "%.6g", value)
    }
}
