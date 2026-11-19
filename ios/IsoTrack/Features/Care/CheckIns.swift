import SwiftUI

/// The side effects the journal offers. Ids are stored in the data file, so
/// never rename one — add new ones instead.
struct Symptom: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String

    static let all: [Symptom] = [
        Symptom(id: "dryLips", title: "Dry lips", symbol: "mouth.fill"),
        Symptom(id: "drySkin", title: "Dry skin", symbol: "hand.raised.fill"),
        Symptom(id: "dryEyes", title: "Dry eyes", symbol: "eye.fill"),
        Symptom(id: "nosebleeds", title: "Nosebleeds", symbol: "nose.fill"),
        Symptom(id: "aches", title: "Joint or muscle aches", symbol: "figure.walk"),
        Symptom(id: "headache", title: "Headache", symbol: "brain.head.profile"),
        Symptom(id: "sunSensitivity", title: "Sun sensitivity", symbol: "sun.max.fill"),
        Symptom(id: "fatigue", title: "Fatigue", symbol: "zzz"),
        Symptom(id: "lowMood", title: "Low mood", symbol: "cloud.rain.fill"),
    ]

    static func title(for id: String) -> String {
        all.first { $0.id == id }?.title ?? id
    }

    static func severityLabel(_ severity: Int) -> String {
        switch severity {
        case 1: return "Mild"
        case 2: return "Moderate"
        case 3: return "Severe"
        default: return "None"
        }
    }

    /// Symptoms of a check-in in catalogue order, worst first within a tie.
    static func sorted(_ symptoms: [String: Int]) -> [(id: String, severity: Int)] {
        let order = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.id, $0) })
        return symptoms
            .filter { $0.value > 0 }
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return (order[$0.key] ?? .max) < (order[$1.key] ?? .max)
            }
            .map { ($0.key, $0.value) }
    }
}

// MARK: - Card

struct CheckInCard: View {
    @Environment(AppStore.self) private var store
    let open: (String) -> Void

