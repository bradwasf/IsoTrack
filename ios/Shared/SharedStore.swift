import Foundation

/// Data location shared between the app and the widget extension via the
/// App Group container. Falls back to the app's Documents folder when the
/// group container is unavailable (e.g. entitlement not provisioned yet).
///
/// The group id and file name are part of the persistence contract — changing
/// either one orphans the data on existing installs. The group id is
/// `group.<app bundle id>`, written into both targets' Info.plist from
/// `ISOTRACK_BUNDLE_ID` (see `Config/IsoTrack.xcconfig`).
enum SharedStore {
    static let appGroupId: String = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "IsoTrackAppGroup") as? String,
              !id.isEmpty, !id.contains("$(") else {
            preconditionFailure("IsoTrackAppGroup is missing from Info.plist; regenerate the project with xcodegen")
        }
        return id
    }()
    static let fileName = "isotrack-data.json"

    static var dataURL: URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            return container.appendingPathComponent(fileName)
        }
        return legacyDocumentsURL
    }

    /// Where 1.0 builds kept the data before the App Group existed.
    static var legacyDocumentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// A once-a-day copy of the last good data file, kept beside it.
    static func snapshotURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("backup.json")
    }

    enum ReadResult {
        case missing
        case loaded(Backup)
        /// The file exists but couldn't be decoded.
        case unreadable
    }

    static func read(at url: URL = dataURL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url),
              let backup = try? JSONDecoder().decode(Backup.self, from: data)
        else { return .unreadable }
        return .loaded(backup)
    }

    static func loadBackup(at url: URL = dataURL) -> Backup? {
        if case .loaded(let backup) = read(at: url) { return backup }
        return nil
    }

    /// Atomically replaces the data file. Before the first write of each day
    /// the current file is copied to the snapshot, so a bad write can never
    /// cost more than a day of history.
    @discardableResult
    static func write(_ backup: Backup, to url: URL = dataURL) -> Bool {
        guard let data = try? JSONEncoder().encode(backup) else { return false }
        refreshSnapshotIfNeeded(for: url)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    private static func refreshSnapshotIfNeeded(for url: URL) {
        let fm = FileManager.default
        let snapshot = snapshotURL(for: url)
        if let modified = (try? fm.attributesOfItem(atPath: snapshot.path))?[.modificationDate] as? Date,
           Calendar.current.isDateInToday(modified) {
            return
        }
        // Only snapshot a file that is healthy and actually holds a course.
        guard case .loaded(let current) = read(at: url), current.profile != nil,
              let data = try? Data(contentsOf: url) else { return }
        try? data.write(to: snapshot, options: .atomic)
    }

    /// Removes the data file and its snapshot (used by "erase all").
    static func removeAll(at url: URL = dataURL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: snapshotURL(for: url))
    }
}
