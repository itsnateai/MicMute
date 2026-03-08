# MicMute

Global microphone mute/unmute toggle for Windows with a system tray indicator.

## What It Does

Mutes and unmutes your default microphone at the OS level using a global hotkey. Works across all applications — great for quickly muting during calls, streams, or recordings.

- **Hotkey**: `Win + Shift + A` (configurable)
- **Tray icon**: Green = mic active, Red = mic muted
- **Left-click** tray icon to toggle
- **Right-click** tray icon for full menu
- **Sound feedback**: audible beep on toggle (low tone = muted, high tone = active)
- **Auto-detect**: automatically reconnects when you plug in or switch microphones
- **External sync**: tray icon stays accurate even when other apps change your mic state

## Requirements

- Windows 10/11
- [AutoHotkey v2](https://www.autohotkey.com/)

## Installation

1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Clone or download this repo
3. Double-click `MicMute.ahk` to run

### Run at Startup

Right-click the tray icon → **Run at Startup** to create/remove a Windows startup shortcut.

## Configuration

Settings are stored in `MicMute.ini` (auto-created when you change settings via the tray menu). You can also edit it manually:

```ini
[General]
Hotkey=#+a
SoundFeedback=1
MuteOnLock=0
```

| Setting | Default | Description |
|---------|---------|-------------|
| `Hotkey` | `#+a` (Win+Shift+A) | Global mute toggle hotkey |
| `SoundFeedback` | `1` | Audible beep on toggle (0 to disable) |
| `MuteOnLock` | `0` | Auto-mute mic when PC locks (Win+L) |

### Hotkey Syntax

Modifier symbols: `#` = Win, `^` = Ctrl, `!` = Alt, `+` = Shift

Examples:
- `^!m` → Ctrl + Alt + M
- `#+a` → Win + Shift + A
- `F13` → F13 key

If the hotkey string is invalid, MicMute falls back to tray-only mode (left-click the icon to toggle).

## Tray Menu

| Item | Action |
|------|--------|
| Toggle Mute | Mute/unmute the mic |
| Hotkey: ... | Shows current hotkey (informational) |
| Sound Feedback | Toggle audible beep on mute/unmute |
| Run at Startup | Toggle Windows startup shortcut |
| Reinitialise Mic | Manually reconnect to audio device |
| Sound Settings... | Open Windows Sound Settings |
| v1.1.0 | Version (informational) |
| Exit | Close MicMute |

## How It Works

MicMute uses Windows Core Audio COM APIs (`IAudioEndpointVolume`) to control the default capture device at the OS level. This means the mute applies system-wide — every application sees the mic as muted.

A background timer (every 3 seconds) monitors the audio endpoint to:
- Auto-detect device changes (mic plugged/unplugged)
- Sync the tray icon if another app changes the mute state

## Important: OS-Level vs App-Level Mute

MicMute mutes at the **operating system level**, which affects ALL applications simultaneously. Most VoIP apps (Zoom, Discord, Teams, etc.) also have their own mute buttons. Be aware:

- If you mute in MicMute AND in your VoIP app, you'll need to unmute in **both** places
- Some apps show "your mic is muted" warnings based on their own mute state, not the OS state
- When in doubt, check both the MicMute tray icon and your app's mute indicator

## Compilation

To compile to a standalone `.exe` (no AutoHotkey installation needed):

```bash
MSYS_NO_PATHCONV=1 ./Ahk2Exe.exe /in MicMute.ahk /out MicMute.exe /icon mic_on.ico /compress 0 /silent
```

> **Note:** Use `/compress 0` — default compression triggers Windows Defender false positives.

## Files

| File | Purpose |
|------|---------|
| `MicMute.ahk` | Main script |
| `mic_on.ico` | Tray icon — mic active (green) |
| `mic_off.ico` | Tray icon — mic muted (red) |
| `MicMute.ini` | User config (auto-created, gitignored) |

## License

[MIT](LICENSE)
