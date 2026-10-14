# Home Dashboard for Apple TV

The tvOS companion to [HomeDashboard](../HomeDashboard), the Raspberry Pi e-ink dashboard.
The Pi keeps doing the fetching (Google Calendar / ICS / CalDAV, OpenWeatherMap, birthdays)
on its own timer; this app reads the Pi's cached snapshot from `GET /api/dashboard` and
draws it natively at TV resolution, with no e-ink pixels and no credentials on the TV.

![The dashboard on an Apple TV 4K, from HomeDashboard's dummy data](docs/dashboard.png)

**Moon** (settings → Show → Moon) is the Pi's `moonphase_photo` theme, drawn natively: today's
moon from the photograph, cut by the true terminator with a faint earthshine copy on the dark
side, three days either side, then moonrise and moonset, sunrise, sunset and the weather, the
next full or new moon, and the panel's quote, in the panel's own faces. The Pi computes every
moon value (the `moon` block of `/api/dashboard`); the app only draws it.

![The Moon layout on an Apple TV, from HomeDashboard's dummy data](docs/moon.png)

**Agenda** (settings → Show → Agenda) is the spiritual successor to the Pi's
`halftone_agenda`, as a dark plate for a big screen: the weather and its reading on the left,
the day's agenda on the right, in cream type on warm charcoal with the Pi's Inky spot inks,
ochre and red. The weather window is painted at full resolution: a sky for each kind of
weather by day and night, a glowing sun, shaded cloud banks, rain, snow, lightning and mist,
and at night the moon photograph at tonight's phase. The agenda keeps the Pi's treatments:
elapsed events print through a fine dot screen (its perforated type), the one in progress is
lifted, the next one carries a red tick, and after sunset, once the day's events are over, it
rolls over to tomorrow.

![The Agenda layout, from HomeDashboard's dummy data](docs/agenda.png)

**Horizon** (settings → Show → Horizon) is the Pi's `wide_horizon` theme: the next 72 hours
on one time axis, night hours narrower than waking ones. The sky across the screen is
coloured by the sun's altitude at every moment, so day, twilight and night follow each other
left to right, with stars by night, the sun at each noon and the moon photograph at each
night's transit. The forecast temperature runs over it as one line with each day's high and
low, clouds, rain, snow, storms and mist sit on their 3-hour slots, the chance of rain hangs
beneath, and the calendar sits below on the same hours: a strip of every timed event's span,
all-day chips and birthdays, then each day's events in its own column. The conditions now and
an outlook (the warmest and coldest hours, the next rain) fill the left column. The payload
carries no coordinates, so the sun follows the Pi's own fallback: an arc between the day's
sunrise and sunset.

![The Horizon layout, from HomeDashboard's dummy data](docs/horizon.png)

## What the TV needs

- The Pi's web UI running, with HomeDashboard 6.2 or later (the `/api/dashboard` route):
  `make web-enable` on the Pi. That also advertises it over Bonjour as `_homedash._tcp`
  when `avahi-daemon` is installed (it is on Raspberry Pi OS), so the TV finds it by itself.
- The web UI's username and password, if one is set (`python -m src.web.auth --set-password`).
  The password is kept in the TV's Keychain.

On first launch the app opens its settings: pick the Pi under **On this network**, or type
its address (`dashboard.local`, `192.168.1.20:8080`). **Demo data** shows a bundled week
with no Pi at all. Click anywhere on the dashboard to come back to settings; Menu closes them.

## How it behaves

- Polls every 5 minutes (every minute after a failure). Polling costs the Pi no API quota:
  the route reads the cache and never fetches.
- Keeps the last good snapshot on screen when the Pi is unreachable and says since when.
  A source the Pi reports as stale is named in the corner; an expired one is not drawn.
- Days and times are in the Pi's configured zone, so the TV agrees with the panel.
- Air quality (when the Pi has PurpleAir on) sits beside the temperature as a badge in its EPA
  band's colour, so a bad-air day reads from across the room.
- A busy week never overflows: the day cards always keep their room, and Today and each card
  pick the richest layout that fits (wrapped titles, then single lines, then a count of the
  rest). A title too long even for two lines ends in "…".
- The layout drifts a few points every ten minutes, so an OLED TV never holds one image.
- The screensaver is off while the app is open.

## Layout

- `Packages/DashboardCore`: the payload model, decoding of the Pi's Python timestamps, the
  agenda (events per day in the Pi's zone), the HTTP client and the demo-data shift. No UI;
  `swift test` runs it on the Mac.
- `HomeDashboardTV/App`: the polling store, Bonjour discovery and the Keychain.
- `HomeDashboardTV/UI`: the three layouts, each a `Theme` (`Theme.swift`), and the settings
  panel. `UI/Parts` holds what layouts share: the painted weather window (`WeatherArt`, its
  composition `WeatherScene` in `DashboardCore`; `docs/agenda-scenes.png` shows six of them),
  the moon disc, a starfield.
- `HomeDashboardTV/Resources/Fonts`: Cinzel, Cormorant Garamond, Manufacturing Consent,
  Righteous, DM Sans, Big Shoulders Display and Figtree from HomeDashboard's `fonts/` (SIL OFL; each licence beside its font). The moon
  photograph (`MoonPhoto`) is the author's own full moon: the full-resolution original of
  the Pi's `assets/moon_full.png`, cropped to the disc at its native 1288 px with the
  disc's levels stretched, enough for the hero moon at 4K without upscaling.
- `HomeDashboardTV/Resources/demo-snapshot.json` and the test fixture are real output of the
  Pi's route over HomeDashboard's dummy data.

## Adding a layout

A layout is a view conforming to `Theme`: its body is the plate, `backdrop` what sits still
behind it, and optionally `notice(_:)` its style for the corner line. `ThemeFrame` adds the
burn-in drift, the notice's place and the Pi's time zone, so a layout only draws. Set
`fullBleed` to have the whole screen instead of the overscan safe area, and keep a 10 pt margin
for the drift. Then add a case to `DashboardStore.Layout` and a line to
`DashboardScreen.content`; the settings list picks it up. Keep its inks and faces `private` to
its file, and list any new font under `UIAppFonts` in `project.yml`.

## Icon

`scripts/generate_brand_assets.py` renders the layered app icon and the Top Shelf images into
the asset catalog (Pillow). The icon is a calendar page over an amber sun on the app's sky,
showing one week as the app does, today's column in amber; the parallax tilt slides the page across the sun. Previews are
in `docs/app-icon.png` and `docs/top-shelf.png`.

```bash
python3 scripts/generate_brand_assets.py
```

## Building

The project is generated by XcodeGen and committed, as in the other PlumpBug apps. After
editing `project.yml`, run `xcodegen` and commit the result; `Tools/check_project_sync.sh`
fails when the two disagree.

```bash
xcodegen
```

```bash
cd Packages/DashboardCore && swift test
```

In the simulator, `-server <address>` or `-demo YES` sets the source for one run, and
`-layout dashboard|agenda|moon|horizon` the layout:

```bash
xcrun simctl launch booted dev.plumpbug.homedashboard -server 127.0.0.1:8080
```

A device build needs a registered Apple TV for its development profile.
