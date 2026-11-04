# Architecture

## Processes

- **GlassWork.app** is an unsandboxed app with a Dock icon and a main window. Closing the window leaves it
  running in the menu bar. It owns every data collector: system metrics (Mach, IOKit, SMC), shell tools
  (`git`, `docker`, `gh`), files of local tools, network checks.
- **GlassWorkWidgets.appex** is the WidgetKit extension. It is sandboxed, so it never runs tools or reads
  arbitrary files. It reads JSON snapshots that the app writes into the shared App Group container and
  performs small actions through App Intents.
- **GlassWorkFanHelper** is an optional LaunchDaemon, the only process that runs as root and the only code
  that writes to the SMC. It is installed with `SMAppService.daemon` when the user presses a button.
- **now-playing-adapter.pl** is a child of the app, run by the system `/usr/bin/perl` because macOS only
  answers trusted MediaRemote clients. It runs only while something on screen shows the current track,
  prints JSON lines and takes transport commands on its input. Closing that input ends it, so it cannot
  outlive the app. The script sits in the app's resources and needs nothing but what macOS ships.

```
collectors ──► app state ──► menu bar items / desktop windows / Dock
                    │
                    └──► SnapshotStore (App Group container, JSON) ──► widget timelines
```

The App Group identifier is `$(TeamIdentifierPrefix)io.github.evgenybaulin.glasswork`. It is passed to code
through the `GWAppGroupID` Info.plist key; `AppGroup.containerURL` falls back to Application Support for
unsigned builds and tests.

## Fan control

Reading fan speeds needs nothing. Changing them goes through the helper:

```
FanEngine (pure) ──► FanControlModel ──► XPC ──► FanHelperServer ──► FanHelperService ──► SMC
```

- `FanEngine` turns temperatures, settings and time into commands: curve, smoothing, failsafe, power rules.
  `FanControlModel` runs it every 2 s while a mode other than Auto is on. This loop reads sensors on its own,
  because `SystemMonitor` pauses for a locked screen and the failsafe must not.
- The helper accepts only "fan N: auto / max / target RPM" and a heartbeat, from a client signed by its own
  team. An unsigned build has no team, so it is refused. The helper checks fan numbers and speeds against the
  SMC's limits itself, and writes only fan mode, fan target and `Ftst` keys.
- Fans return to Auto without the app's help: when the client disconnects, after 10 s of silence, when the
  helper starts (a crash may have left a fan in manual mode) and on SIGTERM.
- The app sends Auto before sleep, and a curve is applied again 10 s after wake. Average CPU above 95 °C
  switches Curve and Custom to Max until the user picks a mode. A lost temperature reading returns to Auto.
- `SMCWriter` lives in `Helper/Sources`, so neither the app nor the tests compile a write. The logic around it
  runs against the `FanSMCAccess` protocol and is tested with a fake.
- Apple silicon reports fan mode 0 (auto), 1 (manual) or 3 (system). Only 1 counts as manual.

## Widget data and actions

The app is the only place that reads anything. Widgets get a `WidgetSnapshot`:

- `AppModel.makeWidgetSnapshot()` builds it for system widgets and desktop windows alike. It only copies the
  latest readings, so calling it often costs little, and it carries only what placed widgets show.
- The kinds placed as desktop windows join the regular 2 s tick. System widgets, which WidgetKit reports through
  `WidgetCenter`, get one read a minute, except charts that need steady samples. See `MonitorDemand(widgets:)`.

A button in a widget cannot do anything by itself, because the extension is sandboxed:

```
Button(intent:) ──► WidgetActionIntent ──► WidgetCommandInbox (App Group) ──► Darwin notification
                                                                                     │
                       FanControlModel, EventKit, timers, eject ◄── AppModel.perform ┘
```

- `GlassWorkUI` cannot name an intent, which must live in the extension to be found. Each host supplies a
  `WidgetActionRenderer`: the extension a button that runs the intent, the app one that calls the model directly.
- A command is dropped after 10 s, so a Max tapped while the app was closed cannot start the fans later.
- `AppModel.perform` trusts nothing in a command and checks it against current state. Without fan control
  `FanControlModel.perform` does nothing, and the widget shows the button as a picture with no action.

A click on a widget goes through `WidgetLink`, which can only name a module's panel or the Widgets pane of Settings.
Any app can open that scheme, so everything else is ignored.

### Photos and birthdays

Photo Frame, On This Day and Birthdays read personal data, so they follow stricter rules:

- `PersonalWidgetStore` reads in the app only, at most once a day, and only for a widget that is on and placed.
- Only the buttons in Settings › Widgets can bring up a macOS prompt. Everything else checks the status and stops.
- Readers are protocols. The real ones for Photos and Contacts live in the app target, so the extension never links
  those frameworks, and tests use fakes.
- Downscaled JPEGs go to the shared container as numbered files. Turning a widget off removes them.
- `PhotoProvider` in the extension moves through the photos on its own timeline, so a new photo costs the app nothing.

## Modules

`Packages/GlassWorkKit`:

- `GlassWorkCore`: models, collectors, parsers, settings, `SnapshotStore`. No SwiftUI.
- `GlassWorkUI`: shared SwiftUI building blocks (glass cards, rings, dot progress, sparklines).

Collectors are plain types with a pure parsing part (unit tested with fixtures) and a thin reading part.

## App usage and quitting

`AppUsageReader` reads CPU time and memory of every process with `proc_pid_rusage`, so nothing is spawned, and
groups them by app: the process macOS holds responsible, then the enclosing `.app` bundle, then the parent. Reads
ride on the monitor's tick: every 60 seconds in the background, which costs about 2 ms each, and every 5 seconds
while a list of apps is on screen. The last hour keeps a point a minute, and a week keeps a point every ten
minutes in `AppUsage.jsonl` in Application Support.

Every Quit button goes through `QuitService`. It refuses system processes and GlassWork itself, and checks who
holds the pid at that moment, because a list can be seconds old. Apps get `NSRunningApplication.terminate()`, so
they can ask to save. Plain processes get a signal.

## Settings

Settings live in a readable JSON file in Application Support and are edited from the Settings window.

## Tests

- `make test-core`: Swift Testing for core logic and SnapshotTesting for UI pieces.
- UI snapshots depend on the macOS and Xcode version. CI sets `GW_SKIP_SNAPSHOTS=1`; record locally with
  `make snapshots`.
