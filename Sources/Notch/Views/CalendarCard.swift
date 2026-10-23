import SwiftUI

/// Week strip plus the events of the selected day. Tap a day to see its events.
struct CalendarCard: View {
    @ObservedObject var calendar: CalendarStore
    @State private var selectedDay = Date()

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDay, format: .dateTime.month(.wide))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(selectedDay, format: .dateTime.year())
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            weekStrip(now: now)
            eventsSection(now: now)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Week strip

    private func weekStrip(now: Date) -> some View {
        let cal = Calendar.current
        let days: [Date] = {
            guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return [now] }
            return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
        }()

        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                DayCell(day: day,
                        isToday: cal.isDate(day, inSameDayAs: now),
                        isSelected: cal.isDate(day, inSameDayAs: selectedDay),
                        hasEvents: calendar.access == .granted && calendar.hasEvents(on: day))
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedDay = day }
                    }
            }
        }
    }

    // MARK: - Events

    @ViewBuilder
    private func eventsSection(now: Date) -> some View {
        switch calendar.access {
        case .notDetermined:
            PromptButton(symbol: "calendar.badge.plus", title: "Show my events") { calendar.requestAccess() }
        case .denied:
            PromptButton(symbol: "lock.fill", title: "Allow calendar access") { calendar.openPrivacySettings() }
        case .granted:
            let events = calendar.events(on: selectedDay, now: now)
            if events.isEmpty {
                Text(Calendar.current.isDate(selectedDay, inSameDayAs: now) ? "No more events today" : "No events")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(events) { event in
                            EventRow(event: event, now: now) { calendar.openCalendarApp() }
                        }
                    }
                    .padding(.bottom, 10)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let hasEvents: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            Text(day, format: .dateTime.weekday(.narrow))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
            Text(day, format: .dateTime.day())
                .font(.system(size: 11, weight: isToday ? .bold : .regular, design: .rounded))
                .frame(width: 21, height: 21)
                .background(Circle().fill(background))
                .foregroundColor(isToday || isSelected ? .white : .white.opacity(0.75))
            Circle()
                .fill(Color.white.opacity(hasEvents ? 0.5 : 0))
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isToday { return .accentColor }
        if isSelected { return .white.opacity(0.2) }
        return .white.opacity(hovering ? 0.08 : 0)
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 9.5))
                    .foregroundColor(event.isOngoing(at: now) ? event.color : .gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let url = event.meetingURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Text("Join")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(event.color.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .help("Open in Calendar")
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        if event.isOngoing(at: now) { return "Now · until \(end)" }
        return "\(start) – \(end)"
    }
}

struct PromptButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.14 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.top, 4)
    }
}
