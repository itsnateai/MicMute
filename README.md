# MicMute

Global microphone mute/unmute toggle for Windows with a system tray indicator.

## What It Does

Mutes and unmutes your default microphone at the OS level using a global hotkey. Works across all applications — great for quickly muting during calls, streams, or recordings.

- **Hotkey**: `Win + Shift + A` (configurable in script)
- **Tray icon**: Green = mic active, Red = mic muted
- **Left-click** tray icon to toggle
- **Right-click** tray icon for menu (toggle, reinitialise, exit)

## Requirements

- Windows 10/11
- [AutoHotkey v2](https://www.autohotkey.com/)

## Installation

1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Clone or download this repo
3. Double-click `MicMute.ahk` to run

## Customization

Edit `MicMute.ahk` line 30 to change the hotkey:

```ahk
global g_hotkey := "#+a"   ; Win + Shift + A
```

Modifier symbols: `#` = Win, `^` = Ctrl, `!` = Alt, `+` = Shift

## Troubleshooting

If you change or unplug your audio device while the script is running, use **Tray > Reinitialise Mic** to reattach, or simply restart the script.

## Files

| File | Purpose |
|------|---------|
| `MicMute.ahk` | Main script |
| `mic_on.ico` | Tray icon — mic active (green) |
| `mic_off.ico` | Tray icon — mic muted (red) |