    var body: some View {
        let today = store.today
        let todays = store.checkIn(on: today)
        let recent = Array(store.checkIns.reversed().prefix(3))

        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Side-effect journal") {
                if store.checkIns.count > 3 {
                    NavigationLink {
                        CheckInListView(open: open)
                    } label: {
                        Text("All \(store.checkIns.count)")
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            InfoRow(symbol: "heart.text.square.fill", tint: .brand,
                    title: todays == nil ? "How are you feeling today?" : "Checked in today",
                    detail: todays == nil
                        ? "A ten-second note so you remember what to tell your dermatologist."
                        : summary(todays)) {
                Button(todays == nil ? "Check in" : "Edit") {
                    open(today)
                }
                .buttonStyle(SoftButtonStyle())
            }

            if !recent.isEmpty {
                Rectangle().fill(Color.hairline).frame(height: 1)
                ForEach(recent) { checkIn in
                    Button {
                        open(checkIn.day)
                    } label: {
                        CheckInRow(checkIn: checkIn, today: today)
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            Rectangle().fill(Color.hairline).frame(height: 1)

            ShareLink(item: VisitSummary.text(store: store)) {
                Label("Share a visit summary", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SoftButtonStyle())

            Text("Your doses and notes in plain text, ready to show at your next appointment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func summary(_ checkIn: CheckIn?) -> String {
        guard let checkIn else { return "" }
        return CheckInRow.summary(checkIn)
    }
}

struct CheckInRow: View {
    let checkIn: CheckIn
    let today: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(checkIn.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(checkIn.date.formatted(.dateTime.day()))
                    .font(.display(.headline))
            }
            .frame(width: 38, height: 38)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.summary(checkIn))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let note = checkIn.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Dry lips (moderate), dry skin (mild)"
    static func summary(_ checkIn: CheckIn) -> String {
        let parts = Symptom.sorted(checkIn.symptoms).map {
            "\(Symptom.title(for: $0.id)) (\(Symptom.severityLabel($0.severity).lowercased()))"
        }
        return parts.isEmpty ? "Note only" : parts.joined(separator: ", ")
    }
}

/// Every check-in, newest first.
struct CheckInListView: View {
    @Environment(AppStore.self) private var store
    let open: (String) -> Void

    var body: some View {
        List {
            ForEach(store.checkIns.reversed()) { checkIn in
                Button {
                    open(checkIn.day)
                } label: {
                    CheckInRow(checkIn: checkIn, today: store.today)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.deleteCheckIn(checkIn)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle("Side-effect journal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sheet

struct CheckInSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let day: String
    @State private var symptoms: [String: Int] = [:]
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Symptom.all) { symptom in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(symptom.title, systemImage: symptom.symbol)
                                .font(.subheadline.weight(.semibold))
                            Picker(symptom.title, selection: severity(for: symptom.id)) {
                                ForEach(0..<4) { level in
                                    Text(Symptom.severityLabel(level)).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(day == store.today ? "Today" : DateText.long(day))
                }

                Section("Note") {
                    TextField("Anything to mention at your next visit?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    if let existing = store.checkIn(on: day) {
                        Button("Delete this check-in", role: .destructive) {
                            store.deleteCheckIn(existing)
                            dismiss()
                        }
                    }
                } footer: {
                    Text("This journal is for your own records and isn't medical advice. If a symptom worries you, contact your prescriber.")
                }
            }
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveCheckIn(day: day, symptoms: symptoms, note: note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationSizing(.form)
        .onAppear {
            if let existing = store.checkIn(on: day) {
                symptoms = existing.symptoms
                note = existing.note ?? ""
            }
        }
    }

    private func severity(for id: String) -> Binding<Int> {
        Binding(
            get: { symptoms[id] ?? 0 },
            set: { symptoms[id] = $0 == 0 ? nil : $0 }
        )
    }
}

// MARK: - Visit summary

/// A plain-text recap to share with a dermatologist: where the course
/// stands, how the last month went, and what was noted in the journal.
enum VisitSummary {
    static func text(store: AppStore) -> String {
        let course = store.course
        let today = course.today
        // Report since the last derm visit, or the last 30 days.
        let lastVisit = store.attendedAppointments.first { $0.kind == .dermVisit && $0.day < today }?.day
        let since = lastVisit ?? Day.adding(-30, to: today)
        let windowStart = max(since, course.firstDay ?? since)

        let windowEntries = course.entries.filter { $0.day >= windowStart && $0.day <= today }
        let windowMg = windowEntries.reduce(0) { $0 + $1.totalMg }
        let windowDays = max(1, Day.distance(from: windowStart, to: today) + 1)
        let loggedDays = Set(windowEntries.map(\.day)).count

        var lines: [String] = []
        lines.append("IsoTrack summary · \(DateText.long(today))")
        lines.append("")
        lines.append("COURSE")
        lines.append("Cumulative dose: \(CourseSnapshot.whole(course.cumulativeMg)) of \(CourseSnapshot.whole(course.goalMg)) mg (\(Int((course.progress * 100).rounded(.down)))%)")
        lines.append("Per kg: \(course.mgPerKg.formatted(.number.precision(.fractionLength(1)))) of \(CourseSnapshot.whole(course.goalMgPerKg)) mg/kg")
        if course.hasSchedule {
            let parts = course.schedule.map { "\(CourseSnapshot.trimmed($0.totalMg)) mg \($0.label.lowercased())" }
            lines.append("Current dose: \(CourseSnapshot.trimmed(course.scheduledMg)) mg a day (\(parts.joined(separator: ", ")))")
        } else if !course.entries.isEmpty {
            lines.append("Current dose: \(CourseSnapshot.doseLabel(mgPerPill: course.usualDose.mgPerPill, pillCount: course.usualDose.pillCount)) a day")
        }
        if let finish = course.estimatedFinishDay, !course.goalReached {
            lines.append("Estimated finish at current pace: \(DateText.monthDay(finish, relativeTo: today))")
        }

        lines.append("")
        lines.append(lastVisit == nil ? "LAST 30 DAYS" : "SINCE LAST DERM VISIT (\(DateText.monthDay(since, relativeTo: today)))")
        lines.append("Doses logged on \(loggedDays) of \(windowDays) days, \(CourseSnapshot.whole(windowMg)) mg in total")

        let checkIns = store.checkIns.filter { $0.day >= since && $0.day <= today }
        if !checkIns.isEmpty {
            lines.append("")
            lines.append("SIDE EFFECTS NOTED (\(checkIns.count) check-in\(checkIns.count == 1 ? "" : "s"))")
            var counts: [String: (days: Int, worst: Int)] = [:]
            for checkIn in checkIns {
                for (id, severity) in checkIn.symptoms where severity > 0 {
                    let current = counts[id] ?? (0, 0)
                    counts[id] = (current.days + 1, max(current.worst, severity))
                }
            }
            for symptom in Symptom.all {
                guard let count = counts[symptom.id] else { continue }
                lines.append("- \(symptom.title): \(count.days) day\(count.days == 1 ? "" : "s"), up to \(Symptom.severityLabel(count.worst).lowercased())")
            }
            let notes = checkIns.compactMap { checkIn in checkIn.note.map { "- \(DateText.monthDay(checkIn.day, relativeTo: today)): \($0)" } }
            if !notes.isEmpty {
                lines.append("")
                lines.append("NOTES")
                lines.append(contentsOf: notes)
            }
        }

        lines.append("")
        lines.append("Self-recorded in IsoTrack. Not a medical record.")
        return lines.joined(separator: "\n")
    }
}
