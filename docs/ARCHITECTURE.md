# Architecture

## Processes

- **GlassWork.app** is an unsandboxed background app (`LSUIElement`). It owns every data collector: system
  metrics (Mach, IOKit, SMC), shell tools (`git`, `docker`, `gh`), files of local tools, network checks.
- **GlassWorkWidgets.appex** is the WidgetKit extension. It is sandboxed, so it never runs tools or reads
  arbitrary files. It reads JSON snapshots that the app writes into the shared App Group container and
  performs small actions through App Intents.

```
collectors ──► app state ──► menu bar items / desktop windows / Dock
                    │
                    └──► SnapshotStore (App Group container, JSON) ──► widget timelines
```

The App Group identifier is `$(TeamIdentifierPrefix)io.github.evgenybaulin.glasswork`. It is passed to code
through the `GWAppGroupID` Info.plist key; `AppGroup.containerURL` falls back to Application Support for
unsigned builds and tests.

## Modules

`Packages/GlassWorkKit`:

- `GlassWorkCore`: models, collectors, parsers, settings, `SnapshotStore`. No SwiftUI.
- `GlassWorkUI`: shared SwiftUI building blocks (glass cards, rings, dot progress, sparklines).

Collectors are plain types with a pure parsing part (unit tested with fixtures) and a thin reading part.

## Settings

Settings live in a readable JSON file in Application Support and are edited from the Settings window.

## Tests

- `make test-core`: Swift Testing for core logic and SnapshotTesting for UI pieces.
- UI snapshots depend on the macOS and Xcode version. CI sets `GW_SKIP_SNAPSHOTS=1`; record locally with
  `make snapshots`.
