import Foundation
import UserNotifications

/// Schedules dose reminders and their one-tap "log it" action. Notifications
/// are scheduled individually for the next two weeks (refreshed on every data
/// change and app activation) so a reminder can be skipped once its dose is
/// logged.
///
/// Without a dose schedule there is one daily reminder at the time chosen in
/// Settings. With a schedule, every scheduled dose that has a reminder time
/// gets its own notification, and those replace the daily one.
final class ReminderManager {
    static let shared = ReminderManager()

    static let categoryId = "DOSE_REMINDER"
    static let logActionId = "LOG_USUAL"
    /// `userInfo` keys on a scheduled dose's reminder.
    static let slotKey = "slot"
    static let dayKey = "day"
    private static let idPrefix = "isotrack.reminder."
    /// iOS keeps at most 64 pending notifications per app; stay well under.
    private static let doseReminderBudget = 48

    private static let enabledKey = "reminder.enabled"
    private static let minutesKey = "reminder.minutes"

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// Reminder time as minutes from midnight (default 9:00 AM).
    var minutesFromMidnight: Int {
        get { UserDefaults.standard.object(forKey: Self.minutesKey) as? Int ?? 9 * 60 }
        set { UserDefaults.standard.set(newValue, forKey: Self.minutesKey) }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func reschedule(course: CourseSnapshot, appointments: [Appointment] = []) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            self.scheduleRefillNudge(center: center, daysLeft: course.refillDaysLeft)
            self.scheduleAppointmentFollowups(center: center, appointments: appointments)

            let timedSlots = course.schedule.filter { $0.reminderMinutes != nil }
            if !timedSlots.isEmpty {
                self.scheduleSlotReminders(center: center, slots: timedSlots, course: course)
            } else if self.enabled {
                self.scheduleDailyReminder(center: center, course: course)
            }
        }
    }

    private static func doseText(mgPerPill: Double, pillCount: Int) -> String {
        let total = CourseSnapshot.trimmed(mgPerPill * Double(pillCount))
        return "\(total) mg (\(CourseSnapshot.doseLabel(mgPerPill: mgPerPill, pillCount: pillCount)))"
    }

    private static func category(id: String, logTitle: String) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: id,
            actions: [UNNotificationAction(identifier: logActionId, title: logTitle, options: [])],
            intentIdentifiers: []
        )
    }

    /// The next `days` fire dates at `minutes` past midnight that are still
    /// in the future, each with its day offset from today.
    private func upcomingFireDates(minutes: Int, days: Int) -> [(offset: Int, comps: DateComponents, date: Date)] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = minutes / 60
            comps.minute = minutes % 60
            guard let fireDate = calendar.date(from: comps), fireDate > now else { return nil }
            return (offset, comps, fireDate)
        }
    }

    /// The single daily reminder, skipped today once today's dosing is done.
    private func scheduleDailyReminder(center: UNUserNotificationCenter, course: CourseSnapshot) {
        // With a schedule (but no per-dose times) the action ticks off
        // whichever dose is next, so don't promise a specific amount.
        let doseText = Self.doseText(mgPerPill: course.usualDose.mgPerPill, pillCount: course.usualDose.pillCount)
        center.setNotificationCategories([
            Self.category(id: Self.categoryId,
                          logTitle: course.hasSchedule ? "Log my next dose" : "Log \(doseText)")
        ])

        for fire in upcomingFireDates(minutes: minutesFromMidnight, days: 14) {
            if fire.offset == 0 && course.todayComplete { continue }

            let content = UNMutableNotificationContent()
            content.title = "Time for your dose"
            content.body = course.hasSchedule
                ? "Tick off your next dose with one tap."
                : "Your usual is \(doseText). Log it with one tap."
            content.sound = .default
            content.categoryIdentifier = Self.categoryId

            center.add(UNNotificationRequest(
                identifier: Self.idPrefix + Day.string(from: fire.date),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: fire.comps, repeats: false)
            ))
        }
    }

    /// One reminder per scheduled dose per day, each with an action that
    /// ticks off that exact dose. Today's is skipped once it's been taken.
    private func scheduleSlotReminders(center: UNUserNotificationCenter, slots: [DoseSlot], course: CourseSnapshot) {
        center.setNotificationCategories(Set(slots.map { slot in
            Self.category(id: Self.categoryId + "." + slot.id,
                          logTitle: "Log \(Self.doseText(mgPerPill: slot.mgPerPill, pillCount: slot.pillCount))")
        }))

        let days = max(3, min(14, Self.doseReminderBudget / slots.count))
        for slot in slots {
            guard let minutes = slot.reminderMinutes else { continue }
            for fire in upcomingFireDates(minutes: minutes, days: days) {
                if fire.offset == 0 && (course.isTaken(slot, on: course.today) || course.todayComplete) { continue }
                let day = Day.string(from: fire.date)

                let content = UNMutableNotificationContent()
                content.title = "\(slot.label) dose"
                content.body = "\(Self.doseText(mgPerPill: slot.mgPerPill, pillCount: slot.pillCount)). Tick it off with one tap."
                content.sound = .default
                content.categoryIdentifier = Self.categoryId + "." + slot.id
                content.userInfo = [Self.slotKey: slot.id, Self.dayKey: day]

                center.add(UNNotificationRequest(
                    identifier: Self.idPrefix + day + "." + slot.id,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: fire.comps, repeats: false)
                ))
            }
        }
    }

    /// One heads-up notification about a day before pills run out.
    /// Scheduled independently of the daily-reminder toggle (delivered only
    /// if notification permission has been granted).
    private func scheduleRefillNudge(center: UNUserNotificationCenter, daysLeft: Int?) {
        guard let daysLeft else { return }

        let calendar = Calendar.current
        let now = Date()
        guard let nudgeDay = calendar.date(byAdding: .day, value: max(0, daysLeft - 1), to: now) else { return }
        var comps = calendar.dateComponents([.year, .month, .day], from: nudgeDay)
        comps.hour = minutesFromMidnight / 60
        comps.minute = minutesFromMidnight % 60
        guard let fireDate = calendar.date(from: comps), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Refill soon"
        content.body = daysLeft <= 1
            ? "You're about to run out of pills — pick up your refill."
            : "About a day of pills left after today — time to arrange your refill."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.idPrefix + "refill",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        center.add(request)
    }

    /// For each unattended appointment, a nudge the morning *after* its
    /// scheduled date so a missed blood draw or derm visit gets marked done
    /// or rescheduled. Scheduled independently of the daily-reminder toggle
    /// (delivered only if notification permission has been granted).
    private func scheduleAppointmentFollowups(center: UNUserNotificationCenter, appointments: [Appointment]) {
        let calendar = Calendar.current
        let now = Date()

        for appointment in appointments where !appointment.attended {
            guard let followupDay = calendar.date(byAdding: .day, value: 1, to: appointment.date) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: followupDay)
            comps.hour = minutesFromMidnight / 60
            comps.minute = minutesFromMidnight % 60
            guard let fireDate = calendar.date(from: comps), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(appointment.kind.title) follow-up"
            content.body = "Did you go for your \(appointment.kind.title.lowercased())? Mark it done or reschedule it."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: Self.idPrefix + "appt." + appointment.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            center.add(request)
        }
    }
}

/// Routes notification taps and the one-tap log action into the store.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    private let store: AppStore

    init(store: AppStore) {
        self.store = store
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == ReminderManager.logActionId {
            let info = response.notification.request.content.userInfo
            let slotId = info[ReminderManager.slotKey] as? String
            let day = info[ReminderManager.dayKey] as? String
            DispatchQueue.main.async {
                // Re-read first so a dose logged from the widget isn't lost.
                self.store.load()
                if let slot = self.store.schedule.first(where: { $0.id == slotId }) {
                    // A scheduled dose's reminder ticks off that dose, on
                    // the day it was for.
                    self.store.setTaken(true, slot: slot, day: day)
                } else {
                    self.store.logNextDose()
                }
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
