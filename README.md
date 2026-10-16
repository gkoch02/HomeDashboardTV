# Home Dashboard for Apple TV

[![CI](https://github.com/gkoch02/HomeDashboardTV/actions/workflows/ci.yml/badge.svg)](https://github.com/gkoch02/HomeDashboardTV/actions/workflows/ci.yml)
[![CodeQL](https://github.com/gkoch02/HomeDashboardTV/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/gkoch02/HomeDashboardTV/actions/workflows/github-code-scanning/codeql)
[![tvOS 17+](https://img.shields.io/badge/tvOS-17%2B-black?logo=apple)](#building-it-yourself)
[![Needs HomeDashboard 6.2+](https://img.shields.io/badge/needs-HomeDashboard%206.2%2B-2f6fb2)](https://github.com/gkoch02/HomeDashboard)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

The tvOS companion to [HomeDashboard](https://github.com/gkoch02/HomeDashboard), the Raspberry Pi e-ink dashboard.
The Pi keeps doing the fetching (Google Calendar / ICS / CalDAV, OpenWeatherMap, birthdays)
on its own timer; this app reads the Pi's cached snapshot from `GET /api/dashboard` and
draws it natively at TV resolution, with no e-ink pixels and no credentials on the TV.

It is not on the App Store: it needs your own HomeDashboard Pi, and you build it onto your
Apple TV yourself with Xcode ([Building it yourself](#building-it-yourself)).

![The dashboard on an Apple TV 4K, from HomeDashboard's dummy data](docs/dashboard.png)

**Agenda** (settings → Layout → Agenda) is the spiritual successor to the Pi's
`halftone_agenda`, as a dark plate for a big screen: the weather and its reading on the left,
the day's agenda on the right, in cream type on warm charcoal with the Pi's Inky spot inks,
ochre and red. The weather window is painted at full resolution: a sky for each kind of
weather by day and night, a glowing sun, shaded cloud banks, rain, snow, lightning and mist,
and at night the moon photograph at tonight's phase. The agenda keeps the Pi's treatments:
elapsed events print through a fine dot screen (its perforated type), the one in progress is
lifted, the next one carries a red tick, and after sunset, once the day's events are over, it
rolls over to tomorrow.

![The Agenda layout, from HomeDashboard's dummy data](docs/agenda.png)

**Horizon** (settings → Layout → Horizon) is the Pi's `wide_horizon` theme: the next 72 hours
on one time axis, night hours narrower than waking ones. The sky across the screen is
coloured by the sun's altitude at every moment, so day, twilight and night follow each other
left to right, with stars by night, the sun at each noon and the moon photograph at each
night's transit. The forecast temperature runs over it as one line with each day's high and
low, clouds, rain, snow, storms and mist sit on their 3-hour slots, the chance of rain hangs
beneath, and the calendar sits below on the same hours: a strip of every timed event's span,
all-day chips and birthdays, then each day's events in its own column. The conditions now and
an outlook (the warmest and coldest hours, the next rain) fill the left column. The sun is
the Pi's: the `sun` block of `/api/dashboard` carries its altitude every 15 minutes, computed
from the Pi's coordinates. A Pi without coordinates, or one older than the block, gets the
panel's own fallback, an arc between the day's sunrise and sunset.

![The Horizon layout, from HomeDashboard's dummy data](docs/horizon.png)

**Skylight** (settings → Layout → Skylight) has no Pi theme behind it; it is drawn for a big
OLED TV. The top of the screen is the sky outside, live: a Metal shader running at 30 frames a
second, coloured by the sun's altitude now, with the sun crossing it from sunrise to sunset,
stars that twinkle after dark and the moon photograph at tonight's phase. The current weather
moves through it as cloud, rain, snow, fog or lightning, drifting with the real wind. Below two
ridges the ground is true black, which an OLED draws with its pixels off. Over the sky sit the
time, today's all-day events and birthdays, and the events still to come today and tomorrow,
with the weather now on the right. On the ground are the next 24 hours as a line through the
temperatures coloured by the heat, with sunrise and sunset where they fall, the days ahead with
their ranges, and the sun and moon times.

![The Skylight layout at dusk, from HomeDashboard's dummy data](docs/skylight.png)

**Light Cycle** (settings → Layout → Light Cycle) is the Pi's `light_cycle` theme: today as one
24-hour dial, midnight at the top. Its band is the sky through the day, coloured by the sun's
altitude as Horizon colours its sky, with stars in the darkest stretch and a rule at sunrise
and sunset. Today's timed events ride inside it as arcs over their hours (red while one runs,
ochre to come, hollow once over), and the sun, or after dark the moon at tonight's phase,
rides the band at the current minute on a needle from the date at the centre. Beside it:
sunrise, sunset, the day's length and how much shorter or longer tomorrow is, the weather now
and the day's agenda. With the Pi's `sun` block the times are the Pi's astronomical ones;
without it, the weather's sunrise and sunset, and no change for tomorrow.

![The Light Cycle layout, from HomeDashboard's dummy data](docs/light-cycle.png)

**Weatherglass** (settings → Layout → Weatherglass) is the Pi's `weatherglass` theme, a deck of
Victorian instruments drawn as black enamel dials in brass: a thermometer with its cold,
comfortable and hot zones and the day's high and low; an aneroid barometer from 950 to
1050 hPa under the banjo barometer's words; a hygrometer; the UV index; a wind compass; the
sun's arc from sunrise to sunset; the moon; and the air quality. A hollow needle on the
barometer marks the pressure one to 36 hours ago, with the change in words (rising, falling,
steady). The TV keeps those readings itself, as the Pi does for its panel, so the trend shows
an hour or so after the layout is first used. The needles swing to their readings when the
layout appears.

![The Weatherglass layout, from HomeDashboard's dummy data](docs/weatherglass.png)

**Fuzzy Clock** (settings → Layout → Fuzzy Clock) is the Pi's `fuzzyclock` theme: the time in
words ("twenty five to nine", "noon"), snapped to the nearest five minutes and set as large as
it fits in DM Sans, the minutes gold and the hour blue on black, over the date and a strip of
the weather now, the next three days and the moon. The words cross-fade when they change.

![The Fuzzy Clock layout, from HomeDashboard's dummy data](docs/fuzzy-clock.png)

**Quote** (settings → Layout → Quote) is the Pi's `qotd` theme: the dashboard's quote of the
day set as large as it fits in Playfair Display, between oversized ochre quotation marks,
over a strip of the weather now, the next three days and the moon.

![The Quote layout, from HomeDashboard's dummy data](docs/quote.png)

**Moon** (settings → Layout → Moon) is the Pi's `moonphase_photo` theme, drawn natively: today's
moon from the photograph, cut by the true terminator with a faint earthshine copy on the dark
side, three days either side, then moonrise and moonset, sunrise, sunset and the weather, the
next full or new moon, and the panel's quote, in the panel's own faces. The Pi computes every
moon value (the `moon` block of `/api/dashboard`); the app only draws it.

![The Moon layout on an Apple TV, from HomeDashboard's dummy data](docs/moon.png)

**Night** (settings → Layout → Night) is the Pi's `wide_night` plate in its inverse,
`wide_night_invert`, for a dark room: the moon's phase, the temperature, the air-quality
index and the sky, in dim red on black and nothing else. A mark without data (the AQI on a Pi
without PurpleAir) is left out and the rest re-spaced.

![The Night layout, from HomeDashboard's dummy data](docs/night.png)

## What the TV needs

- The Pi's web UI running, with HomeDashboard 6.2 or later (the `/api/dashboard` route):
  `make web-enable` on the Pi. That also advertises it over Bonjour as `_homedash._tcp`
  when `avahi-daemon` is installed (it is on Raspberry Pi OS), so the TV finds it by itself.
- The web UI's username and password, if one is set (`python -m src.web.auth --set-password`).
  The password is kept in the TV's Keychain.

On first launch the app opens its settings drawer at **Source**: pick the Pi under **On This
Network**, or type its address (`dashboard.local`, `192.168.1.20:8080`). **Demo data** shows a
bundled week with no Pi at all. Click anywhere on the dashboard to open the drawer again;
Menu goes back a page, then closes it.
Left and right on the remote step through the layouts (Dashboard, Agenda, Horizon, Skylight,
Light Cycle, Weatherglass, Fuzzy Clock, Quote, Moon, Night), and
the one you land on is remembered.

## Building it yourself

You need a Mac with Xcode, an Apple TV on the same network as the Pi, and an Apple
developer account. A paid Apple Developer Program membership is the dependable route: its
development profiles last a year. A free Apple ID (a personal team) may also work, but what
it installs stops launching after 7 days until you build it again.

1. Pair the Apple TV with Xcode: on the TV, **Settings → Remotes and Devices → Remote App
   and Devices**; on the Mac, **Window → Devices and Simulators** in Xcode, then pick the TV
   and enter the code it shows.
2. Give the build your own signing. The team and bundle prefix in the project are the
   author's; yours go in a local file that git ignores:

   ```bash
   cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
   ```

   Set `DEVELOPMENT_TEAM` to your team ID (Xcode → Settings → Accounts) and
   `BUNDLE_ID_PREFIX` to a reverse-DNS prefix of your own.
3. Open `HomeDashboardTV.xcodeproj`, choose your Apple TV as the run destination and run
   the **HomeDashboard** scheme. Xcode makes the profile (automatic signing) and installs
   the app.

On first launch, allow local network access so the app can find the Pi, then pick it in
settings. The committed project is complete, so XcodeGen is only needed to change
`project.yml` (see [Building](#building)).

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
- The screensaver and sleep are held off while the app is open, always or for 1–8 hours after
  the last remote press (settings → Keep awake); after that the Apple TV's own timers apply.

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

(With your own `BUNDLE_ID_PREFIX`, the bundle identifier is `<prefix>.homedashboard`.)

A device build needs a registered Apple TV for its development profile; signing is set up
as in [Building it yourself](#building-it-yourself).

## License

MIT — see [LICENSE](LICENSE). The bundled typefaces are third-party works under the SIL
Open Font License 1.1, each shipped with its upstream license text, and the demo data
carries a few short quotations that are not ours to license; the **Third-party content**
section of [LICENSE](LICENSE) sets out both.
