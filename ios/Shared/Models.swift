import Foundation

// MARK: - Domain types

struct UserProfile: Codable, Equatable {
    var weightKg: Double
    var priorMg: Double
    var goalMgKg: Double
    /// When set, a fixed absolute goal in mg that overrides the mg/kg calculation.
    var goalTotalMg: Double?
    var startedDay: String? // "yyyy-MM-dd"
}

struct DoseEntry: Codable, Equatable, Identifiable {
    var id: String
    var day: String // "yyyy-MM-dd"
    var mgPerPill: Double
    var pillCount: Int
    /// The `DoseSlot` this entry ticked off, when it came from the schedule.
    /// The strength and count are copied in at logging time, so editing or
    /// deleting the slot later never changes history.
    var slotId: String? = nil

    var totalMg: Double { mgPerPill * Double(pillCount) }
    var date: Date { Day.date(from: day) }
}

/// One planned dose in the day — "60 mg with my first meal". An ordered list
/// of these is the dose schedule; each one is ticked off once a day.
struct DoseSlot: Codable, Equatable, Identifiable {
    var id: String
    /// What the dose is taken with or when: "First meal", "Bedtime".
    var label: String
    var mgPerPill: Double
    var pillCount: Int
    /// When to send a reminder, as minutes from midnight. `nil` = no reminder.
    var reminderMinutes: Int?

    var totalMg: Double { mgPerPill * Double(pillCount) }

    /// "8:00 AM" in the user's locale, when a reminder time is set.
    var reminderTimeText: String? {
        guard let minutes = reminderMinutes,
              let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                               second: 0, of: Date())
        else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// A recurring care appointment to keep up with while on isotretinoin —
/// a monthly blood draw or dermatology check-up. IsoTrack only tracks whether
/// it happened; it does not store results or give advice.
struct Appointment: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case bloodDraw
        case dermVisit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bloodDraw: return "Blood draw"
            case .dermVisit: return "Derm check-up"
            }
        }

        var symbol: String {
            switch self {
            case .bloodDraw: return "drop.fill"
            case .dermVisit: return "stethoscope"
            }
        }
    }

    var id: String
    var day: String // "yyyy-MM-dd" — the scheduled date
    var kind: Kind
    var attended: Bool

    var date: Date { Day.date(from: day) }

    /// Scheduled date has passed and it still hasn't been marked attended.
    var isOverdue: Bool { !attended && day < Day.today }
}

/// Refill tracking: pills on hand, decremented as doses are logged.
struct RefillInfo: Codable, Equatable {
    var pillsLeft: Int
    var boxSize: Int
}

/// A personal side-effect note for one day. Symptoms are keyed by a plain
/// string id (see `Symptom`) so unknown ids from a newer build survive a
/// round trip instead of breaking decoding.
struct CheckIn: Codable, Equatable, Identifiable {
    var id: String
    var day: String // "yyyy-MM-dd"
    /// Symptom id → severity (1 mild, 2 moderate, 3 severe). Absent = none.
    var symptoms: [String: Int]
    var note: String?

    var date: Date { Day.date(from: day) }
}

// MARK: - Day helpers

/// Day-granularity date helpers ("yyyy-MM-dd", fixed locale).
enum Day {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date {
        formatter.date(from: string) ?? Date()
    }

    static var today: String { string(from: Date()) }

    /// The day `offset` days away from `day`.
    static func adding(_ offset: Int, to day: String) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: date(from: day)) ?? date(from: day)
        return string(from: date)
    }

    /// Whole days from `start` to `end` (negative when `end` is earlier).
    static func distance(from start: String, to end: String) -> Int {
        Calendar.current.dateComponents([.day], from: date(from: start), to: date(from: end)).day ?? 0
    }
}

// MARK: - On-disk format

/// The app's on-disk and backup format.
///
/// **Compatibility contract:** every build since 1.0 reads and writes this
/// exact JSON shape at `SharedStore.dataURL`. Only ever add *optional* keys
/// here; never rename or remove one, or existing installs lose their data.
struct Backup: Codable {
    struct StoredProfile: Codable {
        var weightKg: Double
        var heightCm: Double? // legacy — no longer collected, kept for old backups
        var priorMg: Double
        var goalMgKg: Double
        var goalTotalMg: Double? // custom absolute goal
        var startedISO: String?
    }

    struct StoredEntry: Codable {
        var id: String
        var date: String
        var mg: Double
        var pills: Int
        var slot: String? // id of the scheduled dose it ticked off — added with dose schedules
    }

    var profile: StoredProfile?
    var entries: [StoredEntry]
    var refill: RefillInfo?
    var appointments: [Appointment]?
    var checkIns: [CheckIn]? // added in 2.0
    var schedule: [DoseSlot]? // added with dose schedules

    init(profile: UserProfile?, entries: [DoseEntry], refill: RefillInfo? = nil,
         appointments: [Appointment] = [], checkIns: [CheckIn] = [], schedule: [DoseSlot] = []) {
        self.refill = refill
        self.appointments = appointments
        self.checkIns = checkIns.isEmpty ? nil : checkIns
        self.schedule = schedule.isEmpty ? nil : schedule
        self.profile = profile.map {
            StoredProfile(weightKg: $0.weightKg, heightCm: nil,
                          priorMg: $0.priorMg, goalMgKg: $0.goalMgKg,
                          goalTotalMg: $0.goalTotalMg, startedISO: $0.startedDay)
        }
        self.entries = entries.map {
            StoredEntry(id: $0.id, date: $0.day, mg: $0.mgPerPill, pills: $0.pillCount, slot: $0.slotId)
        }
    }

    /// Tolerant decoding: the profile and dose entries are essential and must
    /// decode, but one malformed appointment, check-in or scheduled dose is
    /// skipped rather than making the whole file unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decodeIfPresent(StoredProfile.self, forKey: .profile)
        entries = try c.decodeIfPresent([StoredEntry].self, forKey: .entries) ?? []
        refill = try? c.decodeIfPresent(RefillInfo.self, forKey: .refill)
        appointments = (try? c.decodeIfPresent([Lossy<Appointment>].self, forKey: .appointments))?
            .compactMap(\.value)
        checkIns = (try? c.decodeIfPresent([Lossy<CheckIn>].self, forKey: .checkIns))?
            .compactMap(\.value)
        schedule = (try? c.decodeIfPresent([Lossy<DoseSlot>].self, forKey: .schedule))?
            .compactMap(\.value)
    }

    var domainProfile: UserProfile? {
        profile.map {
            UserProfile(weightKg: $0.weightKg,
                        priorMg: $0.priorMg, goalMgKg: $0.goalMgKg,
                        goalTotalMg: $0.goalTotalMg, startedDay: $0.startedISO)
        }
    }

    var domainEntries: [DoseEntry] {
        entries.map {
            DoseEntry(id: $0.id, day: $0.date, mgPerPill: $0.mg, pillCount: $0.pills, slotId: $0.slot)
        }
    }

    /// Scheduled doses that are usable (a positive strength and count).
    var domainSchedule: [DoseSlot] {
        (schedule ?? []).filter { $0.mgPerPill > 0 && $0.pillCount > 0 }
    }
}

/// Decodes to `nil` instead of throwing, so one bad array element is skipped.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
