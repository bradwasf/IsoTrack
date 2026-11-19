# IsoTrack — native iOS app (SwiftUI)

Isotretinoin cumulative-dose tracker for iPhone, built to feel at home on
iPhone Duo: one column when the phone is closed, two fold-aware panes when
it's open.

## What it does

- **Today** — progress ring, cumulative mg and mg/kg, a one-tap "log my usual
  dose" button, the last 7 days, what's up next, and four key stats (remaining,
  daily pace, estimated finish, consistency).
- **Dose schedule** (optional) — split the day into separate doses, e.g. 60 mg
  with your first meal and 30 mg with your second. Today then shows a tick box
  per dose instead of the single button; each can have its own reminder time.
  Set it up from "Split dose" on the Today card or in Settings.
- **Journey** — cumulative curve with a dashed projection to your goal, a month
  calendar (tap any day to add or remove doses), milestones, and full history.
- **Care** — monthly blood draws and derm check-ups with overdue nudges, pill
  supply with a low-stock warning, and a side-effect journal. "Share a visit
  summary" exports doses and notes as plain text for your dermatologist.
- **Widget** (small, medium, lock screen) with a log button, **Siri /
  Shortcuts** ("Log my dose in IsoTrack"), and a **daily reminder** whose
  notification logs your usual dose in one tap. With a dose schedule, all
  three log the next dose still due.
- **Backups** — export and restore a JSON backup from Settings.

## Your data

Everything lives in one JSON file, `isotrack-data.json`, in the App Group
container `group.<bundle id>` (shared with the widget). **The file name, the
App Group, the bundle id and the JSON keys are a compatibility contract** —
every build since 1.0 reads and writes the same shape, so installing a new
build over an old one keeps all your history, as long as you build with the
same bundle id.

- Install new builds **over** the existing app. Deleting the app deletes its
  data (export a backup first if you ever need to).
- New fields are only ever added as optional keys (`checkIns` arrived in 2.0;
  `schedule` and an entry's `slot` came with dose schedules).
- Safety nets: writes are atomic, the last good file is snapshotted once a day
  (`isotrack-data.backup.json`), and a file that can't be read is set aside
  rather than overwritten.
- `IsoTrackTests/PersistenceTests.swift` pins all of this down, including a
  byte-for-byte 1.0 data file.

## iPhone Duo

- Layout follows size classes, never orientation or screen size.
- Open flat, Today is an `ArrangementView` (course on one side, details on the
  other) and Journey/Care use two columns; in both, the gap sits exactly on the
  fold (`FoldSplit` in `Design/Theme.swift` reads the fold from reserved
  regions).
- All orientations are supported so the outer display works propped in
  landscape.
- Opening the phone replays the ring animation (`onHingeChange`).

## Requirements

- **Xcode 27.1 or newer** (for the iPhone Duo layout APIs) — free from the Mac App Store (~15 GB)
- iOS 18+ on your iPhone
- Nothing else for the Simulator; a free Apple ID to run on your own iPhone
- For TestFlight: an [Apple Developer Program](https://developer.apple.com/programs/enroll/) membership ($99/year)

## Build & run on your iPhone (first time)

1. Install Xcode from the Mac App Store, launch it once, and let it install its components.
2. Open `IsoTrack.xcodeproj`.
3. Xcode → Settings → Accounts → add your Apple ID.
4. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set
   `DEVELOPMENT_TEAM` to your Team ID and `ISOTRACK_BUNDLE_ID` to a bundle id
   of your own (e.g. `com.yourname.isotrack`). The file is git-ignored. The
   widget, tests and App Group ids are all derived from it. Keep it the same
   once installed, because it decides where your data lives.
5. Plug in your iPhone (enable Developer Mode on the phone when prompted:
   Settings → Privacy & Security → Developer Mode).
6. Select your phone in the device dropdown and press **Run** (⌘R).

Free Apple ID note: apps signed with a free account stop launching after
7 days — re-run from Xcode to refresh. TestFlight (below) avoids this.

## Put it on TestFlight

1. Enroll in the Apple Developer Program and wait for approval.
2. In [App Store Connect](https://appstoreconnect.apple.com) → *My Apps* → **+** →
   *New App*: platform iOS, bundle ID = your `ISOTRACK_BUNDLE_ID`, any SKU.
3. In Xcode: select **Any iOS Device (arm64)** as the destination →
   *Product → Archive*.
4. When the Organizer opens: **Distribute App** → **TestFlight & App Store** → upload.
5. In App Store Connect → your app → *TestFlight*: the build appears after
   processing (~10 min). Add yourself as an internal tester.
6. Install the **TestFlight** app on your iPhone, accept the invite, and download.

TestFlight builds expire after **90 days** — repeat steps 3–4 to refresh
(bump the build number in `project.yml` → `CURRENT_PROJECT_VERSION`, run
`xcodegen generate`, or just edit it in Xcode).

## Project structure

The `.xcodeproj` is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
After adding or removing files, run `xcodegen generate` in this folder.

| Path | What it is |
|---|---|
| `Shared/Models.swift` | Data types and the on-disk format |
| `Shared/SharedStore.swift` | Where the file lives; safe reads and writes |
| `Shared/CourseMath.swift` | Every derived number (progress, pace, finish, milestones) |
| `Shared/Palette.swift` | Colours and the progress ring, shared with the widget |
| `IsoTrack/App/` | App entry, `AppStore`, reminders, Siri shortcuts, tab shell |
| `IsoTrack/Design/` | Theme, components, motion, confetti |
| `IsoTrack/Features/` | Today, Schedule, Journey, Care, Settings, Onboarding |
| `IsoTrackWidget/` | WidgetKit extension |
| `IsoTrackTests/` | Unit tests: data compatibility and course maths |
| `IsoTrackUITests/` | End-to-end tests (run against a throwaway file, never real data) |
| `Config/` | Team and bundle id (`IsoTrack.xcconfig`, your overrides in `Local.xcconfig`) |

Launch arguments for development: `--demo-data` starts with a sample
mid-course data set, `--demo-schedule` is the same with a two-dose schedule,
`--uitest-reset` starts empty, and `--tab journey|care` opens a tab. The data
modes use a temporary file and leave real data alone.

Build note: if you ever build from the command line, keep `-derivedDataPath`
**outside** `~/Documents` — iCloud Drive stamps Finder metadata on synced files,
which makes the final CodeSign step fail with "resource fork, Finder
information, or similar detritus not allowed". Xcode's default DerivedData
location (`~/Library/Developer/Xcode/DerivedData`) is safe, so normal ⌘R
builds are unaffected.

> Personal tracking only — not medical advice. Follow your dermatologist's plan.
