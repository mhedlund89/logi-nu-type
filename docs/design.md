# Logi Lite — design

_2026-11-10_

## Why

Logi Options 10.22 has stopped working reliably with my MX Master 2S on macOS 27. I want a small
replacement that runs only in the menu bar, uses little memory, and keeps every feature I relied on.

## Devices

- MX Master 2S, Bluetooth, vendor 0x046D, product 0xB019
- MX Keys Mac, Bluetooth, vendor 0x046D, product 0xB361 (needed for battery and Flow)

## Goals

### Stage 1: menu bar app
- Menu bar icon showing mouse battery, with keyboard battery in the menu. Warn when low.
- Take over buttons through Logitech's HID++ 2.0 protocol (feature 0x1B04, Reprogrammable Controls):
  gesture/thumb button (CID 0xC3), wheel-mode button (0xC4), back (0x53), forward (0x56), middle (0x52).
- Actions: keystroke with modifiers, Mission Control, App Exposé, Show Desktop, previous/next desktop,
  Launchpad, media keys (play/pause, next, previous, volume), open app/URL, default (pass through).
- Gesture button: hold and move to choose up/down/left/right, or click without moving. Each one is configurable.
- Thumb wheel (0x2150): horizontal scroll by default, can be set per app (volume, zoom, tab switching).
- Per-app profiles, keyed by bundle ID, applied when the frontmost app changes.
- Device settings: SmartShift on/off and its threshold (0x2110), pointer DPI (0x2201),
  scroll direction and speed.
- Start at login. Settings saved as JSON in ~/Library/Application Support/LogiNuType.
- First run imports the current Logi Options setup:
  - Chrome: wheel-mode button sends Cmd+T
  - Sublime Text: wheel-mode button sends Cmd+Opt+F
  - Spotify: wheel-mode button sends play/pause
  - Everything else stays on defaults, with SmartShift off (ratchet mode).

### Stage 2: Flow
- Runs on both of my Macs. They find each other on the LAN with Bonjour and pair once with a confirmation code.
- Arrangement is set once (the other Mac is left, right, above, or below this one).
- When the cursor pushes past the shared edge, send Change Host (feature 0x1814) to the mouse and to
  MX Keys, so both re-pair to the other Mac. The cursor appears at the matching position there.
- Optional "hold Ctrl to cross" setting.
- Clipboard sync for text and images over the paired, encrypted connection.

## Non-goals
- Firmware updates, onboarding, account sign-in, analytics, Windows support, devices other than these two.

## Anti-goals
- Anything heavy: no Electron, no background daemons beyond the single app, near-zero idle CPU.
- Must never leave the mouse unusable. If the app quits, the device falls back to its native button behaviour.

## How
- Swift with AppKit, as a single menu bar app (LSUIElement), built with SwiftPM and a script that bundles it.
- IOHIDManager for HID++ I/O, a CGEvent tap for scroll changes, and CGEvent and NX system events to send actions.
- Needs Accessibility and Input Monitoring permissions.
- Logi Options must be quit or uninstalled, because both apps diverting the same buttons will conflict.
