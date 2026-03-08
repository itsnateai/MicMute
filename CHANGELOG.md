# Changelog

All notable changes to MicMute are documented here.

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
- README expanded with configuration guide, how-it-works, compilation, and OS-level mute note

## [1.0.0] - 2026-03-06

### Added
- Initial release
- Global hotkey mute/unmute toggle (Win+Shift+A default)
- System tray icon (green = active, red = muted)
- Left-click tray to toggle, right-click for menu
- Manual mic reinitialisation via tray menu
- Custom icon support (mic_on.ico / mic_off.ico)
