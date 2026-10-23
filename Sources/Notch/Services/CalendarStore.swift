import AppKit
import EventKit
import SwiftUI

struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let meetingURL: URL?

    func isOngoing(at date: Date) -> Bool { !isAllDay && start <= date && date < end }
}

/// Upcoming events from the user's calendars (everything Calendar.app shows: iCloud, Google, Exchange…).
final class CalendarStore: ObservableObject {
    enum Access { case notDetermined, granted, denied }

    @Published private(set) var access: Access
    @Published private(set) var events: [CalendarEvent] = []

    private let store = EKEventStore()
    private let daysAhead = 7

    init() {
        access = Self.currentAccess()
        for name in [Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            }
        }
        reload()
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        default: return .denied
        }
    }

    func requestAccess() {
        store.requestAccess(to: .event) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.access = Self.currentAccess()
                self?.reload()
            }
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    func reload() {
        guard access == .granted else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: daysAhead + 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { event in
                CalendarEvent(id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                              title: event.title ?? "Untitled",
                              start: event.startDate,
                              end: event.endDate,
                              isAllDay: event.isAllDay,
                              color: Color(nsColor: event.calendar.color),
                              meetingURL: Self.meetingURL(for: event))
            }
    }

    /// Events on `day`; for today, ones that have already finished are dropped.
    func events(on day: Date, now: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events.filter { event in
            event.start < dayEnd && event.end > dayStart && (event.isAllDay || event.end > now)
        }
    }

    func hasEvents(on day: Date) -> Bool {
        let calendar = Calendar.current
        return events.contains { calendar.isDate($0.start, inSameDayAs: day) }
    }

    // MARK: - Video call links

    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                       "webex.com", "whereby.com", "facetime.apple.com"]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func meetingURL(for event: EKEvent) -> URL? {
        let candidates = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in candidates {
            let range = NSRange(text.startIndex..., in: text)
            for match in linkDetector?.matches(in: text, range: range) ?? [] {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }

    #if DEBUG
    func loadPreviewEvents() {
        let now = Date()
        access = .granted
        events = [
            CalendarEvent(id: "1", title: "Design review", start: now.addingTimeInterval(-900), end: now.addingTimeInterval(1800),
                          isAllDay: false, color: .orange, meetingURL: URL(string: "https://meet.google.com/abc")),
            CalendarEvent(id: "2", title: "Lunch with Ama", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800),
                          isAllDay: false, color: .green, meetingURL: nil),
            CalendarEvent(id: "3", title: "Ship notch v1.1", start: now.addingTimeInterval(14400), end: now.addingTimeInterval(16200),
                          isAllDay: false, color: .blue, meetingURL: nil),
        ]
    }
    #endif
}
