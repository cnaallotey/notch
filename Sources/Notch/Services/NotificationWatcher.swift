import AppKit
import SQLite3

struct NotchAlert: Identifiable, Equatable {
    let id: Int64
    let bundleID: String
    let appName: String
    let icon: NSImage?
    let symbol: String?
    let title: String
    let subtitle: String
    let body: String
    let date: Date
}

/// Mirrors other apps' notifications by reading new rows from Notification Center's own database.
/// Everything stays on this Mac. macOS 15 and later protect that database, so there it only works
/// once Notch has Full Disk Access.
final class NotificationWatcher {
    /// Called on the main queue for each newly delivered notification.
    var onAlert: ((NotchAlert) -> Void)?

    private var lastID: Int64 = 0
    private var lastWALChange: Date?
    private var timer: Timer?
    private let maxAge: TimeInterval = 30

    private static let focusID = "com.apple.controlcenter.notifications.focus"

    private static var databasePath: String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count)
        return String(cString: buffer) + "com.apple.notificationcenter/db2/db"
    }

    func start() {
        guard timer == nil, let id = withDatabase(latestID) else { return }
        lastID = id
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stop() }

    /// A fresh connection per read: a long-lived read-only one keeps seeing a stale snapshot
    /// of the database while Notification Center writes to it.
    private func withDatabase<T>(_ body: (OpaquePointer?) -> T) -> T? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(Self.databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        return body(db)
    }

    private func latestID(_ db: OpaquePointer?) -> Int64 {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT MAX(rec_id) FROM record", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(statement, 0)
    }

    /// Only query when Notification Center has written something since the last look.
    private func poll() {
        let wal = try? FileManager.default.attributesOfItem(atPath: Self.databasePath + "-wal")[.modificationDate] as? Date
        guard wal == nil || wal != lastWALChange else { return }
        lastWALChange = wal
        withDatabase(readNewAlerts)?.forEach { onAlert?($0) }
    }

    private func readNewAlerts(_ db: OpaquePointer?) -> [NotchAlert] {
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a USING(app_id)
            WHERE r.rec_id > ? ORDER BY r.rec_id
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int64(statement, 1, lastID)

        var alerts: [NotchAlert] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            lastID = max(lastID, id)
            guard let identifier = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
                  let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
            // Skip anything stale, e.g. a backlog delivered after waking from sleep.
            guard Date().timeIntervalSince(date) < maxAge,
                  let alert = Self.alert(id: id, bundleID: identifier, data: data, date: date) else { continue }
            alerts.append(alert)
        }
        return alerts
    }

    private static func alert(id: Int64, bundleID: String, data: Data, date: Date) -> NotchAlert? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let request = plist["req"] as? [String: Any] else { return nil }

        let title = text(request["titl"])
        let subtitle = text(request["subt"])
        let body = text(request["body"])
        guard !(title.isEmpty && body.isEmpty) else { return nil }

        if bundleID == focusID {
            return NotchAlert(id: id, bundleID: bundleID, appName: "Focus", icon: nil, symbol: "moon.fill",
                              title: title, subtitle: subtitle, body: body.capitalized, date: date)
        }

        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let appName = appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
        let icon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        return NotchAlert(id: id, bundleID: bundleID, appName: appName, icon: icon, symbol: icon == nil ? "app.badge.fill" : nil,
                          title: title, subtitle: subtitle, body: body, date: date)
    }

    /// Fields are usually plain strings, but localised ones are stored as [format, arguments…].
    private static func text(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let parts = value as? [Any], let first = parts.first as? String { return first }
        return ""
    }
}
