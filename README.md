# Logi : nu-type

A small menu bar replacement for Logi Options, built for the MX Master 2S and MX Keys Mac.

## What it does
- Shows mouse battery in the menu bar, and keyboard battery in the menu.
- Captures buttons over Logitech's HID++ protocol: thumb/gesture button, button behind the wheel,
  back/forward, middle. Each can run a shortcut, Mission Control, desktop switching, media keys,
  open an app or a website, and more. Any button can use hold-and-move gestures.
- Per-app profiles (pre-filled from the old Logi Options setup: Chrome, Sublime Text, Spotify, Figma).
- Thumb wheel: horizontal scroll, volume, zoom, tabs, or desktops, set per app.
- Settings for SmartShift, ratchet/free spin, DPI, and reversing scroll direction.
- Flow between two Macs: push the cursor off the shared edge and the mouse (and MX Keys)
  Easy-Switch to the other Mac. Clipboard is shared. Uses an encrypted connection keyed by a pairing code.

## Build and install
    ./build.sh            # builds, signs, installs to ~/Applications and launches it

Needs Xcode installed (SwiftUI macros aren't in the Command Line Tools).

## First run
1. Allow **Accessibility** and **Input Monitoring** for Logi : nu-type in System Settings → Privacy & Security,
   then use "Relaunch" in Settings → General (or quit and reopen).
2. Quit Logi Options (menu → "Logi Options is running — quit it"). Better still, uninstall it, because
   its helper relaunches itself at every login.
3. Settings → General → turn on "Open Logi : nu-type at login".

## Flow setup
1. Install Logi : nu-type on both Macs.
2. Pair the mouse and keyboard with each Mac on a different Easy-Switch channel.
3. On Mac A: Settings → Flow → Enable, then Copy the pairing code. On Mac B: paste it, choose "Use this code", and enable Flow.
4. Set which side the other Mac is on, on each Mac.
5. Use the mouse on each Mac once so both learn each other's channel. After that, push the cursor off the edge to switch.

Settings live in `~/Library/Application Support/LogiLite/config.json`.
