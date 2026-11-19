import SwiftUI

/// Identifies the day whose doses are being edited in a sheet.
struct DaySelection: Identifiable, Hashable {
    let day: String
    var id: String { day }
}

/// The home screen: where the course stands, and one tap to log today (or a
/// tick box for each scheduled dose).
///
/// On a compact iPhone (and the Duo's outer display) it is a single column.
/// On the Duo's inner display it becomes two panes that the system arranges
/// around the fold — side by side when open flat, and split across the hinge
/// when the phone is propped half open.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var daySelection: DaySelection?
    @State private var fold: FoldPosition?

    var body: some View {
        NavigationStack {
            layout
                .tabScreen("Today")
                .modifier(DateSubtitle(day: store.today))
                .sheet(item: $daySelection) { selection in
                    DaySheet(day: selection.day)
                }
        }
    }

    @ViewBuilder
    private var layout: some View {
        if horizontalSizeClass == .regular {
            if #available(iOS 27.1, *) {
                ArrangementView {
                    CardScroll { CardStack { coursePane } }
                        // Open flat, put the seam between the panes on the fold.
                        .splitArrangementLayoutRatio(fold?.fraction)
                } secondary: {
                    CardScroll { CardStack(startIndex: 1) { detailPane } }
                }
                .arrangementViewStyle(.split)
                .onFoldChange { fold = $0 }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    CardScroll { CardStack { coursePane } }
                    CardScroll { CardStack(startIndex: 1) { detailPane } }
                }
            }
        } else {
            CardScroll {
                CardStack {
                    coursePane
                    detailPane
                }
            }
        }
    }

    /// The essentials: progress, the log button, and the week so far.
    @ViewBuilder
    private var coursePane: some View {
        HeroCard()
        DoseCard { daySelection = DaySelection(day: $0) }
        WeekCard { daySelection = DaySelection(day: $0) }
    }

    /// Everything else worth a glance.
    @ViewBuilder
    private var detailPane: some View {
        UpNextCard()
        StatsGrid()
    }
}

/// Shows the date under the title where the system supports a subtitle.
private struct DateSubtitle: ViewModifier {
    let day: String

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(DateText.long(day))
        } else {
            content
        }
    }
}

// MARK: - Hero

