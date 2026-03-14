# MicMute — CLAUDE.md

## Project Overview

Windows system tray utility providing global hotkey microphone mute/unmute via COM automation (Windows Core Audio APIs). Built in AutoHotkey v2.

**Repo:** https://github.com/itsnateai/MicMute (public — open source final release)

## Stack

- **Language:** AutoHotkey v2
- **Platform:** Windows 10/11
- **APIs:** Windows Core Audio COM (IAudioEndpointVolume, IMMDeviceEnumerator)
- **Build:** Ahk2Exe (compiler at `X:/_Projects/_tools/Ahk/Ahk2Exe.exe`)

## Key Files

| File | Purpose |
|------|---------|
| `MicMute.ahk` | Main script — all logic, GUI, COM calls |
| `mic_on.ico` / `mic_off.ico` | Tray icons (embedded in compiled .exe) |
| `CHANGELOG.md` | Full version history |
| `FINAL_REPORT.md` | Project finalization report |

## Build / Run

```bash
# Run (requires AutoHotkey v2)
autohotkey MicMute.ahk

# Compile to standalone .exe
MSYS_NO_PATHCONV=1 "X:/_Projects/_tools/Ahk/Ahk2Exe.exe" /in MicMute.ahk /out MicMute.exe /icon mic_on.ico /compress 0 /silent
```

## Architecture Notes

- **COM pattern:** IMMDeviceEnumerator → IMMDevice → IAudioEndpointVolume. All vtable indices verified against Windows SDK.
- **Degraded mode:** If no mic on startup, script runs in tray-only mode and auto-recovers via 5s periodic check.
- **Icon embedding:** `@Ahk2Exe-AddResource mic_on.ico, 10` / `@Ahk2Exe-AddResource mic_off.ico, 11`. Referenced at runtime via `TraySetIcon(A_ScriptFullPath, -10/11, true)`.
- **Settings persistence:** MicMute.ini (auto-created, gitignored). All keys have safe defaults.
- **Notifications:** ToolTip bubbles (not TrayTip) with SetTimer auto-dismiss. 5s for errors, 3s for info.

## Known Patterns & Gotchas

- **AHK v2 global scoping (CRITICAL — audit trap):** Functions that ASSIGN to a global variable MUST declare it with `global`. Reading a global without declaring it works fine (resolves to the global). But the moment you ASSIGN to it (`g_foo := value`), AHK v2 silently creates a local shadow — no error, no warning, the global is never touched. **This bug survived 6 audits by 3 different Claudes.** The mute lock debounce (`g_lockDebounce`) was broken in BOTH `SyncMuteState()` and `ToggleDeafen()` — the feature never actually worked since implementation. **Audit procedure:** For every function, grep for every `g_` variable that appears on the LEFT side of `:=`. Verify each one is in that function's `global` declaration. Read-only access (right side of `:=`, `if` conditions) does NOT need a declaration and won't create a shadow.
- **COM HRESULT checking:** Always check return from GetMute/SetMute — stale device handles silently return incorrect state.
- **Mouse hooks overhead:** System-wide mouse hook for scroll events adds ~0.5% idle CPU. Use tray notification callbacks instead.
- **Hotkey GUI control:** AHK's Hotkey control can't represent bare keys like `\` or `]`. Returns empty `.Value` in those cases — preserve the old binding when empty.
- **OSD positioning:** Uses `Shell_TrayWnd` + `A_ScreenWidth` for primary monitor placement only. NOT multi-monitor aware despite what old docs said.
- **Sync interval:** 5s periodic sync is the right balance — 3s was too frequent, 10s felt unresponsive.

## Status

**v1.8.3 — Audit fix release (2026-03-13)**

Deep audit found mute lock debounce completely broken (AHK v2 global scoping bugs in both SyncMuteState and ToggleDeafen), static GUID buffers for hot-path allocation, Explorer restart recovery, INI encoding data loss risk, removed dead code. See CHANGELOG.md for details.
This project is public open source. No further active development planned.
