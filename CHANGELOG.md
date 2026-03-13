# Changelog

All notable changes to MicMute are documented here.

## [1.8.2] - 2026-03-13

### Fixed
- **Header version mismatch** — file header said v1.8.0 while `g_version` was v1.8.1. Both now v1.8.2
- **ToggleDeafen missing global** — `g_lockDebounce` was not in the `global` declaration of `ToggleDeafen()`, causing a local shadow. Mute lock debounce didn't propagate when exiting deafen mode with mute lock enabled
- **PopulateDeviceMenu error safety** — COM device enumeration in `PopulateDeviceMenu()` now wrapped in `try` to prevent errors from silently breaking the tray notification message handler

## [1.8.1] - 2026-03-12

### Fixed
- **Help window hotkey text** — default hotkey shown as "Right-Alt + Comma" corrected to "Win+Shift+A"
- **OSD duration default** — initial value of `g_osdDuration` corrected from 800ms to 1500ms to match INI default, README, and Settings GUI
- **Help text OSD position** — description updated from "top-right corner" to "above the taskbar" (accurate to actual placement)
- **FINAL_REPORT filename casing** — corrected `micmute.ahk` reference to `MicMute.ahk`

## [1.8.0] - 2026-03-10

### Added
- **Help Window** — comprehensive in-app help accessible from Settings GUI. Covers all features: modes, deafen, hotkeys, settings, custom files, and troubleshooting. Resizable window with scrollable content.

### Fixed
- **Default hotkey restored** — default hotkey reverted to Win+Shift+A (`#+a`) as intended.
- **Unmute-on-exit bug** — fixed cleanup edge case from audit.
- **CHANGELOG gaps** — filled missing documentation from prior releases.

## [1.7.0] - 2026-03-10

### Changed
- **Removed scroll-to-volume** — mic volume scroll via mouse wheel over tray icon removed. It required a system-wide mouse hook, causing ~0.5% idle CPU overhead and interfering with normal scroll behaviour. Middle-click mode toggle is now handled via a zero-overhead tray notification callback instead.
- **Sync timer** — periodic mute-state sync interval increased from 3 s to 5 s (reduces background wakeups while remaining responsive).
- Version bumped to 1.7.0

## [1.6.0] - 2026-03-09

### Changed
- **ToolTip notifications** — all user-facing notifications now use floating ToolTip bubbles instead of Windows toast notifications (TrayTip). Non-intrusive and auto-dismiss.
- **Embedded icons** — .ico files are embedded as PE resources in the compiled .exe via `@Ahk2Exe-AddResource`. No external icon files needed for standalone use.
- **Icon fallback chain** — custom INI path → .ico on disk → embedded PE resource → Windows built-in icons. Works in all scenarios.
- **Settings GUI** — title bar shows version, GitHub button opens repo page.
- Version bumped to 1.6.0

### Added
- **Show Tray Icon** section in README — instructions for pinning MicMute to the Windows taskbar tray.

## [1.5.0] - 2026-03-09

### Added
- **Settings GUI** — full settings window (`Settings…` in tray menu) for all options: behavior, OSD, hotkeys, custom files. Replaces manual INI editing. Includes OK / Apply / Cancel buttons with ToolTip feedback on Apply.
- **Startup mute options** — 4-option dropdown: "Don't change", "Always muted", "Always unmuted", "Remember last". Persists mute state across restarts when set to "Remember last".
- **Mic volume scroll** — scroll wheel over tray icon adjusts microphone input volume in 5% steps, event-driven via tray hover detection.
- **Middle-click mode toggle** — middle-click tray icon to switch between Toggle and Push-to-Talk modes with a single distinct tone per mode (1175Hz for Toggle, 1568Hz for PTT).
- **Deafen hotkey capture** — Settings GUI uses a proper Hotkey capture control (press Alt+L and it shows the combo) plus a "WinKey…" popup button for manual Win key combo entry.
- **Browse/Clear buttons** — custom icon and sound file paths use Browse/Clear buttons with filename labels instead of raw Edit boxes.

### Fixed
- **LoadConfig/SaveConfig `global` declarations** — functions had incomplete global lists causing settings (especially StartMuted) to silently fail to save/load. Fixed with bare `global` statement.
- **Middle-click crash** — tray icon middle-click caused 0xc0000005 access violation after ~5 clicks. Fixed ClearTrayHover timer and added try-catch around ComCall in AdjustMicVolume.
- **Middle-click not working until right-click** — tray hover timer was too short (300ms). Increased to 1500ms.
- **PTT→Toggle mode switch** — hotkey still acted as PTT after switching modes via right-click menu until script was restarted. Fixed by properly re-registering hotkey on mode change.
- **Device name truncation** — long microphone names in the Mic Source tray submenu expanded the context menu excessively. Names now truncated at 40 characters.

### Removed
- **LED sync (F-16)** — keyboard LED indicator feature removed entirely. Was unreliable and interfered with actual key function (CapsLock, ScrollLock, NumLock).
- **Hybrid mode (F-06)** — removed in favor of middle-click mode switching between Toggle and PTT.

