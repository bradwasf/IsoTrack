import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ProgressEntry: TimelineEntry {
    let date: Date
    /// `nil` until the course has been set up in the app.
    let course: CourseSnapshot?

    static var placeholder: ProgressEntry {
        let today = Day.today
        let profile = UserProfile(weightKg: 72.5, priorMg: 3960, goalMgKg: 150, goalTotalMg: nil, startedDay: nil)
        let entry = DoseEntry(id: "placeholder", day: today, mgPerPill: 40, pillCount: 2)
        return ProgressEntry(date: .now, course: CourseSnapshot(
            profile: profile, entries: [entry], refill: RefillInfo(pillsLeft: 56, boxSize: 60), today: today
        ))
    }

    static func current() -> ProgressEntry {
        guard let backup = SharedStore.loadBackup(), backup.profile != nil else {
            return ProgressEntry(date: .now, course: nil)
        }
        return ProgressEntry(date: .now, course: CourseSnapshot(backup: backup))
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        let entry = ProgressEntry.current()
        completion(entry.course == nil ? .placeholder : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        // Refresh at midnight so "logged today" resets; the app also reloads
        // timelines on every data change.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        let midnight = Calendar.current.startOfDay(for: tomorrow)
        completion(Timeline(entries: [.current()], policy: .after(midnight)))
    }
}

// MARK: - Views

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProgressEntry

    var body: some View {
        if let course = entry.course {
            switch family {
            case .accessoryCircular: circular(course)
            case .accessoryRectangular: rectangular(course)
            case .accessoryInline: inline(course)
            case .systemMedium: medium(course)
            default: small(course)
            }
        } else {
            switch family {
            case .accessoryCircular, .accessoryInline:
                Image(systemName: "pills.fill")
            default:
                VStack(spacing: 6) {
                    Image(systemName: "pills.fill")
                        .font(.title2)
                        .foregroundStyle(Color.brand)
                    Text("Open IsoTrack to set up your course")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func percent(_ course: CourseSnapshot) -> Int {
        Int((course.progress * 100).rounded(.down))
    }

    private func small(_ course: CourseSnapshot) -> some View {
        VStack(spacing: 8) {
            ZStack {
                ProgressRing(progress: course.progress, lineWidth: 9, track: Color.primary.opacity(0.1))
                VStack(spacing: -1) {
                    Text("\(percent(course))%")
                        .font(.system(size: 22, weight: .semibold))
                        .minimumScaleFactor(0.7)
                    Text("\(shortMg(course.cumulativeMg)) mg")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
            }
            status(course, compact: true)
        }
    }

    private func medium(_ course: CourseSnapshot) -> some View {
        HStack(spacing: 16) {
            ZStack {
                ProgressRing(progress: course.progress, lineWidth: 11, track: Color.primary.opacity(0.1))
                Text("\(percent(course))%")
                    .font(.system(size: 22, weight: .semibold))
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(CourseSnapshot.whole(course.cumulativeMg)) mg")
                    .font(.system(.title3, weight: .semibold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("of \(CourseSnapshot.whole(course.goalMg)) mg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let refill = course.refill, let days = course.refillDaysLeft {
                    Label("\(refill.pillsLeft) left · \(days) d", systemImage: "shippingbox.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(course.refillIsLow ? Color.warn : Color.secondary)
                } else if let days = course.daysUntilFinish, days > 0 {
                    Label("\(days) days to go", systemImage: "flag.checkered")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                status(course, compact: false)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func status(_ course: CourseSnapshot, compact: Bool) -> some View {
        if course.todayComplete {
            Label("Logged today", systemImage: "checkmark.circle.fill")
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(Color.good)
                .lineLimit(1)
        } else if course.goalReached {
            Label("Goal reached", systemImage: "checkmark.seal.fill")
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(Color.good)
                .lineLimit(1)
        } else {
            Button(intent: LogUsualDoseIntent()) {
                // With a schedule this is the next dose still to tick off.
                Label("Log \(CourseSnapshot.trimmed(course.nextDoseMg)) mg", systemImage: "pills.fill")
                    .font(.system(size: compact ? 11 : 12, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, compact ? 10 : 12)
                    .padding(.vertical, compact ? 5 : 6)
                    .foregroundStyle(Color.onBrand)
                    .background(Color.brand, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func circular(_ course: CourseSnapshot) -> some View {
        Gauge(value: course.progress) {
            Image(systemName: "pills.fill")
        } currentValueLabel: {
            Text("\(percent(course))%")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func rectangular(_ course: CourseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("IsoTrack · \(percent(course))%", systemImage: "pills.fill")
                .font(.headline)
            Text("\(CourseSnapshot.whole(course.cumulativeMg)) of \(shortMg(course.goalMg)) mg")
            Text(todayStatus(course).capitalizedFirst)
                .foregroundStyle(.secondary)
            Gauge(value: course.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ course: CourseSnapshot) -> some View {
        Label("\(percent(course))% · \(todayStatus(course))", systemImage: "pills.fill")
    }

    /// "logged today", "1 of 2 logged" (part-way through a schedule), or
    /// "not logged yet".
    private func todayStatus(_ course: CourseSnapshot) -> String {
        if course.todayComplete { return "logged today" }
        let taken = course.takenSlotCount(on: course.today)
        if course.hasSchedule, taken > 0 { return "\(taken) of \(course.schedule.count) logged" }
        return "not logged yet"
    }

    /// "17.7k", "800"
    private func shortMg(_ value: Double) -> String {
        guard value >= 10_000 else { return CourseSnapshot.whole(value) }
        return String(format: "%.1fk", value / 1000).replacingOccurrences(of: ".0k", with: "k")
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Widget

struct IsoTrackWidget: Widget {
    var body: some WidgetConfiguration {
        // The kind is part of the contract with widgets already on the Home
        // Screen — keep it stable.
        StaticConfiguration(kind: "IsoTrackProgress", provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.surface
                }
        }
        .configurationDisplayName("Course progress")
        .description("Your cumulative isotretinoin dose, with one-tap logging of your next dose.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct IsoTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        IsoTrackWidget()
    }
}
