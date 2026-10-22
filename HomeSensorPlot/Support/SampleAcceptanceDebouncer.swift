import Foundation

/// Per-sensor write gate so notification storms don't flood SQLite.
struct SampleAcceptanceDebouncer: Sendable {
    var window: TimeInterval = 2
    private var lastAccepted: [String: Date] = [:]

    init(window: TimeInterval = 2) {
        self.window = window
    }

    mutating func shouldAccept(sensorID: String, at date: Date) -> Bool {
        if let last = lastAccepted[sensorID], date.timeIntervalSince(last) < window {
            return false
        }
        lastAccepted[sensorID] = date
        return true
    }
}
