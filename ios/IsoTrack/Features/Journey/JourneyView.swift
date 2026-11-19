import Charts
import SwiftUI

/// The long view: the cumulative curve, the calendar, milestones and history.
struct JourneyView: View {
    @Environment(AppStore.self) private var store
    @State private var daySelection: DaySelection?

    var body: some View {
        NavigationStack {
            CardScroll {
                SplitColumns {
                    ChartCard()
                    MilestonesCard()
                } trailing: {
                    CalendarCard { daySelection = DaySelection(day: $0) }
                    HistoryCard { daySelection = DaySelection(day: $0) }
                }
            }
            .tabScreen("Journey")
            .sheet(item: $daySelection) { selection in
                DaySheet(day: selection.day)
            }
        }
    }
}

// MARK: - Chart

struct ChartCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDate: Date?
    /// 0...1 — how much of the curve has been drawn in.
    @State private var reveal: CGFloat = 0

    var body: some View {
        let course = store.course
        let series = course.dailySeries
        let selected = selectedPoint(in: series)

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.map { DateText.short($0.day) } ?? "Cumulative dose").eyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(CourseSnapshot.whole(selected?.cumulative ?? course.cumulativeMg))
                        .font(.display(.title))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: selected?.cumulative ?? course.cumulativeMg))
                        .animation(.snappy(duration: 0.25), value: selected?.cumulative ?? course.cumulativeMg)
                    Text("mg")
                        .font(.display(.headline))
                        .foregroundStyle(.secondary)
                }
            }

            if series.count < 2 {
                emptyState
            } else {
                chart(course: course, series: series, selected: selected)
                    // The curve draws itself in from the left.
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: reveal, y: 1, anchor: .leading)
                    }
                    .onAppear {
                        guard reveal == 0 else { return }
                        if reduceMotion {
                            reveal = 1
                        } else {
                            withAnimation(.easeInOut(duration: 1.3).delay(0.3)) { reveal = 1 }
                        }
                    }
                    .sensoryFeedback(.selection, trigger: selected?.day)
                legend(course)
            }
        }
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundStyle(Color.brand)
            Text("Your curve starts here")
                .font(.display(.headline))
            Text("Log doses on two different days and your cumulative dose will be charted against your goal.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func chart(course: CourseSnapshot, series: [CourseSnapshot.SeriesPoint],
                       selected: CourseSnapshot.SeriesPoint?) -> some View {
        let top = max(course.goalMg, course.cumulativeMg) * 1.1
        let floor = max(0, (series.first?.cumulative ?? 0) - top * 0.04)
        let showLowMark = course.lowMarkMg < course.goalMg - 0.5 && course.lowMarkMg > floor

        return Chart {
            ForEach(series) { point in
                AreaMark(
                    x: .value("Day", point.date),
                    yStart: .value("Base", floor),
                    yEnd: .value("Cumulative", point.cumulative)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.brand.opacity(0.14))

                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Cumulative", point.cumulative),
                    series: .value("Series", "Logged")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.brand)
            }

            // Dashed projection from today to the estimated finish.
            if let finish = course.estimatedFinish, let last = series.last, finish > last.date {
                LineMark(x: .value("Day", last.date), y: .value("Cumulative", last.cumulative),
                         series: .value("Series", "Projected"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 6]))
                    .foregroundStyle(Color.brand.opacity(0.7))
                LineMark(x: .value("Day", finish), y: .value("Cumulative", course.goalMg),
                         series: .value("Series", "Projected"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 6]))
                    .foregroundStyle(Color.brand.opacity(0.7))
            }

            RuleMark(y: .value("Goal", course.goalMg))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.primary.opacity(0.45))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("Goal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

            if showLowMark {
                RuleMark(y: .value("120 mg/kg", course.lowMarkMg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.info.opacity(0.8))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("120 mg/kg")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.info)
                    }
            }

            if let selected {
                RuleMark(x: .value("Day", selected.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                PointMark(x: .value("Day", selected.date), y: .value("Cumulative", selected.cumulative))
                    .symbolSize(90)
                    .foregroundStyle(Color.brand)
            }
        }
        .chartYScale(domain: floor...top)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel {
                    if let mg = value.as(Double.self) {
                        Text(Self.compact(mg))
                    }
                }
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Cumulative dose over time")
        .accessibilityValue("\(CourseSnapshot.whole(course.cumulativeMg)) of \(CourseSnapshot.whole(course.goalMg)) milligrams")
    }

    private func legend(_ course: CourseSnapshot) -> some View {
        HStack(spacing: 14) {
            legendItem("Logged", color: .brand, dashed: false)
            if course.estimatedFinish != nil {
                legendItem("At your current pace", color: .brand, dashed: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendItem(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dashed ? [2, 5] : []))
                .frame(width: 18, height: 3)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func selectedPoint(in series: [CourseSnapshot.SeriesPoint]) -> CourseSnapshot.SeriesPoint? {
        guard let selectedDate, !series.isEmpty else { return nil }
        let day = Day.string(from: selectedDate)
        if let exact = series.first(where: { $0.day == day }) { return exact }
        return day < series[0].day ? series.first : series.last
    }

    /// "1.5k", "12k", "800"
    private static func compact(_ mg: Double) -> String {
        guard mg >= 1000 else { return String(Int(mg)) }
        let thousands = mg / 1000
        return thousands == thousands.rounded()
            ? "\(Int(thousands))k"
            : String(format: "%.1fk", thousands)
    }
}

// MARK: - Calendar

struct CalendarCard: View {
    @Environment(AppStore.self) private var store
    let openDay: (String) -> Void

    /// Months back from the current one (0 = this month).
    @State private var monthsBack = 0
    /// Which side the next month slides in from.
    @State private var slideFrom: Edge = .leading

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let course = store.course
        let calendar = Calendar.current
        let today = Day.date(from: course.today)
        let monthStart = Self.monthStart(monthsBack: monthsBack, from: today, calendar: calendar)
        let days = Self.days(in: monthStart, calendar: calendar)
        let leadingBlanks = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let mgByDay = course.mgByDay
        let appointmentDays = Set(store.appointments.map(\.day))
        let loggedCount = days.filter { mgByDay[$0] != nil }.count
        let monthMg = days.reduce(0.0) { $0 + (mgByDay[$1] ?? 0) }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(monthStart.formatted(.dateTime.month(.wide).year()))
                    .font(.display(.headline))
                    .contentTransition(.numericText())
                Spacer()
                monthButton("chevron.left", label: "Previous month") { step(by: 1) }
                monthButton("chevron.right", label: "Next month") { step(by: -1) }
                    .disabled(monthsBack == 0)
                    .opacity(monthsBack == 0 ? 0.35 : 1)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Self.weekdaySymbols(calendar: calendar), id: \.offset) { symbol in
                    Text(symbol.element)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 40)
                }
                ForEach(days, id: \.self) { day in
                    CalendarDay(
                        day: day,
                        state: state(for: day, course: course, mgByDay: mgByDay),
                        hasAppointment: appointmentDays.contains(day)
                    ) {
                        openDay(day)
                    }
                }
            }
            .id(monthsBack)
            .transition(.asymmetric(
                insertion: .move(edge: slideFrom).combined(with: .opacity),
                removal: .move(edge: slideFrom == .leading ? .trailing : .leading).combined(with: .opacity)
            ))

            HStack(spacing: 12) {
                Text("\(loggedCount) \(loggedCount == 1 ? "day" : "days") logged · \(CourseSnapshot.whole(monthMg)) mg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if !appointmentDays.isEmpty {
                    HStack(spacing: 5) {
                        Circle().fill(Color.info).frame(width: 6, height: 6)
                        Text("Appointment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .sensoryFeedback(.selection, trigger: monthsBack)
    }

    /// Moves `delta` months into the past (negative = toward the present).
    private func step(by delta: Int) {
        slideFrom = delta > 0 ? .leading : .trailing
        withAnimation(Motion.spring) {
            monthsBack = max(0, monthsBack + delta)
        }
    }

    private func monthButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 40)
                .background(Color.surfaceRaised, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(Color.primary)
        .accessibilityLabel(label)
    }

    private func state(for day: String, course: CourseSnapshot, mgByDay: [String: Double]) -> CalendarDay.State {
        if mgByDay[day] != nil { return .logged }
        if day > course.today { return .future }
        if day == course.today { return .today }
        if let first = course.firstDay, day > first { return .missed }
        return .idle
    }

    private static func monthStart(monthsBack: Int, from today: Date, calendar: Calendar) -> Date {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        return calendar.date(byAdding: .month, value: -monthsBack, to: thisMonth) ?? thisMonth
    }

    private static func days(in monthStart: Date, calendar: Calendar) -> [String] {
        let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: monthStart).map(Day.string(from:))
        }
    }

    private static func weekdaySymbols(calendar: Calendar) -> [EnumeratedSequence<[String]>.Element] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array((Array(symbols[shift...]) + Array(symbols[..<shift])).enumerated())
    }
}

