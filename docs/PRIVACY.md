# Privacy

KeySwitch is designed to operate locally on the Mac.

## Data KeySwitch processes

- Global keyboard events while the app is running.
- The user's KeySwitch mappings, activation settings, HUD preferences, and
  setup state.
- Codex Micro layout metadata and six agent-slot status values exposed by the
  local Codex renderer.
- Local application and permission status needed for setup and diagnostics.

KeySwitch uses key events to resolve configured controls. It does not maintain
a text history, send keystrokes to an analytics service, or provide a cloud
account.

## Storage

Preferences are stored in the standard macOS `UserDefaults` domain for the
KeySwitch bundle identifier. They can be reset by removing the app's defaults
or by using the relevant reset controls in the app.

KeySwitch does not intentionally write Codex task content, screenshots,
profiling traces, or event logs to disk during normal use.

The app bundle includes `PrivacyInfo.xcprivacy`. It declares that KeySwitch
does not track people or collect data, and documents its local use of
`UserDefaults` and system uptime for preferences and double-tap timing.

## Network behavior

The Codex bridge connects to the configured Chromium debugging port at
`127.0.0.1`. No analytics or telemetry endpoint is included. The prototype and
app should never be configured to expose that privileged port to an external
network.

Because the renderer belongs to Codex, Codex's own storage and network behavior
is governed by its provider and is outside KeySwitch's control.

## macOS permissions

KeySwitch requests:

| Permission | Purpose |
| --- | --- |
| Input Monitoring | Observe global key presses and modifier changes. |
| Accessibility | Install and recover the global event tap used by the control layer. |

These permissions are powerful. Only run builds you trust, and review source
changes involving the event tap, app launch behavior, or renderer evaluation.

## Removing local data

Quit KeySwitch, remove the app, and clear its macOS privacy entries if you no
longer want it to monitor input. The defaults domain is
`com.mohitpatil.keyswitch` unless a fork changes the bundle identifier.

Privacy concerns that may be security vulnerabilities should follow the
private process in [SECURITY.md](../SECURITY.md).
