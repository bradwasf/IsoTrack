# Contributing to IsoTrack

Thanks for helping out. Bug reports, fixes and small focused features are all
welcome.

## Getting set up

1. Install Xcode 27.1+ and XcodeGen (`brew install xcodegen`).
2. `cd ios && xcodegen generate && open IsoTrack.xcodeproj`
3. Run in the Simulator. For a device, copy `ios/Config/Local.xcconfig.example`
   to `ios/Config/Local.xcconfig` and set your own team and bundle id. That
   file is git-ignored, so your signing details never end up in a commit.

Handy launch arguments (Scheme → Run → Arguments): `--demo-data`,
`--demo-schedule`, `--uitest-reset`, `--tab journey|care`. They use a
temporary data file and never touch real data.

## Ground rules

- **Don't break existing data.** The JSON file name, the App Group and the JSON
  keys are a compatibility contract (see "Your data" in `ios/README.md`). New
  fields must be optional. `IsoTrackTests/PersistenceTests.swift` must keep
  passing, including the 1.0 data file fixture.
- **No network, accounts, analytics or third-party SDKs.** Health data stays on
  the device.
- **Not medical advice.** Don't add dosing recommendations. The app records
  and adds up what the user's dermatologist prescribed.
- Edit `ios/project.yml` rather than the generated `.xcodeproj`, then run
  `xcodegen generate` and commit both.
- Never commit real health data, a `Local.xcconfig`, or your own Team ID.

## Pull requests

- Keep each PR to one change and explain the why in the description.
- Run the unit tests (`IsoTrackTests`) before opening it; CI runs them too.
- For UI changes, include a before/after screenshot, closed and open on iPhone
  Duo if you can.