struct CalendarDay: View {
    enum State {
        case logged, missed, today, future, idle
    }

    let day: String
    let state: State
    let hasAppointment: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(Day.date(from: day).formatted(.dateTime.day()))
                .font(.display(.subheadline, weight: state == .logged ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background { background }
                .overlay(alignment: .bottom) {
                    if hasAppointment {
                        Circle()
                            .fill(Color.info)
                            .frame(width: 5, height: 5)
                            .padding(.bottom, 4)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .pulse(on: state, amount: 1.15)
        .animation(Motion.spring, value: state)
        .disabled(state == .future)
        .accessibilityLabel("\(DateText.long(day)), \(accessibilityState)\(hasAppointment ? ", appointment" : "")")
    }

    private var foreground: Color {
        switch state {
        case .logged: return .primary
        case .missed: return .warn
        case .today: return .brand
        case .future: return Color.secondary.opacity(0.5)
        case .idle: return .secondary
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        switch state {
        case .logged: shape.fill(Color.brand.opacity(0.26))
        case .missed: shape.fill(Color.warn.opacity(0.13))
        case .today: shape.strokeBorder(Color.brand, lineWidth: 2)
        case .future, .idle: Color.clear
        }
    }

    private var accessibilityState: String {
        switch state {
        case .logged: return "logged"
        case .missed: return "not logged"
        case .today: return "today, not logged yet"
        case .future: return "upcoming"
        case .idle: return "no dose"
        }
    }
}

// MARK: - Milestones

struct MilestonesCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let course = store.course
        let milestones = course.milestones
        VStack(alignment: .leading, spacing: 4) {
            CardHeader("Milestones")
                .padding(.bottom, 8)

            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(systemName: milestone.isReached ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: milestone.isReached)
                            .foregroundStyle(milestone.isReached ? Color.brand : Color.secondary.opacity(0.4))
                        if index < milestones.count - 1 {
                            Rectangle()
                                .fill(milestone.isReached ? Color.brand.opacity(0.45) : Color.hairline)
                                .frame(width: 2)
                                .frame(minHeight: 22)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(milestone.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(milestone.isReached ? .primary : .secondary)
                        Text(milestone.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 14)
                    Spacer(minLength: 8)
                    Text(status(milestone, today: course.today))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(milestone.isReached ? Color.good : Color.secondary)
                        .contentTransition(.numericText())
                        .padding(.top, 3)
                }
                .riseIn(3 + index, distance: 14)
                .animation(Motion.spring, value: milestone.state)
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func status(_ milestone: CourseSnapshot.Milestone, today: String) -> String {
        switch milestone.state {
        case .reached(let day): return DateText.monthDay(day, relativeTo: today)
        case .reachedBeforeTracking: return "Before tracking"
        case .projected(let day): return "≈ \(DateText.monthDay(day, relativeTo: today))"
        case .pending: return "—"
        }
    }
}

// MARK: - History

struct HistoryCard: View {
    @Environment(AppStore.self) private var store
    let openDay: (String) -> Void

    private static let previewCount = 5

    var body: some View {
        let entries = store.entries
        let recent = Array(entries.suffix(Self.previewCount).reversed())
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Recent doses") {
                if entries.count > Self.previewCount {
                    NavigationLink {
                        HistoryListView()
                    } label: {
                        Text("All \(entries.count)")
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            if recent.isEmpty {
                Text("Nothing logged yet. Your doses will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(recent) { entry in
                    Button {
                        openDay(entry.day)
                    } label: {
                        DoseRow(entry: entry, today: store.today, slotLabel: slotLabel(for: entry))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("Recent doses")
                }
            }
        }
        .card()
    }

    private func slotLabel(for entry: DoseEntry) -> String? {
        store.schedule.first { $0.id == entry.slotId }?.label
    }
}

struct DoseRow: View {
    let entry: DoseEntry
    let today: String
    /// The scheduled dose this entry ticked off, e.g. "First meal".
    var slotLabel: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "pills.fill", tint: .brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.day == today ? "Today" : DateText.short(entry.day))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text([slotLabel, CourseSnapshot.doseLabel(mgPerPill: entry.mgPerPill, pillCount: entry.pillCount)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("+\(CourseSnapshot.trimmed(entry.totalMg)) mg")
                .font(.display(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every dose, newest first, grouped by month. Swipe to delete.
struct HistoryListView: View {
    @Environment(AppStore.self) private var store

    private var months: [(title: String, entries: [DoseEntry])] {
        let grouped = Dictionary(grouping: store.entries) { String($0.day.prefix(7)) }
        return grouped.keys.sorted(by: >).map { key in
            let entries = (grouped[key] ?? []).reversed()
            let title = Day.date(from: key + "-01").formatted(.dateTime.month(.wide).year())
            return (title, Array(entries))
        }
    }

    var body: some View {
        List {
            ForEach(months, id: \.title) { month in
                Section {
                    ForEach(month.entries) { entry in
                        DoseRow(entry: entry, today: store.today,
                                slotLabel: store.schedule.first { $0.id == entry.slotId }?.label)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(month.title)
                        Spacer()
                        Text("\(CourseSnapshot.whole(month.entries.reduce(0) { $0 + $1.totalMg })) mg")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle("All doses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
