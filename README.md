# MicMute

Global microphone mute/unmute toggle for Windows with a system tray indicator.

**[Installation](#installation)** · **[Features](#features)** · **[Configuration](#configuration)** · **[Tray Menu](#tray-menu)** · **[How It Works](#how-it-works)**

## Installation

### Requirements

- Windows 10/11
- [AutoHotkey v2](https://www.autohotkey.com/) (or use the compiled .exe)

### Quick Start

1. Download the latest release (`MicMute.exe`) — no AutoHotkey installation needed, icons are embedded
2. Or clone/download this repo and run `MicMute.ahk` with [AutoHotkey v2](https://www.autohotkey.com/)

### Run at Startup

Right-click the tray icon → **Settings…** → check **Run at startup**.

## Features

Mutes and unmutes your default microphone at the OS level using a global hotkey. Works across all applications — great for quickly muting during calls, streams, or recordings.

- **Hotkey**: `Win + Shift + A` (configurable, rebindable at runtime)
- **Tray icon**: Green = mic active, Red = mic muted
- **Left-click** tray icon to toggle
- **Middle-click** tray icon to switch between Toggle and PTT modes
- **Right-click** tray icon for full menu
- **Scroll wheel** over tray icon to adjust mic volume (5% steps)
- **Sound feedback**: audible beep or custom WAV on toggle
- **Icon flash**: tray icon flashes briefly on toggle for visibility
- **On-screen display**: optional floating overlay shows MUTED/ACTIVE on toggle
- **Modes**: Toggle and Push-to-Talk
- **Mute lock**: prevent external apps from changing your mute state
- **Deafen mode**: separate hotkey to mute mic + speakers simultaneously
- **Settings GUI**: full settings window — no need to edit INI files manually
- **Device selector**: pick which microphone to control from the tray menu
- **Custom icons**: configurable .ico paths for colorblind accessibility
- **Custom sounds**: replace default beep with your own .wav files
- **Unmute on exit**: auto-unmutes mic when MicMute closes (prevents "dead mic")
- **Auto-detect**: automatically reconnects when you plug in or switch microphones
- **External sync**: tray icon stays accurate even when other apps change your mic state

## Configuration

All settings are accessible through the **Settings GUI** (right-click tray → Settings…). Settings are stored in `MicMute.ini` (auto-created).

```ini
[General]
Hotkey=#+a
SoundFeedback=1
Mode=toggle
DeviceId=
MuteLock=0
MuteSound=
UnmuteSound=
IconMuted=
IconActive=
OSD_Enabled=0
OSD_Duration=1500
DeafenHotkey=
MiddleClickToggle=1
StartMuted=no
```

| Setting | Default | Description |
|---------|---------|-------------|
| `Hotkey` | `#+a` (Win+Shift+A) | Global mute toggle hotkey |
| `SoundFeedback` | `1` | Audible beep on toggle (0 to disable) |
| `Mode` | `toggle` | Hotkey mode: `toggle` or `push-to-talk` |
| `DeviceId` | _(empty)_ | Specific mic device ID (empty = system default) |
| `MuteLock` | `0` | Prevent external apps from changing mute state |
| `MuteSound` | _(empty)_ | Custom .wav file path for mute sound (empty = beep) |
| `UnmuteSound` | _(empty)_ | Custom .wav file path for unmute sound (empty = beep) |
| `IconMuted` | _(empty)_ | Custom .ico path for muted icon (empty = mic_off.ico) |
| `IconActive` | _(empty)_ | Custom .ico path for active icon (empty = mic_on.ico) |
| `OSD_Enabled` | `0` | Show floating overlay on toggle |
| `OSD_Duration` | `1500` | OSD display time in milliseconds (min 500) |
| `DeafenHotkey` | _(empty)_ | Hotkey for deafen mode (empty = disabled) |
| `MiddleClickToggle` | `1` | Middle-click tray to switch Toggle/PTT modes |
| `StartMuted` | `no` | Startup behavior: `no`, `yes`, `unmuted`, or `last` |

### Hotkey Syntax

Modifier symbols: `#` = Win, `^` = Ctrl, `!` = Alt, `+` = Shift

Examples:
- `^!m` → Ctrl + Alt + M
- `#+a` → Win + Shift + A
- `F13` → F13 key

If the hotkey string is invalid, MicMute falls back to tray-only mode (left-click the icon to toggle).

You can also change the hotkey at runtime via Tray → **Hotkey: ...**.

## Tray Menu

| Item | Action |
|------|--------|
| Toggle Mute | Mute/unmute the mic |
| Hotkey: ... | Shows current hotkey — click to rebind |
| Mode → | Submenu: Toggle, Push-to-Talk |
| Mic Source → | Submenu: available audio devices |
| Settings… | Open Settings GUI |
| Reinit Mic | Manually reconnect to audio device |
| Sound Settings | Open Windows Sound Settings |
| Exit | Close MicMute |

### Modes

- **Toggle** (default): Press the hotkey to flip mute on/off.
- **Push-to-Talk**: Hold the hotkey to unmute. Release to re-mute. (30s safety timeout)

Switch modes via the tray menu or middle-click the tray icon.

### Deafen Mode

Set a deafen hotkey in Settings to enable a separate hotkey that mutes both your microphone and speakers simultaneously. Press again to restore both to their previous state. The tray tooltip shows `[DEAFENED]` when active.

### Mute Lock

When enabled, MicMute prevents other applications from changing your mic mute state. If an app tries to unmute/mute your mic, MicMute immediately re-applies your chosen state.

### On-Screen Display

When enabled, a floating overlay briefly appears on screen showing **MUTED** (red) or **ACTIVE** (green) whenever the mute state changes. The OSD is click-through and semi-transparent. Appears on the monitor where your mouse cursor is.

### Custom Sounds

Replace the default beep with your own `.wav` files. Set paths via Settings → Custom Files section. Falls back to beep if the file is missing or invalid.

### Accessible Icons

Set custom `.ico` file paths for colorblind-friendly alternatives via Settings → Custom Files. The default red/green icons can be difficult for the ~8% of males with red/green color deficiency.

### Startup Behavior

Control what happens to your mic when MicMute starts:
- **Don't change** — leaves mic in its current state (default)
- **Always muted** — forces mic to mute on startup
- **Always unmuted** — forces mic to unmute on startup
- **Remember last** — restores the previous session's mute state

## How It Works

MicMute uses Windows Core Audio COM APIs (`IAudioEndpointVolume`) to control the default capture device at the OS level. This means the mute applies system-wide — every application sees the mic as muted.

A background timer (every 3 seconds) monitors the audio endpoint to:
- Auto-detect device changes (mic plugged/unplugged)
- Sync the tray icon if another app changes the mute state
- Enforce mute lock if enabled

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
| `mic_on.ico` | Tray icon — mic active (green). Embedded in compiled .exe |
| `mic_off.ico` | Tray icon — mic muted (red). Embedded in compiled .exe |
| `MicMute.ini` | User config (auto-created, gitignored) |

## License

[MIT](LICENSE)
