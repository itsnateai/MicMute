# MicMute

Global microphone mute/unmute toggle for Windows with a system tray indicator.

## What It Does

Mutes and unmutes your default microphone at the OS level using a global hotkey. Works across all applications — great for quickly muting during calls, streams, or recordings.

- **Hotkey**: `Win + Shift + A` (configurable, rebindable at runtime)
- **Tray icon**: Green = mic active, Red = mic muted
- **Left-click** tray icon to toggle
- **Right-click** tray icon for full menu
- **Sound feedback**: audible beep or custom WAV on toggle
- **Icon flash**: tray icon flashes briefly on toggle for visibility
- **On-screen display**: optional floating overlay shows MUTED/ACTIVE on toggle
- **Modes**: Toggle, Push-to-Talk, Push-to-Mute, Hybrid (PTT/Toggle)
- **Mute lock**: prevent external apps from changing your mute state
- **Deafen mode**: separate hotkey to mute mic + speakers simultaneously
- **Device selector**: pick which microphone to control from the tray menu
- **LED sync**: sync keyboard LED (ScrollLock/CapsLock/NumLock) with mute state
- **Custom icons**: configurable .ico paths for colorblind accessibility
- **Unmute on exit**: auto-unmutes mic when MicMute closes (prevents "dead mic")
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
Mode=toggle
DeviceId=
UnmuteOnExit=1
MuteLock=0
MuteSound=
UnmuteSound=
HybridThreshold=300
IconMuted=
IconActive=
OSD_Enabled=0
OSD_Position=bottom
OSD_Duration=1500
LEDIndicator=
DeafenHotkey=
```

| Setting | Default | Description |
|---------|---------|-------------|
| `Hotkey` | `#+a` (Win+Shift+A) | Global mute toggle hotkey |
| `SoundFeedback` | `1` | Audible beep on toggle (0 to disable) |
| `MuteOnLock` | `0` | Auto-mute mic when PC locks (Win+L) |
| `Mode` | `toggle` | Hotkey mode: `toggle`, `push-to-talk`, `push-to-mute`, or `hybrid` |
| `DeviceId` | _(empty)_ | Specific mic device ID (empty = system default) |
| `UnmuteOnExit` | `1` | Auto-unmute mic when MicMute exits |
| `MuteLock` | `0` | Prevent external apps from changing mute state |
| `MuteSound` | _(empty)_ | Custom .wav file path for mute sound (empty = beep) |
| `UnmuteSound` | _(empty)_ | Custom .wav file path for unmute sound (empty = beep) |
| `HybridThreshold` | `300` | Hybrid mode: ms threshold between toggle and PTT (min 50) |
| `IconMuted` | _(empty)_ | Custom .ico path for muted icon (empty = mic_off.ico) |
| `IconActive` | _(empty)_ | Custom .ico path for active icon (empty = mic_on.ico) |
| `OSD_Enabled` | `0` | Show floating overlay on toggle |
| `OSD_Position` | `bottom` | OSD position: `top`, `bottom`, or `center` |
| `OSD_Duration` | `1500` | OSD display time in milliseconds (min 500) |
| `LEDIndicator` | _(empty)_ | Keyboard LED to sync: `scrolllock`, `capslock`, or `numlock` |
| `DeafenHotkey` | _(empty)_ | Hotkey for deafen mode (empty = disabled) |

### Hotkey Syntax

Modifier symbols: `#` = Win, `^` = Ctrl, `!` = Alt, `+` = Shift

Examples:
- `^!m` → Ctrl + Alt + M
- `#+a` → Win + Shift + A
- `F13` → F13 key

If the hotkey string is invalid, MicMute falls back to tray-only mode (left-click the icon to toggle).

You can also change the hotkey at runtime via Tray → **Change Hotkey...**.

## Tray Menu

| Item | Action |
|------|--------|
| Toggle Mute | Mute/unmute the mic |
| Hotkey: ... | Shows current hotkey (informational) |
| Mode → | Submenu: Toggle, Push-to-Talk, Push-to-Mute, Hybrid |
| Microphone → | Submenu: System Default + detected devices |
| Change Hotkey... | Open dialog to rebind hotkey at runtime |
| Sound Feedback | Toggle audible beep/sound on mute/unmute |
| Mute Lock | Prevent external apps from changing mute state |
| On-Screen Display | Toggle floating overlay on mute/unmute |
| Run at Startup | Toggle Windows startup shortcut |
| Reinitialise Mic | Manually reconnect to audio device |
| Sound Settings... | Open Windows Sound Settings |
| v1.3.0 | Version (informational) |
| Exit | Close MicMute |

### Modes

- **Toggle** (default): Press the hotkey to flip mute on/off.
- **Push-to-Talk**: Hold the hotkey to unmute. Release to re-mute. (30s safety timeout)
- **Push-to-Mute**: Hold the hotkey to mute. Release to re-unmute. (30s safety timeout)
- **Hybrid (PTT/Toggle)**: Short press (<300ms) toggles mute. Long press activates push-to-talk. Eliminates mode switching.

### Deafen Mode

Set `DeafenHotkey` in MicMute.ini to enable a separate hotkey that mutes both your microphone and speakers simultaneously. Press again to restore both to their previous state. The tray tooltip shows `[DEAFENED]` when active.

### Mute Lock

When enabled, MicMute prevents other applications from changing your mic mute state. If an app tries to unmute/mute your mic, MicMute immediately re-applies your chosen state. Toggle via tray menu or set `MuteLock=1` in the INI.

### On-Screen Display

When enabled, a floating overlay briefly appears on screen showing **MUTED** (red) or **ACTIVE** (green) whenever the mute state changes. The OSD is click-through and semi-transparent. Appears on the monitor where your mouse cursor is.

### Custom Sounds

Replace the default beep with your own `.wav` files. Set `MuteSound` and/or `UnmuteSound` to WAV file paths in MicMute.ini. Falls back to beep if the file is missing or invalid.

### Accessible Icons

Set `IconMuted` and `IconActive` to custom `.ico` file paths for colorblind-friendly alternatives. The default red/green icons can be difficult for the ~8% of males with red/green color deficiency.

### LED Sync

Set `LEDIndicator` to `scrolllock`, `capslock`, or `numlock` to sync a keyboard LED with the mute state. LED ON = mic muted. The original LED state is restored when MicMute exits.

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
| `mic_on.ico` | Tray icon — mic active (green) |
| `mic_off.ico` | Tray icon — mic muted (red) |
| `MicMute.ini` | User config (auto-created, gitignored) |

## License

[MIT](LICENSE)
