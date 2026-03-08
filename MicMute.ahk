; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  MicMute.ahk  —  Global microphone mute toggle                         ║
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
; ║                                                                          ║
; ║  Note: If you change or unplug your default audio device while the      ║
; ║  script is running, use Tray → "Reinitialise Mic" to reattach,          ║
; ║  or simply restart the script.                                           ║
; ╚══════════════════════════════════════════════════════════════════════════╝

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ── CONFIGURATION ────────────────────────────────────────────────────────────
;  Change g_hotkey to whatever combo you prefer.
;  Modifier symbols:  #=Win  ^=Ctrl  !=Alt  +=Shift
;  Examples:
;    "^!m"   →  Ctrl + Alt + M
;    "#+a"   →  Win  + Shift + A
;    "F13"   →  F13 key (if your keyboard has it)
global g_hotkey := "#+a"

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
hotkeyLabel := "Hotkey: " HotkeyToReadable(g_hotkey)
A_TrayMenu.Delete()
A_TrayMenu.Add("Toggle Mute",      (*) => ToggleMute())
A_TrayMenu.Add(hotkeyLabel,        (*) => 0)
A_TrayMenu.Disable(hotkeyLabel)
A_TrayMenu.Add()
A_TrayMenu.Add("Reinitialise Mic",  (*) => ReinitMic())
A_TrayMenu.Add("Sound Settings…",  (*) => Run("ms-settings:sound"))
A_TrayMenu.Add("Exit",              (*) => ExitApp())
A_TrayMenu.Default    := "Toggle Mute"
A_TrayMenu.ClickCount := 1    ; single left-click fires default item

; ── HOTKEY ───────────────────────────────────────────────────────────────────
Hotkey(g_hotkey, (*) => ToggleMute())

; ── INITIALISE ICON ──────────────────────────────────────────────────────────
Sleep(150)
SyncTray()

; Show a brief tooltip if no mic was found so the user knows what's up
if !g_pAEV {
    TrayTip("No microphone detected.`nPlug one in and use Tray → Reinitialise Mic.", "MicMute", "Icon!")
    SetTimer(() => TrayTip(), -5000)   ; dismiss after 5 seconds
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Core functions                                                          ║
; ╚══════════════════════════════════════════════════════════════════════════╝

ToggleMute() {
    global g_muted, g_pAEV
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
}

SyncTray() {
    global g_muted, g_icoGreen, g_icoRed
    if g_muted {
        ; Red / muted — use custom icon or fall back to a built-in "blocked" icon
        (g_icoRed != "") ? TraySetIcon(g_icoRed) : TraySetIcon("shell32.dll", 131)
        A_IconTip := "Mic: MUTED"
    } else {
        ; Green / active — use custom icon or fall back to a built-in microphone icon
        (g_icoGreen != "") ? TraySetIcon(g_icoGreen) : TraySetIcon("imageres.dll", 109)
        A_IconTip := "Mic: Active"
    }
}

; Re-acquire the default mic endpoint (call after changing/unplugging audio device).
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
; ║  Windows API helpers                                                     ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Translate AHK hotkey symbols into a readable string e.g. "#+a" → "Win + Shift + A"
; Uses RegExMatch to isolate the leading modifier prefix so key names like
; "Numpad+" are never confused with the Shift modifier symbol.
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

; Initialise IAudioEndpointVolume for the default capture (mic) device.
; Returns the COM pointer on success, or 0 on failure (shows a message box
; but does NOT exit — the script stays alive so the user can reinitialise).
InitMicEndpoint() {
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
        MsgBox("CoCreateInstance failed: 0x" Format("{:08X}", hr & 0xFFFFFFFF) "`n`nUse Tray → Reinitialise Mic after connecting a microphone.", "MicMute", "Icon!")
        return 0
    }

    hr := ComCall(4, pEnum, "UInt", 1, "UInt", 0, "Ptr*", &pDev := 0, "Int")
    ObjRelease(pEnum)
    if (hr != 0 || !pDev) {
        MsgBox("GetDefaultAudioEndpoint failed: 0x" Format("{:08X}", hr & 0xFFFFFFFF) "`n`nMake sure a microphone is connected, then use Tray → Reinitialise Mic.", "MicMute", "Icon!")
        return 0
    }

    hr := ComCall(3, pDev, "Ptr", IID_AEV, "UInt", 23, "Ptr", 0, "Ptr*", &pAEV := 0, "Int")
    ObjRelease(pDev)
    if (hr != 0 || !pAEV) {
        MsgBox("Activate IAudioEndpointVolume failed: 0x" Format("{:08X}", hr & 0xFFFFFFFF) "`n`nUse Tray → Reinitialise Mic to retry.", "MicMute", "Icon!")
        return 0
    }

    return pAEV
}

; Release COM handle on exit.
Cleanup(*) {
    global g_pAEV
    if g_pAEV
        ObjRelease(g_pAEV)
}
