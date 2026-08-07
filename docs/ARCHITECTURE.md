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
inactivity timers, agent lighting, setup, launch-at-login state, and bridge
lifecycle. It is the single source of truth passed into SwiftUI views.

The model derives a narrow input-settings signature before rebuilding the
keyboard engine. Visual, connection, and HUD preferences therefore update
without interrupting an active keyboard layer.

Configuration is encoded into `UserDefaults`. Decoding merges new defaults so
older installations gain new controls and options without erasing custom
mappings.

### `HUDWindowController` and SwiftUI views

`HUDWindowController` owns one transparent, non-activating `NSPanel`. SwiftUI
renders the expanded Micro layout inside that panel while the keyboard layer is
active. The controller keeps the selected HUD size anchored to the top-right of
the active screen, and the panel never becomes the typing focus.

`MenuBarStatusLabel` renders the same six agent states into the app's
`MenuBarExtra` label. It uses color plus distinct shapes so that status remains
distinguishable without color perception.

Animated agent lighting is opt-in. A single 30 Hz main-actor clock is shared by
the visible lighting leaves and stops when animation is unnecessary, the HUD is
hidden, or Reduce Motion is enabled.

The selected HUD appearance is scoped to the HUD subtree and panel; it must not
change the Settings window or other app UI.

### `CodexMicroBridge`

Connects to a Chromium debugging target on the configured loopback port. It
discovers the Codex renderer, establishes a WebSocket connection, reads Micro
layout and agent-lighting state, and emits the existing key, joystick, and
encoder event payloads. Discovery rejects redirects, non-loopback targets,
unexpected ports, malformed page paths, credentials, query strings, and
responses larger than 1 MiB. Unchanged renderer snapshots are deduplicated.

This is an adapter for undocumented upstream behavior, not a USB or Bluetooth
device emulator. All bridge operations must fail closed: losing the renderer
can disable Codex actions, but it must not leave the keyboard layer stuck.

### Setup and permissions

`FirstRunSetupWindowController` presents a guided setup window. The permission
service checks Input Monitoring and Accessibility independently. The setup flow
can restart the original Codex app with a debugging-port argument, then asks
the bridge to reconnect.

`LaunchAtLoginService` wraps `SMAppService.mainApp`. Registration is always a
user-controlled preference; macOS can require separate approval in Login Items,
which the Settings UI reports explicitly.

### `SparkleUpdaterController`

Owns the Sparkle 2 updater for official Developer ID-signed builds. Automatic
checks and downloads are enabled by default and can be disabled in Settings.
Debug, unsigned, development-signed, and Homebrew-managed builds do not start
Sparkle.

Download completion alone is not treated as installation readiness. The
controller waits for Sparkle's `willInstallUpdateOnQuit` delegate callback,
retains its prepared installation action, and only then exposes **Restart to
Update** in the menu and Settings. Invoking that action lets Sparkle atomically
replace KeySwitch, terminate it, and relaunch the new version.

## State flow

```text
NSEvent / CGEvent
       │
       ▼
KeyboardEngine
       │ control + layer callbacks
       ▼
    AppModel ───────────────► HUD panel and Settings
       │  │
       │  └────────────────► Sparkle signed update feed
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
   must not be exposed to a network. Strict endpoint validation reduces the
   attack surface but cannot authenticate another local process that binds the
   configured port first.
5. **Upstream compatibility:** evaluated renderer modules and state can change
   without notice.
6. **Application updates:** release builds read a signed HTTPS appcast, verify
   an EdDSA-signed archive before extraction, and rely on Apple code signing,
   notarization, and Sparkle for replacement and relaunch.

See [SECURITY.md](../SECURITY.md) for responsible disclosure and
[PRIVACY.md](PRIVACY.md) for data handling.

## Testing strategy

Unit coverage focuses on the deterministic boundaries:

- activation shortcuts, Hold/Toggle behavior, and suppression;
- Micro slot and payload contracts;
- stick and dial behavior;
- configuration round trips and legacy migrations;
- agent status, menu-bar rendering, HUD-size migrations, endpoint validation,
  bounded discovery responses, launch-at-login state mapping, and prepared
  update action handling; and
- optional live bridge checks behind an explicit environment flag.

Visual behavior, permission prompts, and live upstream compatibility still
require manual macOS testing.
