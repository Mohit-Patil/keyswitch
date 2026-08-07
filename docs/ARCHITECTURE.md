# Architecture

KeySwitch separates global input capture, application state, rendering, and
Codex compatibility so that each boundary can fail independently and be tested
in isolation.

## Components

### `KeyboardEngine`

Owns the macOS event tap and the keyboard-layer state machine. It recognizes
the activation shortcut, suppresses mapped or unmapped keys according to the
configuration, emits Micro control press/release events, and guarantees the
Escape safety exit.

The engine does not know about SwiftUI, windows, or Codex renderer details.

### `AppModel`

Coordinates persisted configuration, permissions, layer state, HUD visibility,
inactivity timers, agent lighting, setup, and bridge lifecycle. It is the
single source of truth passed into SwiftUI views.

Configuration is encoded into `UserDefaults`. Decoding merges new defaults so
older installations gain new controls and options without erasing custom
mappings.

### `HUDWindowController` and SwiftUI views

`HUDWindowController` owns one transparent, non-activating `NSPanel`. SwiftUI
renders the expanded Micro layout inside that panel while the keyboard layer is
active. The controller keeps the selected HUD size anchored to the top-right of
the active screen, and the panel never becomes the typing focus.

`MenuBarStatusLabel` renders the same six agent states into the app's
`MenuBarExtra` label. It uses a compact original-color image because macOS
extracts the image portion of a menu-bar label rather than preserving arbitrary
colored shape views.

The selected HUD appearance is scoped to the HUD subtree and panel; it must not
change the Settings window or other app UI.

### `CodexMicroBridge`

Connects to a Chromium debugging target on the configured loopback port. It
discovers the Codex renderer, establishes a WebSocket connection, reads Micro
layout and agent-lighting state, and emits the existing key, joystick, and
encoder event payloads.

This is an adapter for undocumented upstream behavior, not a USB or Bluetooth
device emulator. All bridge operations must fail closed: losing the renderer
can disable Codex actions, but it must not leave the keyboard layer stuck.

### Setup and permissions

`FirstRunSetupWindowController` presents a guided setup window. The permission
service checks Input Monitoring and Accessibility independently. The setup flow
can restart the original Codex app with a debugging-port argument, then asks
the bridge to reconnect.

## State flow

```text
NSEvent / CGEvent
       │
       ▼
KeyboardEngine
       │ control + layer callbacks
       ▼
    AppModel ───────────────► HUD panel and Settings
       │
       ▼
CodexMicroBridge ◄──────────► Codex renderer on 127.0.0.1
```

The renderer remains the source of truth for Micro keycaps and slot actions.
KeySwitch remains the source of truth for which Mac key activates each slot.

## Trust boundaries

1. **Global input:** macOS sends keyboard events after the user grants privacy
   permissions.
2. **Local persistence:** mappings and preferences are stored in the KeySwitch
   defaults domain.
3. **App control:** setup can terminate and relaunch the installed Codex app.
4. **Renderer debugging:** the loopback debugging endpoint is privileged and
   must not be exposed to a network.
5. **Upstream compatibility:** evaluated renderer modules and state can change
   without notice.

See [SECURITY.md](../SECURITY.md) for responsible disclosure and
[PRIVACY.md](PRIVACY.md) for data handling.

## Testing strategy

Unit coverage focuses on the deterministic boundaries:

- activation shortcuts, Hold/Toggle behavior, and suppression;
- Micro slot and payload contracts;
- stick and dial behavior;
- configuration round trips and legacy migrations;
- agent status, menu-bar rendering, and HUD-size migrations; and
- optional live bridge checks behind an explicit environment flag.

Visual behavior, permission prompts, and live upstream compatibility still
require manual macOS testing.