### Changed
- Version bumped to 1.5.0
- Tray menu reorganized: Mode/Mic Source submenus, Settings item, separators
- Settings GUI layout tightened — less wasted space for file selectors
- Only Toggle and Push-to-Talk modes available (removed Hybrid and Push-to-Mute)

## [1.3.0] - 2026-03-08

### Added
- **F-02**: On-screen display — floating MUTED/ACTIVE overlay on toggle, click-through, configurable position and duration
- **F-04**: Custom sound files — replace default beep with .wav files via MuteSound/UnmuteSound config, with beep fallback
- **F-06**: Hybrid PTT/Toggle mode — short press (<300ms) toggles, long press activates push-to-talk, eliminates mode switching
- **F-10**: Unmute on exit — auto-unmutes mic in Cleanup() before releasing COM, prevents "dead mic" after quitting
- **F-11**: Mute lock — prevents external apps from changing mute state, with debounce to avoid infinite toggle war
- **F-13**: Live hotkey rebinding — "Change Hotkey..." dialog in tray menu, supports both standard and Win key combos
- **F-16**: Keyboard LED sync — sync ScrollLock/CapsLock/NumLock with mute state, saves and restores initial LED state
- **F-17**: Accessible icon colors — configurable .ico paths via IconMuted/IconActive for colorblind users
- **F-20**: Deafen mode — separate hotkey mutes mic + speakers simultaneously, restores speaker state on un-deafen

### Changed
- Version bumped to 1.3.0
- Tray menu now includes Change Hotkey, Mute Lock, On-Screen Display items
- Mode submenu now includes Hybrid (PTT/Toggle) option
- MicMute.ini now stores 12 additional config keys (all backward-compatible defaults)
- SoundBeep calls replaced with PlayFeedback() function supporting custom WAV files
- Header comment block updated with full feature list

## [1.2.0] - 2026-03-08

### Added
- **P2-01**: Push-to-talk / push-to-mute mode — hold hotkey to temporarily unmute (PTT) or mute (PTM), with 30s safety timeout
- **P2-02**: Audio device selector — tray submenu enumerates capture devices via COM IMMDeviceEnumerator, persists choice in INI
- **P4-03**: Tray icon flash on toggle — 3-cycle flash animation draws attention to mute state changes

### Changed
- Version bumped to 1.2.0
- Tray menu now includes Mode submenu (Toggle / Push-to-Talk / Push-to-Mute) and Microphone submenu (device picker)
- MicMute.ini now stores Mode and DeviceId settings
- InitMicEndpoint supports specific device ID via IMMDeviceEnumerator::GetDevice, falls back to system default
- ExtractKeyName strips all AHK prefix characters (~*$<> in addition to #^!+)
- FlashIcon restarts cleanly on overlapping toggles instead of dropping the second flash

## [1.1.0] - 2026-03-08

### Fixed
- **P0-01**: Script no longer crashes on startup if no mic is connected — starts in degraded state with recovery via tray menu
- **P0-02**: GetMute COM calls now check HRESULT — stale device no longer causes incorrect mute state
- **P0-03**: Invalid hotkey string no longer crashes on startup — falls back to tray-only mode with error message
- **P1-04**: Documented the Sleep(150) delay before SyncTray (tray icon registration timing)
- **P1-06**: Replaced ternary operators with if/else for TraySetIcon calls

### Added
- **P1-01**: Auto-detect mic plug/unplug — periodic check reconnects automatically without user intervention
- **P1-02**: Periodic mute state sync — tray icon stays accurate when other apps change mic mute
- **P1-03**: TrayTip confirmation after successful mic reinitialisation
- **P1-05**: Version string (v1.1.0) displayed in tray menu and tooltip
- **P2-03**: Sound feedback — audible beep on toggle (low tone = muted, high tone = active), toggleable via tray menu
- **P2-04**: Run at Startup — tray menu toggle to create/remove Windows startup shortcut
- **P2-05**: Config file support — settings stored in MicMute.ini (auto-created when changed via tray menu)
- **P4-02**: Mute on lock — optional auto-mute when PC locks (Win+L), enable via MicMute.ini
- **P4-04**: Added note about HotkeyToReadable() duplication with MWBToggle

### Changed
- OnExit(Cleanup) moved before first COM call to prevent resource leaks
- Error dialogs now suggest Tray → Reinitialise Mic instead of crashing
- Tray tooltip shows version number and current mute state
- Tray menu expanded with Sound Feedback, Run at Startup, and version display

## [1.0.0] - 2026-03-06

### Added
- Initial release
- Global hotkey mute/unmute toggle (Win+Shift+A default)
- System tray icon (green = active, red = muted)
- Left-click tray to toggle, right-click for menu
- Manual mic reinitialisation via tray menu
- Custom icon support (mic_on.ico / mic_off.ico)