struct HeroCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the ring and the counters are currently showing; they chase the
    /// real values so the card fills and counts up instead of snapping.
    @State private var shownProgress: Double = 0
    @State private var shownMg: Double = 0
    @State private var shownMgPerKg: Double = 0

    var body: some View {
        let course = store.course
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    ring(course)
                    summary(course)
                }
                VStack(spacing: 16) {
                    ring(course)
                    summary(course)
                }
            }
            footer(course)
        }
        .card()
        .onAppear { animate(to: course, delay: 0.25) }
        .onChange(of: course.cumulativeMg) { _, _ in animate(to: store.course, delay: 0) }
        .onChange(of: course.goalMg) { _, _ in animate(to: store.course, delay: 0) }
        .modifier(ReplayOnUnfold { replay() })
    }

    private func ring(_ course: CourseSnapshot) -> some View {
        ZStack {
            ProgressRing(
                progress: shownProgress,
                lineWidth: 14,
                marker: course.lowMarkMg < course.goalMg - 0.5 ? course.lowMarkMg / course.goalMg : nil
            )
            VStack(spacing: -2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    RollingNumber(value: shownProgress * 100) { "\(Int($0.rounded(.down)))" }
                        .font(.system(size: 38, weight: .semibold))
                    Text("%")
                        .font(.display(.headline))
                        .foregroundStyle(.secondary)
                }
                Text("of goal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 132, height: 132)
        // A dose landing gives the ring a heartbeat.
        .pulse(on: store.logPulse, amount: 1.07)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Course progress")
        .accessibilityValue("\(Int((course.progress * 100).rounded(.down))) percent of goal")
    }

    private func summary(_ course: CourseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cumulative dose").eyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    RollingNumber(value: shownMg)
                        .font(.system(size: 34, weight: .semibold))
                    Text("mg")
                        .font(.display(.headline))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text("of \(CourseSnapshot.whole(course.goalMg)) mg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                RollingNumber(value: shownMgPerKg) { $0.formatted(.number.precision(.fractionLength(1))) }
                    .font(.display(.headline))
                Text("of \(CourseSnapshot.whole(course.goalMgPerKg)) mg/kg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cumulative dose")
        .accessibilityValue("\(CourseSnapshot.whole(course.cumulativeMg)) of \(CourseSnapshot.whole(course.goalMg)) milligrams, \(course.mgPerKg.formatted(.number.precision(.fractionLength(1)))) milligrams per kilogram")
    }

    @ViewBuilder
    private func footer(_ course: CourseSnapshot) -> some View {
        if course.goalReached {
            footerLabel("Goal reached. You did it.", symbol: "checkmark.seal.fill", tint: .good)
        } else if let finish = course.estimatedFinishDay, let days = course.daysUntilFinish {
            footerLabel(
                days <= 0
                    ? "On pace to finish today"
                    : "On pace to finish \(DateText.monthDay(finish, relativeTo: course.today)) · \(days) \(days == 1 ? "day" : "days")",
                symbol: "flag.checkered", tint: .brand
            )
        } else {
            footerLabel("Log a dose to see your finish date", symbol: "flag.checkered", tint: .secondary)
        }
    }

    private func footerLabel(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
            .animation(Motion.spring, value: text)
    }

    private func animate(to course: CourseSnapshot, delay: Double) {
        guard !reduceMotion else {
            shownProgress = course.progress
            shownMg = course.cumulativeMg
            shownMgPerKg = course.mgPerKg
            return
        }
        withAnimation(Motion.fill.delay(delay)) {
            shownProgress = course.progress
            shownMg = course.cumulativeMg
            shownMgPerKg = course.mgPerKg
        }
    }

    /// Empties the card and fills it again.
    private func replay() {
        guard !reduceMotion else { return }
        shownProgress = 0
        shownMg = 0
        shownMgPerKg = 0
        animate(to: store.course, delay: 0.15)
    }
}

/// Replays an animation when an iPhone Duo is opened all the way. Purely a
/// flourish — layout never depends on the hinge.
private struct ReplayOnUnfold: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { old, new in
                guard let hinge = new.hinge, hinge.status == .fullyOpen,
                      old.hinge?.status != .fullyOpen else { return }
                action()
            }
        } else {
            content
        }
    }
}

// MARK: - Today's dose

struct DoseCard: View {
    @Environment(AppStore.self) private var store
    @State private var showSchedule = false
    let openDay: (String) -> Void

    var body: some View {
        let course = store.course
        VStack(alignment: .leading, spacing: 14) {
            // The button dissolves into the confirmation, and back again.
            if course.hasSchedule {
                scheduled(course)
                    .transition(.blurReplace.combined(with: .scale(0.96)))
            } else if course.loggedToday {
                logged(course)
                    .transition(.blurReplace.combined(with: .scale(0.96)))
            } else {
                notLogged(course)
                    .transition(.blurReplace.combined(with: .scale(0.96)))
            }

            if course.yesterdayMissed {
                Rectangle().fill(Color.hairline).frame(height: 1)
                HStack(spacing: 10) {
                    Label("Nothing logged yesterday", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button(course.hasSchedule ? "Log all" : "Log usual") {
                        store.logFullDay(course.yesterday)
                    }
                    .buttonStyle(SoftButtonStyle())
                    .accessibilityLabel(course.hasSchedule
                                        ? "Log all of yesterday's scheduled doses"
                                        : "Log usual dose for yesterday")
                }
                .transition(.blurReplace)
            }
        }
        .card()
        .animation(Motion.spring, value: course.loggedToday)
        .animation(Motion.spring, value: course.yesterdayMissed)
        .animation(Motion.spring, value: course.hasSchedule)
        .sheet(isPresented: $showSchedule) {
            ScheduleSheet()
        }
    }

    /// With a dose schedule: a tick box per dose, and how far through the
    /// day's total they add up to.
    private func scheduled(_ course: CourseSnapshot) -> some View {
        let taken = course.takenSlotCount(on: course.today)
        let complete = course.todayComplete
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Today's doses") {
                Button("Edit") { showSchedule = true }
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel("Edit dose schedule")
            }

            SlotChecklist(day: course.today)
                .padding(.vertical, -4)

            MeterBar(value: course.scheduledMg > 0 ? course.todayMg / course.scheduledMg : 0, height: 6)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(complete ? "All done for today" : "\(taken) of \(course.schedule.count) taken")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(complete ? Color.brand : Color.primary)
                        .contentTransition(.numericText())
                    Text("\(CourseSnapshot.trimmed(course.todayMg)) of \(CourseSnapshot.trimmed(course.scheduledMg)) mg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: course.todayMg))
                }
                .animation(Motion.spring, value: course.todayMg)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("schedule-status")
                Spacer(minLength: 4)
                Button("Other dose") {
                    openDay(course.today)
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }

    private func notLogged(_ course: CourseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Today's dose") {
                Button("Split dose") { showSchedule = true }
                    .font(.caption.weight(.semibold))
                    .accessibilityHint("Sets up separate doses to tick off through the day")
                    .accessibilityIdentifier("split-dose")
            }

            if course.entries.isEmpty {
                // No history yet, so there's no "usual" to offer.
                Button {
                    openDay(course.today)
                } label: {
                    Label("Log your first dose", systemImage: "pills.fill")
                        .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 4)))
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("log-first")

