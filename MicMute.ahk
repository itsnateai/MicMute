; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  MicMute.ahk  —  Global microphone mute toggle                         ║
; ║  Version: 1.1.0                                                         ║
; ║  Requires: AutoHotKey v2  (https://www.autohotkey.com/)                ║
; ║                                                                          ║
; ║  • Left-click  tray icon  → toggle mute                                 ║
; ║  • Right-click tray icon  → menu (toggle / reinitialise / sound / exit) ║
; ║  • Hotkey below           → toggle mute from anywhere                   ║
; ║  • Green icon = mic active  |  Red icon = mic muted                     ║
; ║                                                                          ║
; ║  Files (place in the same folder as this script):                       ║
; ║    mic_on.ico   — shown when mic is active  (falls back to AHK default) ║
; ║    mic_off.ico  — shown when mic is muted   (falls back to AHK default) ║
; ║    MicMute.ini  — optional config file (auto-created via tray menu)     ║
; ║                                                                          ║
; ║  Note: MicMute auto-detects when you change or unplug your mic.        ║
; ║  You can also use Tray → "Reinitialise Mic" to manually reconnect.     ║
; ╚══════════════════════════════════════════════════════════════════════════╝

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ── CONFIGURATION ────────────────────────────────────────────────────────────
;  Version string displayed in tray menu and tooltip.
global g_version := "1.1.0"

;  Defaults — overridden by MicMute.ini if present.
;  Change g_hotkey to whatever combo you prefer.
;  Modifier symbols:  #=Win  ^=Ctrl  !=Alt  +=Shift
;  Examples:
;    "^!m"   →  Ctrl + Alt + M
;    "#+a"   →  Win  + Shift + A
;    "F13"   →  F13 key (if your keyboard has it)
global g_hotkey        := "#+a"
global g_soundFeedback := true
global g_muteOnLock    := false

; Load overrides from INI (if it exists)
LoadConfig()

; ── AUDIO SETUP ──────────────────────────────────────────────────────────────
; Uses Windows Core Audio (IAudioEndpointVolume) via proper CoCreateInstance.
; This mutes the default microphone at the OS level — affects ALL apps.
;
; IAudioEndpointVolume vtable indices (IUnknown takes 0-2):
;   14 = SetMute(BOOL bMute, LPCGUID pguidEventContext)
;   15 = GetMute(BOOL *pbMute)

global g_pAEV := InitMicEndpoint()

; Register cleanup BEFORE any further COM calls so the pointer
; is always released even if something below throws.
OnExit(Cleanup)

; Read initial mute state
global g_muted := false
if g_pAEV {
    hr := ComCall(15, g_pAEV, "Int*", &_initMuted := 0, "Int")   ; GetMute
    g_muted := (hr = 0 && _initMuted != 0)
}

; ── TRAY ICONS ───────────────────────────────────────────────────────────────
; Place mic_on.ico and mic_off.ico in the same folder as this script.
; If either file is missing, a Windows built-in icon is used as a fallback.
global g_icoGreen := FileExist(A_ScriptDir "\mic_on.ico")  ? A_ScriptDir "\mic_on.ico"  : ""
global g_icoRed   := FileExist(A_ScriptDir "\mic_off.ico") ? A_ScriptDir "\mic_off.ico" : ""

; ── TRAY MENU ────────────────────────────────────────────────────────────────
BuildTrayMenu()

; ── HOTKEY ───────────────────────────────────────────────────────────────────
; Validate the hotkey string — fall back to tray-only mode on error (P0-03).
try {
    Hotkey(g_hotkey, (*) => ToggleMute())
} catch as e {
    MsgBox("Invalid hotkey: `"" g_hotkey "`"`n`n" e.Message
        . "`n`nFalling back to tray-only mode."
        . "`nEdit the hotkey in MicMute.ini or MicMute.ahk line 38.", "MicMute", "Icon!")
}

; ── INITIALISE ICON ──────────────────────────────────────────────────────────
; Brief delay so the shell has time to register the new tray icon
; before we attempt to change it — without this, SyncTray() can
; silently fail to update the icon on first run.
Sleep(150)
SyncTray()

; Show a brief tooltip if no mic was found so the user knows what's up
if !g_pAEV {
    TrayTip("No microphone detected.`nPlug one in — MicMute will auto-detect it.", "MicMute", "Icon!")
    SetTimer(() => TrayTip(), -5000)   ; dismiss after 5 seconds
}

; ── PERIODIC SYNC ────────────────────────────────────────────────────────────
; Every 3 seconds, verify the audio endpoint is still valid and sync
; the tray icon if another app (or Windows Settings) changed the mute state.
; Handles both device hotplug (P1-01) and external mute changes (P1-02).
SetTimer(SyncMuteState, 3000)

; ── MUTE ON LOCK ─────────────────────────────────────────────────────────────
; Auto-mute when the workstation locks (Win+L). Requires g_muteOnLock = true.
; Set MuteOnLock=1 in MicMute.ini to enable.
if g_muteOnLock {
    DllCall("Wtsapi32\WTSRegisterSessionNotification", "Ptr", A_ScriptHwnd, "UInt", 0)
    OnMessage(0x02B1, OnSessionChange)   ; WM_WTSSESSION_CHANGE
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Core functions                                                          ║
; ╚══════════════════════════════════════════════════════════════════════════╝

ToggleMute() {
    global g_muted, g_pAEV, g_soundFeedback
    if !g_pAEV {
        MsgBox("No microphone endpoint is available.`n`nTry Tray → Reinitialise Mic.", "MicMute", "Icon!")
        return
    }
    newState := !g_muted
    hr := ComCall(14, g_pAEV, "Int", newState, "Ptr", 0, "Int")   ; SetMute
    if (hr != 0) {
        MsgBox("SetMute failed (0x" Format("{:08X}", hr & 0xFFFFFFFF) ")."
            . "`n`nYour audio device may have changed."
            . "`n`nUse Tray → Reinitialise Mic, or restart the script.", "MicMute", "Icon!")
        return
    }
    g_muted := newState
    SyncTray()
    ; Audible feedback — low tone for muted, high tone for active (P2-03)
    if g_soundFeedback
        SoundBeep(g_muted ? 400 : 800, 100)
}

SyncTray() {
    global g_muted, g_icoGreen, g_icoRed, g_version
    if g_muted {
        ; Red / muted — use custom icon or fall back to a built-in "blocked" icon
        if (g_icoRed != "")
            TraySetIcon(g_icoRed)
        else
            TraySetIcon("shell32.dll", 131)
        A_IconTip := "MicMute v" g_version " — Mic: MUTED"
    } else {
        ; Green / active — use custom icon or fall back to a built-in microphone icon
        if (g_icoGreen != "")
            TraySetIcon(g_icoGreen)
        else
            TraySetIcon("imageres.dll", 109)
        A_IconTip := "MicMute v" g_version " — Mic: Active"
    }
}

; Periodically check if the mic endpoint is still valid and if the mute
; state has changed externally (e.g. via Windows Sound Settings).
; Handles device hotplug (P1-01) and external mute sync (P1-02).
SyncMuteState() {
    global g_pAEV, g_muted
    if !g_pAEV {
        ; No mic currently — try to find one that may have been plugged in
        g_pAEV := InitMicEndpoint(true)   ; silent mode — no MsgBox
        if !g_pAEV
            return
        ; New device found — read its mute state
        TrayTip("Microphone detected — auto-connected.", "MicMute", "Iconi")
        SetTimer(() => TrayTip(), -3000)
        hr := ComCall(15, g_pAEV, "Int*", &_initMuted := 0, "Int")
        g_muted := (hr = 0 && _initMuted != 0)
        SyncTray()
        return
    }
    ; Check if device is still valid by reading mute state
    try {
        hr := ComCall(15, g_pAEV, "Int*", &currentMute := 0, "Int")   ; GetMute
    } catch {
        hr := -1
    }
    if (hr != 0) {
        ; Device went away — release stale pointer and show notification
        ObjRelease(g_pAEV)
        g_pAEV := 0
        g_muted := false
        SyncTray()
        TrayTip("Microphone disconnected.`nWill auto-reconnect when available.", "MicMute", "Icon!")
        SetTimer(() => TrayTip(), -5000)
        return
    }
    ; Sync tray if an external app changed the mute state
    externalMuted := (currentMute != 0)
    if (externalMuted != g_muted) {
        g_muted := externalMuted
        SyncTray()
    }
}

; Re-acquire the default mic endpoint (manual reinit from tray menu).
ReinitMic() {
    global g_pAEV, g_muted
    if g_pAEV {
        ObjRelease(g_pAEV)
        g_pAEV := 0
    }
    g_pAEV := InitMicEndpoint()
    if !g_pAEV
        return   ; InitMicEndpoint already showed an error box
    ; Re-read the current mute state from the new endpoint
    hr := ComCall(15, g_pAEV, "Int*", &_muted := 0, "Int")   ; GetMute
    g_muted := (hr = 0 && _muted != 0)
    SyncTray()
    TrayTip("Microphone reinitialised.", "MicMute", "Iconi")
    SetTimer(() => TrayTip(), -3000)
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Tray menu                                                               ║
; ╚══════════════════════════════════════════════════════════════════════════╝

BuildTrayMenu() {
    global g_hotkey, g_version, g_soundFeedback
    hotkeyLabel := "Hotkey: " HotkeyToReadable(g_hotkey)

    A_TrayMenu.Delete()
    A_TrayMenu.Add("Toggle Mute",       (*) => ToggleMute())
    A_TrayMenu.Add(hotkeyLabel,          (*) => 0)
    A_TrayMenu.Disable(hotkeyLabel)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Sound Feedback",     (*) => ToggleSoundFeedback())
    if g_soundFeedback
        A_TrayMenu.Check("Sound Feedback")
    A_TrayMenu.Add()
    A_TrayMenu.Add("Run at Startup",     (*) => ToggleStartup())
    if FileExist(A_Startup "\MicMute.lnk")
        A_TrayMenu.Check("Run at Startup")
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reinitialise Mic",   (*) => ReinitMic())
    A_TrayMenu.Add("Sound Settings…",    (*) => Run("ms-settings:sound"))
    A_TrayMenu.Add()
    A_TrayMenu.Add("v" g_version,        (*) => 0)
    A_TrayMenu.Disable("v" g_version)
    A_TrayMenu.Add("Exit",               (*) => ExitApp())
    A_TrayMenu.Default    := "Toggle Mute"
    A_TrayMenu.ClickCount := 1           ; single left-click fires default item
}

ToggleSoundFeedback() {
    global g_soundFeedback
    g_soundFeedback := !g_soundFeedback
    if g_soundFeedback
        A_TrayMenu.Check("Sound Feedback")
    else
        A_TrayMenu.Uncheck("Sound Feedback")
    SaveConfig()
}

ToggleStartup() {
    shortcut := A_Startup "\MicMute.lnk"
    if FileExist(shortcut) {
        FileDelete(shortcut)
        A_TrayMenu.Uncheck("Run at Startup")
        TrayTip("Startup shortcut removed.", "MicMute", "Iconi")
    } else {
        ; Create shortcut — works for both compiled .exe and raw .ahk
        if A_IsCompiled {
            FileCreateShortcut(A_ScriptFullPath, shortcut, A_ScriptDir,
                , "MicMute — Global mic mute toggle", A_ScriptFullPath)
        } else {
            FileCreateShortcut(A_AhkPath, shortcut, A_ScriptDir,
                '`"' A_ScriptFullPath '`"', "MicMute — Global mic mute toggle")
        }
        A_TrayMenu.Check("Run at Startup")
        TrayTip("Will start with Windows.", "MicMute", "Iconi")
    }
    SetTimer(() => TrayTip(), -3000)
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Configuration (INI file)                                                ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Read settings from MicMute.ini if it exists. Falls back to defaults.
LoadConfig() {
    global g_hotkey, g_soundFeedback, g_muteOnLock
    ini := A_ScriptDir "\MicMute.ini"
    if !FileExist(ini)
        return
    g_hotkey        := IniRead(ini, "General", "Hotkey", g_hotkey)
    g_soundFeedback := (IniRead(ini, "General", "SoundFeedback", "1") = "1")
    g_muteOnLock    := (IniRead(ini, "General", "MuteOnLock", "0") = "1")
}

; Save current settings to MicMute.ini.
SaveConfig() {
    global g_hotkey, g_soundFeedback, g_muteOnLock
    ini := A_ScriptDir "\MicMute.ini"
    IniWrite(g_hotkey, ini, "General", "Hotkey")
    IniWrite(g_soundFeedback ? "1" : "0", ini, "General", "SoundFeedback")
    IniWrite(g_muteOnLock ? "1" : "0", ini, "General", "MuteOnLock")
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Windows API helpers                                                     ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Translate AHK hotkey symbols into a readable string e.g. "#+a" → "Win + Shift + A"
; Uses RegExMatch to isolate the leading modifier prefix so key names like
; "Numpad+" are never confused with the Shift modifier symbol.
; NOTE: Shared with MWBToggle — consider a shared library if more scripts need this.
HotkeyToReadable(hk) {
    mods   := ""
    prefix := RegExMatch(hk, "^([#^!+]+)", &m) ? m[1] : ""
    key    := RegExReplace(hk, "^[#^!+]+", "")
    if (InStr(prefix, "#"))
        mods .= "Win + "
    if (InStr(prefix, "^"))
        mods .= "Ctrl + "
    if (InStr(prefix, "!"))
        mods .= "Alt + "
    if (InStr(prefix, "+"))
        mods .= "Shift + "
    return mods . StrUpper(key)
}

; Handle workstation lock/unlock for auto-mute (P4-02).
; Only active when g_muteOnLock = true and WTS notifications are registered.
OnSessionChange(wParam, lParam, msg, hwnd) {
    global g_pAEV, g_muted
    ; WTS_SESSION_LOCK = 0x7
    if (wParam = 0x7 && g_pAEV && !g_muted) {
        hr := ComCall(14, g_pAEV, "Int", true, "Ptr", 0, "Int")   ; SetMute
        if (hr = 0) {
            g_muted := true
            SyncTray()
        }
    }
}

; Initialise IAudioEndpointVolume for the default capture (mic) device.
; Returns the COM pointer on success, or 0 on failure (shows a message box
; but does NOT exit — the script stays alive so the user can reinitialise).
; If silent=true, suppresses MsgBox dialogs (used by periodic auto-detect).
InitMicEndpoint(silent := false) {
    CLSID_MMEnum := Buffer(16)
    IID_MMEnum   := Buffer(16)
    IID_AEV      := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", "{BCDE0395-E52F-467C-8E3D-C4579291692E}", "Ptr", CLSID_MMEnum)
    DllCall("ole32\CLSIDFromString", "WStr", "{A95664D2-9614-4F35-A746-DE8DB63617E6}", "Ptr", IID_MMEnum)
    DllCall("ole32\CLSIDFromString", "WStr", "{5CDF2C82-841E-4546-9722-0CF74078229A}", "Ptr", IID_AEV)

    hr := DllCall("ole32\CoCreateInstance",
        "Ptr",  CLSID_MMEnum,
        "Ptr",  0,
        "UInt", 1,
        "Ptr",  IID_MMEnum,
        "Ptr*", &pEnum := 0,
        "Int")
    if (hr != 0 || !pEnum) {
        if !silent
            MsgBox("CoCreateInstance failed: 0x" Format("{:08X}", hr & 0xFFFFFFFF) "`n`nUse Tray → Reinitialise Mic after connecting a microphone.", "MicMute", "Icon!")
        return 0
    }

    hr := ComCall(4, pEnum, "UInt", 1, "UInt", 0, "Ptr*", &pDev := 0, "Int")
    ObjRelease(pEnum)
    if (hr != 0 || !pDev) {
        if !silent
            MsgBox("GetDefaultAudioEndpoint failed: 0x" Format("{:08X}", hr & 0xFFFFFFFF) "`n`nMake sure a microphone is connected, then use Tray → Reinitialise Mic.", "MicMute", "Icon!")
        return 0
    }

    hr := ComCall(3, pDev, "Ptr", IID_AEV, "UInt", 23, "Ptr", 0, "Ptr*", &pAEV := 0, "Int")
    ObjRelease(pDev)
    if (hr != 0 || !pAEV) {
        if !silent
            MsgBox("Activate IAudioEndpointVolume failed: 0x" Format("{:08X}", hr & 0xFFFFFFFF) "`n`nUse Tray → Reinitialise Mic to retry.", "MicMute", "Icon!")
        return 0
    }

    return pAEV
}

; Release COM handle and clean up on exit.
Cleanup(*) {
    global g_pAEV, g_muteOnLock
    if g_muteOnLock
        DllCall("Wtsapi32\WTSUnRegisterSessionNotification", "Ptr", A_ScriptHwnd)
    if g_pAEV
        ObjRelease(g_pAEV)
}
