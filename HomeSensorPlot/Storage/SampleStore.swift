import Foundation
import SQLite3

enum SampleStoreError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .openFailed(let message), .prepareFailed(let message), .stepFailed(let message):
            return message
        case .invalidPath:
            return "Invalid database path"
        }
    }
}

/// Thread-safe SQLite store for sensor metadata and time-series samples.
final class SampleStore: @unchecked Sendable {
    static let legacyDatabaseFileName = "homesensorplot.sqlite"

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.cayla.HomeSensorPlot.SampleStore", qos: .utility)
    let channel: DistributionChannel
    let databaseURL: URL

    init(directory: URL? = nil, channel: DistributionChannel? = nil) throws {
        let resolvedChannel = channel ?? DistributionChannel.current()
        self.channel = resolvedChannel
        let dir = try directory ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        databaseURL = dir.appendingPathComponent(resolvedChannel.databaseFileName)
        if !FileManager.default.fileExists(atPath: databaseURL.path) {
            do {
                try Self.copyLegacyDatabaseIfNeeded(directory: dir, channel: resolvedChannel, destination: databaseURL)
            } catch {
                NSLog(
                    "HomeSensorPlot: could not copy legacy database into \(resolvedChannel.rawValue) (\(error.localizedDescription)). Starting empty."
                )
                if FileManager.default.fileExists(atPath: databaseURL.path) {
                    try? FileManager.default.removeItem(at: databaseURL)
                }
            }
        }
        try open()
        try migrate()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    static func defaultDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SampleStoreError.invalidPath
        }
        return appSupport.appendingPathComponent("HomeSensorPlot", isDirectory: true)
    }

    // MARK: - Sensors

    func upsertSensor(_ sensor: SensorRecord) throws {
        try write("""
            INSERT INTO sensors (
                id, home_name, room_name, accessory_name, service_name,
                characteristic_type, metric_name, unit, is_hidden, is_blocked, auto_discovered
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                home_name = excluded.home_name,
                room_name = excluded.room_name,
                accessory_name = excluded.accessory_name,
                service_name = excluded.service_name,
                characteristic_type = excluded.characteristic_type,
                metric_name = excluded.metric_name,
                unit = excluded.unit,
                auto_discovered = excluded.auto_discovered
            """) { stmt in
            bindSensor(stmt, sensor)
        }
    }

    func setHidden(sensorID: String, hidden: Bool) throws {
        try write("UPDATE sensors SET is_hidden = ? WHERE id = ?") { stmt in
            sqlite3_bind_int(stmt, 1, hidden ? 1 : 0)
            bindText(stmt, 2, sensorID)
        }
    }

    func setBlocked(sensorID: String, blocked: Bool) throws {
        try write("UPDATE sensors SET is_blocked = ? WHERE id = ?") { stmt in
            sqlite3_bind_int(stmt, 1, blocked ? 1 : 0)
            bindText(stmt, 2, sensorID)
        }
    }

    func allSensors() throws -> [SensorRecord] {
        try read("""
            SELECT
                s.id, s.home_name, s.room_name, s.accessory_name, s.service_name,
                s.characteristic_type, s.metric_name, s.unit, s.is_hidden, s.is_blocked, s.auto_discovered,
                (
                    SELECT value FROM samples WHERE sensor_id = s.id ORDER BY ts DESC LIMIT 1
                ) AS last_value,
                (
                    SELECT ts FROM samples WHERE sensor_id = s.id ORDER BY ts DESC LIMIT 1
                ) AS last_ts
            FROM sensors s
            ORDER BY s.home_name, s.room_name, s.accessory_name, s.metric_name
            """) { stmt in
            var rows: [SensorRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(sensor(from: stmt, includeLast: true))
            }
            return rows
        }
    }

    func sensors(mockOnly: Bool) throws -> [SensorRecord] {
        try allSensors().filter { mockOnly ? $0.isMock : !$0.isMock }
    }

    /// Removes demo/mock sensors and their samples (used when switching to Live HomeKit).
    func deleteMockSensors() throws {
        // Samples cascade via FK; delete sensors matching mock: prefix.
        try queue.sync {
            try exec("DELETE FROM samples WHERE sensor_id LIKE 'mock:%'")
            try exec("DELETE FROM sensors WHERE id LIKE 'mock:%'")
        }
    }

    /// Drops HAP catch-all `homekit_auto_*` rows (camera/lock noise) when unknown collection is off.
    func deleteAutoMetricSensors() throws {
        try queue.sync {
            try exec("""
                DELETE FROM samples WHERE sensor_id IN (
                    SELECT id FROM sensors WHERE metric_name LIKE 'homekit_auto_%'
                )
                """)
            try exec("DELETE FROM sensors WHERE metric_name LIKE 'homekit_auto_%'")
        }
    }

    func visibleSensors() throws -> [SensorRecord] {
        try allSensors().filter { !$0.isHidden && !$0.isBlocked }
    }

    func collectibleSensorIDs() throws -> Set<String> {
        try read("SELECT id FROM sensors WHERE is_blocked = 0") { stmt in
            var ids = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.insert(String(cString: sqlite3_column_text(stmt, 0)))
            }
            return ids
        }
    }

    // MARK: - Samples

    func insertSample(sensorID: String, timestamp: Date, value: Double) throws {
        try write("INSERT INTO samples (sensor_id, ts, value) VALUES (?, ?, ?)") { stmt in
            bindText(stmt, 1, sensorID)
            sqlite3_bind_double(stmt, 2, timestamp.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, value)
        }
    }

    func insertSamples(_ samples: [(sensorID: String, timestamp: Date, value: Double)]) throws {
        guard !samples.isEmpty else { return }
        try queue.sync {
            try transaction {
                let sql = "INSERT INTO samples (sensor_id, ts, value) VALUES (?, ?, ?)"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                    throw SampleStoreError.prepareFailed(lastErrorMessage())
                }
                defer { sqlite3_finalize(stmt) }

                for sample in samples {
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    bindText(stmt, 1, sample.sensorID)
                    sqlite3_bind_double(stmt, 2, sample.timestamp.timeIntervalSince1970)
                    sqlite3_bind_double(stmt, 3, sample.value)
                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        throw SampleStoreError.stepFailed(lastErrorMessage())
                    }
                }
            }
        }
    }

    func samples(sensorID: String, from start: Date, to end: Date = .now) throws -> [SamplePoint] {
        try read("""
            SELECT id, sensor_id, ts, value
            FROM samples
            WHERE sensor_id = ? AND ts >= ? AND ts <= ?
            ORDER BY ts ASC
            """) { stmt in
            bindText(stmt, 1, sensorID)
            sqlite3_bind_double(stmt, 2, start.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, end.timeIntervalSince1970)
            var points: [SamplePoint] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                points.append(
                    SamplePoint(
                        id: sqlite3_column_int64(stmt, 0),
                        sensorID: String(cString: sqlite3_column_text(stmt, 1)),
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                        value: sqlite3_column_double(stmt, 3)
                    )
                )
            }
            return points
        }
    }

    /// Newest sample strictly before `date`, for drawing a line into the chart window.
    func latestSample(sensorID: String, before date: Date) throws -> SamplePoint? {
        try read("""
            SELECT id, sensor_id, ts, value
            FROM samples
            WHERE sensor_id = ? AND ts < ?
            ORDER BY ts DESC
            LIMIT 1
            """) { stmt in
            bindText(stmt, 1, sensorID)
            sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return SamplePoint(
                id: sqlite3_column_int64(stmt, 0),
                sensorID: String(cString: sqlite3_column_text(stmt, 1)),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                value: sqlite3_column_double(stmt, 3)
            )
        }
    }

    func latestSamples(includeHidden: Bool = false) throws -> [LatestSample] {
        let hiddenClause = includeHidden ? "" : "AND s.is_hidden = 0"
        return try read("""
            SELECT
                s.id, s.metric_name, sm.value, sm.ts,
                s.home_name, s.room_name, s.accessory_name, s.characteristic_type, s.unit
            FROM sensors s
            JOIN samples sm ON sm.id = (
                SELECT id FROM samples WHERE sensor_id = s.id ORDER BY ts DESC LIMIT 1
            )
            WHERE s.is_blocked = 0 \(hiddenClause)
            ORDER BY s.metric_name, s.accessory_name
            """) { stmt in
            var rows: [LatestSample] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    LatestSample(
                        sensorID: String(cString: sqlite3_column_text(stmt, 0)),
                        metricName: String(cString: sqlite3_column_text(stmt, 1)),
                        value: sqlite3_column_double(stmt, 2),
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                        homeName: String(cString: sqlite3_column_text(stmt, 4)),
                        roomName: String(cString: sqlite3_column_text(stmt, 5)),
                        accessoryName: String(cString: sqlite3_column_text(stmt, 6)),
                        characteristicType: String(cString: sqlite3_column_text(stmt, 7)),
                        unit: String(cString: sqlite3_column_text(stmt, 8))
                    )
                )
            }
            return rows
        }
    }

    func prune(retentionDays: Int) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        return try queue.sync {
            try writeUnlocked("DELETE FROM samples WHERE ts < ?") { stmt in
                sqlite3_bind_double(stmt, 1, cutoff.timeIntervalSince1970)
            }
            let removed = Int(sqlite3_changes(db))
            try writeUnlocked("DELETE FROM outdoor_temperatures WHERE ts < ?") { stmt in
                sqlite3_bind_double(stmt, 1, cutoff.timeIntervalSince1970)
            }
            return removed
        }
    }

    func upsertOutdoorTemperatures(_ points: [OutdoorTemperaturePoint]) throws {
        guard !points.isEmpty else { return }
        try queue.sync {
            try transaction {
                let sql = """
                    INSERT INTO outdoor_temperatures (ts, celsius) VALUES (?, ?)
                    ON CONFLICT(ts) DO UPDATE SET celsius = excluded.celsius
                    """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                    throw SampleStoreError.prepareFailed(lastErrorMessage())
                }
                defer { sqlite3_finalize(stmt) }
                for point in points {
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    sqlite3_bind_double(stmt, 1, point.timestamp.timeIntervalSince1970)
                    sqlite3_bind_double(stmt, 2, point.celsius)
                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        throw SampleStoreError.stepFailed(lastErrorMessage())
                    }
                }
            }
        }
    }

    func outdoorTemperatures(from start: Date, to end: Date = .now) throws -> [OutdoorTemperaturePoint] {
        try read("""
            SELECT ts, celsius FROM outdoor_temperatures
            WHERE ts >= ? AND ts <= ?
            ORDER BY ts ASC
            """) { stmt in
            sqlite3_bind_double(stmt, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, end.timeIntervalSince1970)
            var points: [OutdoorTemperaturePoint] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                points.append(
                    OutdoorTemperaturePoint(
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                        celsius: sqlite3_column_double(stmt, 1)
                    )
                )
            }
            return points
        }
    }

    func sensorCount() throws -> Int {
        try read("SELECT COUNT(*) FROM sensors WHERE is_blocked = 0") { stmt in
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    func sampleCount() throws -> Int {
        try read("SELECT COUNT(*) FROM samples") { stmt in
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    /// Deletes samples and sensor rows in this channel's database. Preferences are untouched.
    func deleteAllCollectedData() throws {
        try queue.sync {
            try transaction {
                try exec("DELETE FROM samples")
                try exec("DELETE FROM outdoor_temperatures")
                try exec("DELETE FROM sensors")
            }
        }
    }

    /// Point existing series at a replacement HomeKit id. Hidden and blocked flags stay on the series.
    func rebind(_ pairs: [SensorContinuityPair]) throws {
        guard !pairs.isEmpty else { return }
        try queue.sync {
            try transaction {
                for pair in pairs {
                    let flags = try hiddenAndBlocked(sensorID: pair.existing.id)
                    var sensor = pair.discovered
                    sensor.isHidden = flags.hidden
                    sensor.isBlocked = flags.blocked
                    try insertSensorUnlocked(sensor)
                    try writeUnlocked(
                        "UPDATE samples SET sensor_id = ? WHERE sensor_id = ?"
                    ) { stmt in
                        bindText(stmt, 1, sensor.id)
                        bindText(stmt, 2, pair.existing.id)
                    }
                    try writeUnlocked("DELETE FROM sensors WHERE id = ?") { stmt in
                        bindText(stmt, 1, pair.existing.id)
                    }
                }
            }
        }
    }

    static func legacyCopiedChannels(in directory: URL) -> [String] {
        let prefix = "homesensorplot.legacy-copied-to-"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names.compactMap { name in
            guard name.hasPrefix(prefix) else { return nil }
            return String(name.dropFirst(prefix.count))
        }.sorted()
    }

    // MARK: - Internals

    private static func copyLegacyDatabaseIfNeeded(
        directory: URL,
        channel: DistributionChannel,
        destination: URL
    ) throws {
        let legacy = directory.appendingPathComponent(legacyDatabaseFileName)
        let sentinel = directory.appendingPathComponent("homesensorplot.legacy-copied-to-\(channel.rawValue)")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        guard !FileManager.default.fileExists(atPath: sentinel.path) else { return }
        try checkpointWAL(at: legacy)
        try FileManager.default.copyItem(at: legacy, to: destination)
        try Data(channel.rawValue.utf8).write(to: sentinel)
    }

    private static func checkpointWAL(at databaseURL: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw SampleStoreError.openFailed("Could not open legacy database for checkpoint")
        }
        defer { sqlite3_close(handle) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Legacy checkpoint failed"
            sqlite3_free(errorMessage)
            throw SampleStoreError.stepFailed(message)
        }
    }

    private func open() throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw SampleStoreError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
        db = handle
        try exec("PRAGMA journal_mode = WAL")
        try exec("PRAGMA synchronous = NORMAL")
        try exec("PRAGMA foreign_keys = ON")
    }

    private func migrate() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS sensors (
                id TEXT PRIMARY KEY,
                home_name TEXT NOT NULL,
                room_name TEXT NOT NULL,
                accessory_name TEXT NOT NULL,
                service_name TEXT NOT NULL,
                characteristic_type TEXT NOT NULL,
                metric_name TEXT NOT NULL,
                unit TEXT NOT NULL DEFAULT '',
                is_hidden INTEGER NOT NULL DEFAULT 0,
                is_blocked INTEGER NOT NULL DEFAULT 0,
                auto_discovered INTEGER NOT NULL DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS samples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sensor_id TEXT NOT NULL,
                ts REAL NOT NULL,
                value REAL NOT NULL,
                FOREIGN KEY(sensor_id) REFERENCES sensors(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_samples_sensor_ts ON samples(sensor_id, ts);
            CREATE TABLE IF NOT EXISTS outdoor_temperatures (
                ts REAL PRIMARY KEY,
                celsius REAL NOT NULL
            );
            """)
    }

    /// Caller must already be on `queue`.
    private func transaction(_ work: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        var succeeded = false
        defer {
            if succeeded {
                try? exec("COMMIT")
            } else {
                try? exec("ROLLBACK")
            }
        }
        try work()
        succeeded = true
    }

    private func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(errorMessage)
            throw SampleStoreError.stepFailed(message)
        }
    }

    private func write(_ sql: String, bind: (OpaquePointer) -> Void) throws {
        try queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                throw SampleStoreError.prepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }
            bind(stmt)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SampleStoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    private func read<T>(_ sql: String, work: (OpaquePointer) throws -> T) throws -> T {
        try queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                throw SampleStoreError.prepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }
            return try work(stmt)
        }
    }

    private func hiddenAndBlocked(sensorID: String) throws -> (hidden: Bool, blocked: Bool) {
        let sql = "SELECT is_hidden, is_blocked FROM sensors WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SampleStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, sensorID)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw SampleStoreError.stepFailed("Missing sensor \(sensorID)")
        }
        return (sqlite3_column_int(stmt, 0) != 0, sqlite3_column_int(stmt, 1) != 0)
    }

    private func insertSensorUnlocked(_ sensor: SensorRecord) throws {
        try writeUnlocked("""
            INSERT INTO sensors (
                id, home_name, room_name, accessory_name, service_name,
                characteristic_type, metric_name, unit, is_hidden, is_blocked, auto_discovered
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """) { stmt in
            bindSensor(stmt, sensor)
        }
    }

    /// Caller must already be on `queue` and inside a transaction.
    private func writeUnlocked(_ sql: String, bind: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SampleStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SampleStoreError.stepFailed(lastErrorMessage())
        }
    }

    private func bindSensor(_ stmt: OpaquePointer, _ sensor: SensorRecord) {
        bindText(stmt, 1, sensor.id)
        bindText(stmt, 2, sensor.homeName)
        bindText(stmt, 3, sensor.roomName)
        bindText(stmt, 4, sensor.accessoryName)
        bindText(stmt, 5, sensor.serviceName)
        bindText(stmt, 6, sensor.characteristicType)
        bindText(stmt, 7, sensor.metricName)
        bindText(stmt, 8, sensor.unit)
        sqlite3_bind_int(stmt, 9, sensor.isHidden ? 1 : 0)
        sqlite3_bind_int(stmt, 10, sensor.isBlocked ? 1 : 0)
        sqlite3_bind_int(stmt, 11, sensor.autoDiscovered ? 1 : 0)
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "Database not open" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func sensor(from stmt: OpaquePointer, includeLast: Bool) -> SensorRecord {
        var lastValue: Double?
        var lastUpdated: Date?
        if includeLast, sqlite3_column_type(stmt, 11) != SQLITE_NULL {
            lastValue = sqlite3_column_double(stmt, 11)
            lastUpdated = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12))
        }
        return SensorRecord(
            id: String(cString: sqlite3_column_text(stmt, 0)),
            homeName: String(cString: sqlite3_column_text(stmt, 1)),
            roomName: String(cString: sqlite3_column_text(stmt, 2)),
            accessoryName: String(cString: sqlite3_column_text(stmt, 3)),
            serviceName: String(cString: sqlite3_column_text(stmt, 4)),
            characteristicType: String(cString: sqlite3_column_text(stmt, 5)),
            metricName: String(cString: sqlite3_column_text(stmt, 6)),
            unit: String(cString: sqlite3_column_text(stmt, 7)),
            isHidden: sqlite3_column_int(stmt, 8) != 0,
            isBlocked: sqlite3_column_int(stmt, 9) != 0,
            autoDiscovered: sqlite3_column_int(stmt, 10) != 0,
            lastValue: lastValue,
            lastUpdated: lastUpdated
        )
    }
}