                Text("Pick the pill strength and how many you took.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    store.addUsualDose()
                } label: {
                    Label("Log \(CourseSnapshot.trimmed(course.usualTotalMg)) mg", systemImage: "pills.fill")
                        .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 4)))
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("log-usual")

                HStack(spacing: 10) {
                    Text("Your usual · \(CourseSnapshot.doseLabel(mgPerPill: course.usualDose.mgPerPill, pillCount: course.usualDose.pillCount))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Other dose") {
                        openDay(course.today)
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    private func logged(_ course: CourseSnapshot) -> some View {
        let todays = course.entries(on: course.today)
        let detail = todays.count == 1
            ? CourseSnapshot.doseLabel(mgPerPill: todays[0].mgPerPill, pillCount: todays[0].pillCount)
            : "\(todays.count) doses"
        return HStack(spacing: 12) {
            CheckBurst(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Logged today")
                    .font(.display(.headline))
                Text("\(CourseSnapshot.trimmed(course.todayMg)) mg · \(detail)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            Button("Edit") {
                openDay(course.today)
            }
            .buttonStyle(SoftButtonStyle())
            .accessibilityLabel("Edit today's doses")
        }
        .accessibilityIdentifier("logged-today")
    }
}

// MARK: - Week

struct WeekCard: View {
    @Environment(AppStore.self) private var store
    let openDay: (String) -> Void

    var body: some View {
        let course = store.course
        let logged = course.loggedDays
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Last 7 days") {
                if course.streakDays > 1 {
                    Label("\(course.streakDays)-day streak", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warn)
                        .contentTransition(.numericText(value: Double(course.streakDays)))
                        .symbolEffect(.bounce, value: course.streakDays)
                        .transition(.blurReplace)
                }
            }
            .animation(Motion.spring, value: course.streakDays)

            HStack(spacing: 0) {
                ForEach((0..<7).reversed(), id: \.self) { offset in
                    let day = Day.adding(-offset, to: course.today)
                    DayDot(
                        day: day,
                        state: state(for: day, course: course, logged: logged),
                        isToday: offset == 0
                    ) {
                        openDay(day)
                    }
                    .frame(maxWidth: .infinity)
                    // The dots land one after another, oldest first.
                    .riseIn(8 + (6 - offset), distance: 10)
                }
            }
        }
        .card()
    }

    private func state(for day: String, course: CourseSnapshot, logged: Set<String>) -> DayDot.State {
        if logged.contains(day) { return .logged }
        if day == course.today { return .open }
        if let first = course.firstDay, day > first { return .missed }
        return .idle
    }
}

/// One day in the week strip: weekday letter above a tappable disc.
struct DayDot: View {
    enum State {
        case logged, missed, open, idle
    }

    let day: String
    let state: State
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        let date = Day.date(from: day)
        Button(action: action) {
            VStack(spacing: 6) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isToday ? Color.brand : Color.secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.display(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                    .frame(width: 38, height: 38)
                    .background { background }
                    // Pops when the day gets logged (or un-logged).
                    .pulse(on: state, amount: 1.22)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.spring, value: state)
        .accessibilityLabel("\(DateText.long(day)), \(accessibilityState)")
        .accessibilityHint("Opens that day's doses")
    }

