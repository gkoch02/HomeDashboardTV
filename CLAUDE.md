# CLAUDE.md

tvOS companion to the HomeDashboard Pi, plus the same layouts as a Mac screensaver. The
README is the full reference (architecture under **Layout**, how to add one under **Adding a
layout**); this file holds only what every session needs.

## Project generation

- `project.yml` is the source of truth; the `.xcodeproj` and `HomeDashboardTV/Info.plist` are
  XcodeGen output, committed so clones and Xcode Cloud build without XcodeGen. After editing
  `project.yml` or adding a source file, run `xcodegen` and commit the result.
  `Tools/check_project_sync.sh` is CI's check that they agree.
- Build settings go in `project.yml`, never in Xcode's UI: the next `xcodegen` wipes UI edits.
- CI pins XcodeGen 2.46.0; a different version can regenerate differently and fail the sync check.

## Build and test

```bash
(cd Packages/DashboardCore && swift test)        # the only tests CI runs; no UI
xcodebuild -scheme HomeDashboard -configuration Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -derivedDataPath build/sim build
xcrun simctl launch booted dev.plumpbug.homedashboard -demo YES -layout <name>
Tools/install_saver.sh                           # Mac screensaver, Release, into ~/Library/Screen Savers
```

- Run `xcodebuild` outside the sandbox (a hook enforces it): sandboxed, it cannot read the
  Xcode account and signs Xcode out.
- Keep derived data under `build/<name>` (ignored); don't scatter it elsewhere.
- CI doesn't build the app, so a change to `HomeDashboardTV/` or `HomeDashboardSaver/` is
  unverified until built locally for both the tvOS simulator and a macOS scheme
  (`HomeDashboardSaverHost`), since every layout compiles into both.
- Check a layout visually before a PR: simulator screenshot (`xcrun simctl io <udid>
  screenshot`), or the host app's `-snapshot <path>` on the Mac. `simctl install` kills the
  running app, so relaunch before each screenshot.

## Code rules

- Logic that can be unit-tested (geometry, time, text fitting, colour math) goes in
  `Packages/DashboardCore` with a test; views only draw.
- Everything in `HomeDashboardTV/UI` and `App` must compile for macOS too: UIKit types go
  through `UI/Parts/Platform.swift`, resources through `PlatformBundle.resources` (not
  `Bundle.main`, which is the screensaver host there). Layout inks and faces stay `private`
  to their file; new fonts are listed under `UIAppFonts` in `project.yml`.
- Days and times use the Pi's configured zone, never the device's.
- Target: tvOS 17 / macOS 14, Swift 5 mode. Signing comes from `Config/Signing.xcconfig`,
  overridden by the git-ignored `Config/Signing.local.xcconfig`.

## Conventions

- Commit subjects are plain sentences in the imperative ("Keep a saved HTTPS address whole in
  Options"); the body says why, not what the diff shows.
- Work on a branch and merge by PR; `main` is protected by the `core` CI check.
- README screenshots in `docs/` are 1920×1080 from the demo data; refresh one when its
  layout changes visibly.
