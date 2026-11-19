# IsoTrack

[![CI](https://github.com/bradwasf/IsoTrack/actions/workflows/ci.yml/badge.svg)](https://github.com/bradwasf/IsoTrack/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An isotretinoin cumulative-dose tracker for iPhone, written in SwiftUI and
laid out for iPhone Duo: one column when the phone is closed, two fold-aware
panes when it's open.

- **Today**: progress ring, one-tap dose logging (or a tick box per dose if you
  split your day into a schedule), the last 7 days, what's next.
- **Journey**: cumulative chart with a projection to your goal, calendar,
  milestones and full history.
- **Care**: appointments, pill supply, a side-effect journal and a shareable
  summary for your dermatologist.
- Home and lock screen widgets, Siri / Shortcuts, and a daily reminder.

**Private by design.** Everything is stored on the device in one JSON file.
There is no account, no server, no analytics and no network access.

> [!IMPORTANT]
> IsoTrack is a personal tracking tool, not a medical device, and nothing in it
> is medical advice. Your dose, goal and schedule come from your dermatologist.
> Follow their plan.

## Build

Requires Xcode 27.1 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
cd ios
xcodegen generate     # only needed after changing project.yml
open IsoTrack.xcodeproj
```

It runs in the Simulator straight away. To install it on your own iPhone, set
your Apple team and a bundle id of your own:

```sh
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig
# then edit DEVELOPMENT_TEAM and ISOTRACK_BUNDLE_ID
```

[`ios/README.md`](ios/README.md) covers device and TestFlight builds, how the
data file stays compatible between versions, the iPhone Duo layout, and the
project structure.

## Tests

```sh
cd ios
xcodebuild test -project IsoTrack.xcodeproj -scheme IsoTrack \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:IsoTrackTests
```

`IsoTrackTests` covers the course maths and the on-disk data format.
`IsoTrackUITests` drives the app end to end against a throwaway data file.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
