# A tour of the code

For anyone opening this repo for the first time. `README.md` is the full reference and `CLAUDE.md` holds the rules the code keeps; both are written to be looked up. This page is meant to be read once, top to bottom, and leaves you knowing which few files matter, how the dashboard gets from the Pi to the TV, and how to find your way around the rest.

You don't need to know Swift well to follow it. Where a piece of Swift is quoted, the sentence around it says what it does.

## The big picture

This app is a screen for [HomeDashboard](https://github.com/gkoch02/HomeDashboard), the Raspberry Pi e-ink dashboard. The Pi does the real work: it fetches the calendar, the weather, the birthdays and the air quality, keeps them cached, and serves them all as one JSON document at `/api/dashboard`. This app asks for that document every five minutes and draws it. To understand where the data comes from, how it's fetched, or why a source is stale, read the Pi's side: [HomeDashboard's `docs/CODE_TOUR.md`](https://github.com/gkoch02/HomeDashboard/blob/main/docs/CODE_TOUR.md) and its web UI's code (`src/web/`).

The one exception is the Mac screensaver's **This Mac** source, which needs no Pi: it builds the same document on the Mac from Open-Meteo and calendar feeds (`LocalSource`, `LocalSnapshot`).

`project.yml` defines five targets:

| Target (scheme) | What it is | Folder |
|---|---|---|
| `DashboardCore` | A Swift package with no screen code: the data model, decoding the Pi's JSON, the HTTP client, the agenda, and each layout's testable arithmetic (sky colours, the orrery's angles, the fuzzy clock's words). Its tests run on the Mac | `Packages/DashboardCore/` |
| `HomeDashboard` | The Apple TV app | `HomeDashboardTV/` |
| `HomeDashboardSaver` | The Mac screensaver, `Home Dashboard.saver`. Not a copy: it compiles the TV app's layouts and store again for the Mac | `HomeDashboardSaver/` plus most of `HomeDashboardTV/` |
| `HomeDashboardSaverHost` | A Mac window around the screensaver's screen, for working on it, and the quickest way to see a layout | `HomeDashboardSaver/Host/` |
| `HomeDashboardUITests` | A UI test that drives the TV app with the remote | `HomeDashboardUITests/` |

`scripts/` (Python: the icon, the Top Shelf images, the banner) and `Tools/` (the screensaver install and the project check) never ship.

## Words this code uses

| Word | Means |
|---|---|
| **snapshot** | The Pi's `/api/dashboard` document, decoded: `Snapshot` in `Packages/DashboardCore/Sources/DashboardCore/Snapshot.swift`. Everything on screen comes from one |
| **source** | One kind of data in the snapshot (events, weather, birthdays, air quality), each a `Source<…>` with its `data` and how stale the Pi says it is (`staleness`) |
| **schema version** | The document's version number. A build refuses a newer one than it knows (`Snapshot.supportedSchemaVersion`) |
| **connection** | Where the snapshot comes from: a Pi's address, the demo data, or (on the Mac) This Mac. `DashboardStore.Connection` |
| **backup** | A second Pi, used while the main one doesn't answer |
| **demo** | A real snapshot from the Pi's dummy data, bundled (`HomeDashboardTV/Resources/demo-snapshot.json`) and shifted to today (`shiftedToToday`), so the app works with no Pi |
| **Bonjour** / **`_homedash._tcp`** | How the TV finds a Pi on the network by itself (`PiBrowser`) |
| **layout** / **theme** | One of the screens you step through with left and right (Dashboard, Cyberpunk, Uplink, …). `DashboardStore.Layout` names them; each is a view conforming to `Theme` |
| **`LayoutSwitch`** | Layout name → view, one line each. `HomeDashboardTV/UI/Theme.swift` |
| **plate** / **backdrop** | A layout's content, which drifts, and what sits still behind it |
| **drift** / **burn-in** | The plate moving a few points every ten minutes so an OLED TV never holds one image (`BurnIn.drift`) |
| **notice** | The line in the corner when the Pi can't be reached or a source is stale (`DashboardStore.notice`) |
| **agenda** | The events grouped by day in the Pi's time zone (`AgendaDay` in `Agenda.swift`) |
| **sky** | The live shader backgrounds of Skylight, Aurora and Window, drawn with Metal through `SkyLayer` (`.metal` files in `UI/Parts/`) |
| **highlights** / **headroom** | On an HDR TV, how much brighter than white the skies' brightest points may go |
| **`WeatherArt`** / **`WeatherScene`** | The painted weather window some layouts share: what to paint (`WeatherScene`, in the package) and the painting (`WeatherArt`) |

## Following one update

Say the TV is showing the Dashboard layout, pointed at the Pi. Here's the path of one update, with the file and the name at each step. To find one, search the file for `func` and its name, e.g. `func refresh`.

**1. The app starts.** `HomeDashboardTV/App/HomeDashboardApp.swift`. It makes one `DashboardStore`, shows `DashboardScreen`, and calls `store.start()` when it appears.

**2. The poll.** `DashboardStore.start()` in `HomeDashboardTV/App/DashboardStore.swift` starts a loop:

```swift
await self.refresh()
let healthy = self.problem == nil && self.onBackupSince == nil
try? await Task.sleep(for: healthy ? Self.pollInterval : Self.retryInterval)
```

"Fetch, then wait five minutes (`pollInterval`), or one minute (`retryInterval`) if the fetch failed or the backup is standing in."

**3. Fetching.** `DashboardStore.refresh()`. For a Pi it calls `DashboardClient.fetchFirst(of:username:password:)` with the main Pi's address and the backup's, which tries them in order and returns the first answer. For the demo it loads the bundled snapshot instead; on the Mac's This Mac it asks `LocalSource`.

**4. Over the network.** `Packages/DashboardCore/Sources/DashboardCore/DashboardClient.swift`, `fetch()`. It sends `GET /api/dashboard` (with the web UI's password, if one is set) and checks the answer: a 401 means a wrong password, anything but 200 is an error. `validated(_:)` decodes it with `Snapshot.decode`, which turns the Pi's `snake_case` names and Python timestamps into Swift's, and refuses a schema version newer than this build knows.

**5. Storing it.** Back in `refresh()`, a good answer becomes `snapshot` and clears any problem. A failure keeps the last good snapshot on screen and records when it started failing, which `notice` turns into "Can't reach the dashboard since …". `DashboardStore` is `@Observable`, so setting `snapshot` makes SwiftUI redraw whatever reads it.

**6. Choosing the layout.** `HomeDashboardTV/UI/DashboardScreen.swift`. Inside a `TimelineView(.everyMinute)` (which redraws once a minute, for the clock), it hands the snapshot to `LayoutSwitch`, which picks the view:

```swift
case .dashboard: frame(DashboardView.self)
```

`frame` wraps it in `ThemeFrame`, which adds the drift, the backdrop, the corner notice and the Pi's time zone. Left and right on the remote arrive at `onMoveCommand` here and step `store.layout`.

**7. Drawing it.** `HomeDashboardTV/UI/DashboardView.swift`. The left column shows the clock and date in the Pi's zone, then, if the snapshot has weather, `CurrentWeather` (the symbol from `WeatherSymbol.name(for:)`, the temperature, the high and low, the air-quality badge) and a five-day `ForecastRow`; the rest of the screen is the week's agenda from `Agenda.swift`. The layout's colours are its own `Palette`, kept `private` to the file.

Every layout takes the same snapshot; they differ only in step 7.

The Mac screensaver runs steps 2–7 with its own shell: `HomeDashboardSaver/Bundle/HomeDashboardSaverView.swift` is the `ScreenSaverView`, and `HomeDashboardSaver/Shared/SaverScreen.swift` stands in for `DashboardScreen`.

## The files that matter

| File | One line |
|---|---|
| `HomeDashboardTV/App/HomeDashboardApp.swift` | The app's entry |
| `HomeDashboardTV/App/DashboardStore.swift` | The poll, the connection and backup, the chosen layout, the corner notice, keep-awake |
| `HomeDashboardTV/App/PiBrowser.swift` | Finding Pis on the network |
| `HomeDashboardTV/App/LocalSource.swift` | The Mac's This Mac source |
| `HomeDashboardTV/UI/DashboardScreen.swift` | The TV's screen: the remote, the settings drawer, the layout |
| `HomeDashboardTV/UI/Theme.swift` | The `Theme` protocol, `ThemeFrame`, `LayoutSwitch`, the drift |
| `HomeDashboardTV/UI/<Name>View.swift` | One layout |
| `HomeDashboardTV/UI/SettingsView.swift` | The settings drawer |
| `HomeDashboardTV/UI/Parts/` | What layouts share: the weather painting, the moon disc, the starfield, the Metal sky layer |
| `Packages/DashboardCore/Sources/DashboardCore/Snapshot.swift` | The data, as the Pi sends it |
| `Packages/DashboardCore/Sources/DashboardCore/DashboardClient.swift` | Fetching it |
| `Packages/DashboardCore/Sources/DashboardCore/Agenda.swift` | Events by day |
| `Packages/DashboardCore/Sources/DashboardCore/<Layout>.swift` | A layout's testable arithmetic (`Skylight.swift`, `Orrery.swift`, …) |
| `HomeDashboardSaver/` | The screensaver's own shell, options sheet and host window |
| `project.yml` | The Xcode project's source of truth |

## What you can skip

- **The other layouts.** Each stands alone; you only need the one you're looking at, plus anything it uses from `UI/Parts/`.
- **The `.metal` and `.h` files** in `UI/Parts/`: GPU shaders for the live skies.
- **`WideColour.swift`, `SkyColour.swift`** and the HDR handling: only about how bright and how saturated colours get on an HDR TV.
- **`LocalSource`, `LocalSnapshot`, `OpenMeteo.swift`, `ICS.swift`**: the Mac's no-Pi source. The TV never uses them.
- **`Packages/DashboardCore/Tests/`** and `HomeDashboardUITests/`: ignore until one fails.
- **`HomeDashboardTV/Resources/`**: fonts, the moon photograph, the demo data.
- **`HomeDashboardTV.xcodeproj`** and `HomeDashboardTV/Info.plist`: generated from `project.yml` by XcodeGen; never edit them by hand.

The long comments, the tests and the rules in `CLAUDE.md` can look alarming. They're there because the code was written mostly by an AI, which rereads everything every time and benefits from checks that catch it drifting. A person can safely read around them.

## Finding things

From the repo folder:

```bash
grep -rn "not updated lately" HomeDashboardTV/   # where does this message come from?
grep -rn "func refresh" HomeDashboardTV/         # where is this function defined?
grep -rln "airQuality" HomeDashboardTV/ Packages/ # every file that uses this field
```

`-r` searches every file in the folder, `-n` shows line numbers, `-l` lists just the file names. In Xcode (`open HomeDashboardTV.xcodeproj`), Find in Project (Cmd-Shift-F) does the same, and Cmd-clicking a name ("Jump to Definition") goes to where it's defined. To find a layout's code from its name on screen, look up its case in `DashboardStore.Layout`, then that case's line in `LayoutSwitch`.

## Reading a crash

A Swift crash shows up in the Xcode console when running from Xcode, or as a crash report: for the TV, in Xcode's Devices window (View Device Logs); for the screensaver, in Console.app → Crash Reports, under `legacyScreenSaver`, the system process the saver runs inside.

A made-up example:

```
Fatal error: Index out of range
...
Thread 0 Crashed:
0   libswiftCore.dylib   _assertionFailure(...)
1   HomeDashboard        ForecastRow.body.getter (DashboardView.swift:240)
2   SwiftUICore          ...
```

Read it **from the top down** (the opposite of Python): the first line is the reason; under `Crashed:`, skip the system frames (libswiftCore, SwiftUI) to the first line in this project's code, here `DashboardView.swift`, line 240.

| Message | Usually means |
|---|---|
| `Index out of range` | Asked for item n of a list shorter than that |
| `Unexpectedly found nil while unwrapping an Optional value` | Something that may be missing (a font, a resource) was missing, and the code assumed it wasn't (`!`) |
| `Fatal error: …` with a message | The code checked something and stopped on purpose; the message says what |
| "Can't reach the dashboard since …" on screen | Not a crash: the Pi didn't answer. Check its web UI is running |
| An error naming a key or type while decoding | Not a crash: the Pi sent something this build can't read, usually after a Pi update changed the document. The tests in `Packages/DashboardCore` decode a real Pi document and catch this |
| Compiler errors (`cannot find 'x' in scope`) | A misspelled or moved name. Xcode marks the line in red. Every layout also builds for the Mac, so a UIKit-only type breaks the screensaver's build |

## Making a change

1. **Find the place** with the tables above, or `grep`. How a layout looks is in its `<Name>View.swift`; its arithmetic is often in the package.
2. **Change one thing.**
3. **See it.** There are no SwiftUI previews in this project; the two quick ways to see a layout are:

   - **On the Mac, as a picture**, with the demo data:

     ```bash
     xcodebuild -scheme HomeDashboardSaverHost -derivedDataPath build/host -quiet build
     build/host/Build/Products/Debug/HomeDashboardSaverHost.app/Contents/MacOS/HomeDashboardSaverHost -demo YES -layout dashboard -snapshot /tmp/test.png -settle 3
     open /tmp/test.png
     ```

     Leave out `-snapshot` to watch it live (arrow keys step through the layouts). Use `-server <the Pi's address>` instead of `-demo YES` for your own data.

   - **In the Apple TV Simulator.** Xcode's Device Hub must have an Apple TV simulator (add one there if it lists none). Build and run from Xcode (`open HomeDashboardTV.xcodeproj`, the `HomeDashboard` scheme, an Apple TV simulator, Cmd-R), or from the terminal:

     ```bash
     xcodebuild -scheme HomeDashboard -destination 'generic/platform=tvOS Simulator' -derivedDataPath build/sim -quiet build
     xcrun simctl install booted "build/sim/Build/Products/Debug-appletvsimulator/Home Dashboard.app"
     xcrun simctl launch booted dev.plumpbug.homedashboard -demo YES -layout uplink
     ```

     The README lists every `-layout` name.
4. **Undo** if it's wrong: `git diff` shows what you changed, `git checkout -- <file>` puts the original back.

Then run the tests: `cd Packages/DashboardCore && swift test`. Run it, and anything that calls `xcodebuild`, from a normal terminal: in a sandbox it signs Xcode out of your account. The tests cover the package only, so build both the TV app and the Mac host after changing a layout: every layout compiles into both.

## Where to go next

| To understand | Read |
|---|---|
| Where the data comes from, and the Pi's web UI | [HomeDashboard's code tour](https://github.com/gkoch02/HomeDashboard/blob/main/docs/CODE_TOUR.md) |
| Setting up, the remote, every layout, the Mac screensaver, adding a layout | `README.md` |
| The rules the code keeps | `CLAUDE.md` |
