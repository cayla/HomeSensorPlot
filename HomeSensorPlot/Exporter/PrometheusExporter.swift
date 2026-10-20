import Foundation
import Network

/// Minimal localhost HTTP server exposing Prometheus text exposition at `/metrics`.
///
/// Bind contract: loopback only. If loopback cannot be bound, `start` throws — we never
/// fall back to all-interfaces (HomeKit labels must not be LAN-reachable).
final class PrometheusExporter: @unchecked Sendable {
    private let store: SampleStore
    private let queue = DispatchQueue(label: "com.cayla.HomeSensorPlot.Exporter")
    private var listener: NWListener?
    private var port: UInt16 = 9105
    /// Generation token so stale `.ready`/`.failed` from a cancelled listener are ignored.
    private var listenGeneration: UInt64 = 0

    /// Fired on the main queue when the listener becomes ready or fails after `start`.
    /// Success carries the bound port. Not called for intentional `stop()`.
    var onListenStateChanged: ((Result<UInt16, Error>) -> Void)?

    init(store: SampleStore) {
        self.store = store
    }

    func start(port: Int) throws {
        stop()
        listenGeneration &+= 1
        let generation = listenGeneration
        self.port = UInt16(clamping: max(1, min(port, 65535)))
        guard let nwPort = NWEndpoint.Port(rawValue: self.port) else {
            throw NSError(
                domain: "HomeSensorPlot.Exporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid exporter port"]
            )
        }

        // Catalyst rejects `requiredLocalEndpoint = 127.0.0.1` with NWError 22.
        // Restrict to the loopback interface instead; fail closed if that fails.
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            throw NSError(
                domain: "HomeSensorPlot.Exporter",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not bind loopback :\(self.port) (\(error.localizedDescription)). Exporter stays off.",
                ]
            )
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.emitListenState(.success(self.port), generation: generation)
            case .failed(let error):
                NSLog("HomeSensorPlot exporter failed: \(error)")
                self.queue.async {
                    // Drop the dead listener; ignore if `stop`/`start` already replaced it.
                    if self.listenGeneration == generation {
                        self.listener?.cancel()
                        self.listener = nil
                    }
                }
                self.emitListenState(.failure(error), generation: generation)
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listenGeneration &+= 1
        listener?.cancel()
        listener = nil
    }

    private func emitListenState(_ result: Result<UInt16, Error>, generation: UInt64) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.listenGeneration == generation else { return }
            self.onListenStateChanged?(result)
        }
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
                NSLog("HomeSensorPlot exporter receive error: \(error)")
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
        lines.append("# HomeSensorPlot HomeKit exporter")
        for metricName in grouped.keys.sorted() {
            lines.append("# HELP \(metricName) HomeKit sensor reading exported by HomeSensorPlot")
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