    private var foreground: Color {
        switch state {
        case .logged: return .primary
        case .missed: return .warn
        case .open: return .primary
        case .idle: return .secondary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch state {
        case .logged:
            Circle().fill(Color.brand.opacity(0.30))
        case .missed:
            Circle().fill(Color.warn.opacity(0.14))
        case .open:
            Circle().strokeBorder(Color.brand, lineWidth: 2)
        case .idle:
            Circle().fill(Color.surfaceRaised)
        }
    }

    private var accessibilityState: String {
        switch state {
        case .logged: return "logged"
        case .missed: return "not logged"
        case .open: return "not logged yet"
        case .idle: return "before your first dose"
        }
    }
}

// MARK: - Up next

/// The care items that need attention soonest, each linking to the Care tab.
struct UpNextCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let course = store.course
        let overdue = store.overdueAppointments
        let next = store.upcomingAppointments.first
        let hasAnything = !overdue.isEmpty || next != nil || store.refill != nil

        VStack(alignment: .leading, spacing: 14) {
            CardHeader("Up next")

            if hasAnything {
                ForEach(overdue) { appointment in
                    row(symbol: appointment.kind.symbol, tint: .warn,
                        title: "\(appointment.kind.title) overdue",
                        detail: "Was \(DateText.short(appointment.day)) · mark it done or reschedule",
                        detailTint: .warn)
                }
                if let next {
                    row(symbol: next.kind.symbol, tint: .info,
                        title: next.kind.title,
                        detail: "\(DateText.short(next.day)) · \(DateText.relative(next.day, to: course.today))")
                }
                if let refill = store.refill, let days = course.refillDaysLeft {
                    row(symbol: "shippingbox.fill", tint: course.refillIsLow ? .warn : .good,
                        title: "\(refill.pillsLeft) \(refill.pillsLeft == 1 ? "pill" : "pills") left",
                        detail: course.refillIsLow
                            ? "About \(days) \(days == 1 ? "day" : "days") left · time to refill"
                            : "About \(days) days at your usual dose",
                        detailTint: course.refillIsLow ? .warn : nil)
                }
            } else {
                row(symbol: "calendar.badge.plus", tint: .info,
                    title: "Add your monthly appointments",
                    detail: "Track blood draws, derm visits and your pill supply")
            }
        }
        .card()
    }

    private func row(symbol: String, tint: Color, title: String, detail: String, detailTint: Color? = nil) -> some View {
        Button {
            router.tab = .care
        } label: {
            InfoRow(symbol: symbol, tint: tint, title: title, detail: detail, detailTint: detailTint) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Stats

struct StatsGrid: View {
    @Environment(AppStore.self) private var store

    private let columns = [
        GridItem(.flexible(), spacing: Metrics.spacing),
        GridItem(.flexible(), spacing: Metrics.spacing),
    ]

    var body: some View {
        let course = store.course
        LazyVGrid(columns: columns, spacing: Metrics.spacing) {
            StatTile(label: "Remaining",
                     value: course.goalReached ? "Done" : "\(CourseSnapshot.whole(course.remainingMg)) mg",
                     detail: "to reach your goal")

            StatTile(label: "Daily pace",
                     value: course.paceMgPerDay.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) mg" } ?? "—",
                     detail: "last \(CourseSnapshot.paceWindowDays) days")

            StatTile(label: "Est. finish",
                     value: finishValue(course),
                     detail: finishDetail(course))

            StatTile(label: "Consistency",
                     value: course.adherence.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                     detail: "of days logged")
        }
    }

    private func finishValue(_ course: CourseSnapshot) -> String {
        if course.goalReached { return "Reached" }
        guard let finish = course.estimatedFinishDay else { return "—" }
        return DateText.monthDay(finish, relativeTo: course.today)
    }

    private func finishDetail(_ course: CourseSnapshot) -> String {
        if course.goalReached { return "cumulative goal" }
        guard let days = course.daysUntilFinish else { return "log a dose to see it" }
        return days <= 0 ? "today" : "in \(days) \(days == 1 ? "day" : "days")"
    }
}
