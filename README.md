# GlassWork

A Liquid Glass companion for macOS: live menu bar modules, desktop widgets and a widget-friendly Dock in one app.

> Status: early development. See the roadmap below.

## What it does

- **Menu bar.** Small live items for the processor, memory, disk, network, battery, GPU, temperatures and fans,
  plus developer modules (coding-assistant usage limits, Git, dev servers, containers, ping, VPN, Wi-Fi, uptime)
  and everyday ones (calendar, world clocks, timers, keep awake, now playing, notes, to-dos, weather, exchange
  rates and more). Each item can show a symbol, a figure, a graph, both, or a label, and keeps a fixed width.
- **Desktop widgets.** Native WidgetKit widgets in small, medium, large and extra large sizes, and the same
  widgets as live floating desktop windows that update every second.
- **Dock.** A Dock replacement on any edge of the screen, with live widgets beside your apps, folders, stacks,
  Downloads and presets. It is off until you turn it on.
- **Main window.** What every app uses right now and over the last week, with helpers counted in. Apps can be
  quit from there, the Hub, the CPU and Memory panels, the Dock and a palette on ⌃⌥Q.
- **Window Tiles.** Keyboard shortcuts that send the front window to a half, a third, a quarter or another
  display. Off until you turn it on, and it needs Accessibility.

Everything is read locally from this Mac. Nothing is logged or uploaded; network access is limited to the
modules that need it (ping, endpoints, GitHub through your own `gh`, weather, exchange rates, and song lyrics
from lrclib.net for the Lyrics widget, which you can turn off). The Photo Frame, On This Day and Birthdays widgets
stay off until you turn them on in Settings; only then does the app read that folder, Photos or Contacts.

## Requirements

- macOS 26 or later
- Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), SwiftLint and SwiftFormat:
  `brew install xcodegen swiftlint swiftformat`

## Build

```sh
echo 'DEVELOPMENT_TEAM = YOURTEAMID' > Config/Local.xcconfig   # any Apple ID team, free works
make install      # release build into /Applications and launch
make help         # all commands
```

`make build-unsigned` builds without signing; widgets need a signed build to appear in the widget gallery.

## Project layout

| Path | What |
|---|---|
| `App/` | The GlassWork app: menu bar items, settings, desktop windows, Dock |
| `Widgets/` | WidgetKit extension (sandboxed, reads shared snapshots) |
| `Helper/` | Optional privileged daemon that changes fan speed |
| `Packages/GlassWorkKit/` | `GlassWorkCore` (collectors, models, storage) and `GlassWorkUI` (shared views) |
| `Config/` | Build settings; `Local.xcconfig` holds your signing team and is not committed |
| `scripts/` | Helper scripts, including the optional background auto-update |

Architecture notes: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Roadmap

1. Foundation and system menu bar modules
2. Developer modules
3. Everyday modules, weather and exchange rates
4. WidgetKit widgets and floating desktop widgets
5. Dock

## License

MIT, see [LICENSE](LICENSE).
