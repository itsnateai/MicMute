; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  MicMute.ahk  —  Global microphone mute toggle                         ║
; ║  Version: 1.2.0                                                         ║
; ║  Requires: AutoHotKey v2  (https://www.autohotkey.com/)                ║
; ║                                                                          ║
; ║  • Left-click  tray icon  → toggle mute                                 ║
; ║  • Right-click tray icon  → menu (toggle / reinitialise / sound / exit) ║
; ║  • Hotkey below           → toggle mute from anywhere                   ║
; ║  • Green icon = mic active  |  Red icon = mic muted                     ║
; ║                                                                          ║
; ║  Modes:                                                                  ║
; ║    Toggle (default) — press hotkey to flip mute on/off                  ║
; ║    Push-to-Talk     — hold hotkey to unmute, release to re-mute         ║
; ║    Push-to-Mute     — hold hotkey to mute, release to re-unmute        ║
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
global g_version := "1.2.0"

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
global g_mode          := "toggle"     ; "toggle", "push-to-talk", "push-to-mute"
global g_deviceId      := ""           ; empty = system default
global g_unmuteOnExit  := true         ; unmute mic when MicMute exits (F-10)
global g_iconMuted     := ""           ; custom .ico path for muted state (F-17)
global g_iconActive    := ""           ; custom .ico path for active state (F-17)
global g_ledIndicator  := ""           ; LED to sync: "scrolllock", "capslock", "numlock", or "" (F-16)
global g_muteSound     := ""           ; custom .wav for mute feedback (F-04)
global g_unmuteSound   := ""           ; custom .wav for unmute feedback (F-04)
global g_muteLock      := false        ; prevent external apps from changing mute state (F-11)
global g_lockDebounce  := false        ; skip one sync cycle after enforcement (F-11)
global g_hybridThreshold := 300        ; ms threshold: short press=toggle, long press=PTT (F-06)
global g_hybridPTTActive := false      ; set by timer when PTT activates in hybrid mode (F-06)
global g_osdEnabled    := false        ; show floating overlay on toggle (F-02)
global g_osdPosition   := "bottom"     ; OSD position: "top", "bottom", "center" (F-02)
global g_osdDuration   := 1500         ; OSD display time in ms (F-02)
global g_osdGui        := 0            ; GUI object reference for current OSD (F-02)
global g_deafenHotkey  := ""           ; separate hotkey for deafen mode (F-20)
global g_deafened      := false        ; true when deafened (mic + speakers muted) (F-20)
global g_ledInitialState := false      ; LED state at startup, for cleanup restore (F-16)
global g_speakerWasMuted := false      ; remember speaker state before deafen (F-20)

; Load overrides from INI (if it exists)
LoadConfig()

; Save LED state at startup before MicMute starts toggling it (F-16)
if (g_ledIndicator != "")
    g_ledInitialState := GetKeyState(g_ledIndicator, "T")

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
; Priority: custom INI path > mic_on/mic_off.ico > built-in fallback (F-17)
global g_icoGreen := (g_iconActive != "" && FileExist(g_iconActive)) ? g_iconActive
    : FileExist(A_ScriptDir "\mic_on.ico")  ? A_ScriptDir "\mic_on.ico"  : ""
global g_icoRed   := (g_iconMuted != "" && FileExist(g_iconMuted)) ? g_iconMuted
    : FileExist(A_ScriptDir "\mic_off.ico") ? A_ScriptDir "\mic_off.ico" : ""

; ── FLASH ANIMATION STATE ──────────────────────────────────────────────────
global g_flashing   := false   ; true while flash animation is running
global g_flashCount := 0       ; counts 0..5 (3 on/off cycles)

; ── TRAY MENU ────────────────────────────────────────────────────────────────
BuildTrayMenu()

; ── HOTKEY ───────────────────────────────────────────────────────────────────
; Validate the hotkey string — fall back to tray-only mode on error (P0-03).
RegisterHotkey()
RegisterDeafenHotkey()

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
    if (hr < 0) {
        MsgBox("SetMute failed (0x" Format("{:08X}", hr & 0xFFFFFFFF) ")."
            . "`n`nYour audio device may have changed."
            . "`n`nUse Tray → Reinitialise Mic, or restart the script.", "MicMute", "Icon!")
        return
    }
    g_muted := newState
    SyncTray()
    FlashIcon()
    ShowOSD()
    PlayFeedback()
}

; Set mute to a specific state (used by PTT/PTM on key release).
SetMuteState(muted) {
    global g_muted, g_pAEV
    if !g_pAEV
        return
    if (g_muted = muted)
        return
    hr := ComCall(14, g_pAEV, "Int", muted, "Ptr", 0, "Int")   ; SetMute
    if (hr < 0)
        return
    g_muted := muted
    SyncTray()
    FlashIcon()
    ShowOSD()
    PlayFeedback()
}

; Play audible feedback on toggle (F-04).
; Uses custom WAV files if configured, otherwise SoundBeep fallback.
PlayFeedback() {
    global g_muted, g_soundFeedback, g_muteSound, g_unmuteSound
    if !g_soundFeedback
        return
    soundFile := g_muted ? g_muteSound : g_unmuteSound
    if (soundFile != "" && FileExist(soundFile)) {
        try
            SoundPlay(soundFile, true)   ; synchronous — throws on bad file
        catch
            SoundBeep(g_muted ? 400 : 800, 100)   ; fallback on error
    } else {
        SoundBeep(g_muted ? 400 : 800, 100)
    }
}

; Show an on-screen display overlay indicating mute state (F-02).
; Borderless, always-on-top, click-through GUI that auto-dismisses.
ShowOSD() {
    global g_muted, g_osdEnabled, g_osdPosition, g_osdDuration, g_osdGui
    if !g_osdEnabled
        return
    ; Destroy previous OSD if still showing
    if g_osdGui {
        try g_osdGui.Destroy()
        g_osdGui := 0
    }
    ; Create borderless, always-on-top, click-through GUI
    osd := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    osd.BackColor := g_muted ? "CC0000" : "00AA00"
    osd.MarginX := 20
    osd.MarginY := 10
    label := g_muted ? "MUTED" : "ACTIVE"
    osd.SetFont("s24 cFFFFFF bold", "Segoe UI")
    osd.Add("Text", "Center", label)
    ; Show first to get dimensions, then reposition
    osd.Show("NoActivate AutoSize")
    osd.GetPos(, , &osdW, &osdH)
    ; Find the monitor the mouse cursor is on (multi-monitor aware)
    MouseGetPos(&mx, &my)
    monNum := 1
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &_l, &_t, &_r, &_b)
        if (mx >= _l && mx < _r && my >= _t && my < _b) {
            monNum := A_Index
            break
        }
    }
    MonitorGetWorkArea(monNum, &workL, &workT, &workR, &workB)
    xPos := workL + ((workR - workL - osdW) // 2)
    if (g_osdPosition = "top")
        yPos := workT + 50
    else if (g_osdPosition = "center")
        yPos := workT + ((workB - workT - osdH) // 2)
    else   ; bottom (default)
        yPos := workB - osdH - 50
    osd.Show("NoActivate x" xPos " y" yPos " w" osdW " h" osdH)
    WinSetTransparent(200, "ahk_id " osd.Hwnd)
    g_osdGui := osd
    SetTimer(DismissOSD, -g_osdDuration)
}

DismissOSD() {
    global g_osdGui
    if g_osdGui {
        try g_osdGui.Destroy()
        g_osdGui := 0
    }
}

SyncTray() {
    global g_muted, g_icoGreen, g_icoRed, g_version, g_flashing
    ; Don't interfere while flash animation is running
    if g_flashing
        return
    SetTrayIcon()
}

; Actually apply the icon/tooltip based on current g_muted state.
SetTrayIcon() {
    global g_muted, g_icoGreen, g_icoRed, g_version, g_deafened
    suffix := g_deafened ? " [DEAFENED]" : ""
    if g_muted {
        ; Red / muted — use custom icon or fall back to a built-in "blocked" icon
        if (g_icoRed != "")
            TraySetIcon(g_icoRed)
        else
            TraySetIcon("shell32.dll", 131)
        A_IconTip := "MicMute v" g_version " — Mic: MUTED" suffix
    } else {
        ; Green / active — use custom icon or fall back to a built-in microphone icon
        if (g_icoGreen != "")
            TraySetIcon(g_icoGreen)
        else
            TraySetIcon("imageres.dll", 109)
        A_IconTip := "MicMute v" g_version " — Mic: Active" suffix
    }
    SyncLED()
}

; Sync a keyboard LED with the current mute state (F-16).
; Muted = LED ON, Active = LED OFF. Only active if g_ledIndicator is set.
SyncLED() {
    global g_muted, g_ledIndicator
    if (g_ledIndicator = "")
        return
    currentState := GetKeyState(g_ledIndicator, "T")   ; toggle state
    if (g_muted && !currentState)
        SendInput("{" g_ledIndicator "}")
    else if (!g_muted && currentState)
        SendInput("{" g_ledIndicator "}")
}

; ── ICON FLASH (P4-03) ──────────────────────────────────────────────────────
; Flash the tray icon 3 times on toggle to draw attention.
; Uses a fast timer (100ms) with 6 ticks: tick 0=opposite, 1=current,
; 2=opposite, 3=current, 4=opposite, 5=current (settled).

FlashIcon() {
    global g_flashing, g_flashCount
    if g_flashing
        SetTimer(FlashTick, 0)   ; stop existing flash before restarting
    g_flashing   := true
    g_flashCount := 0
    SetTimer(FlashTick, 100)
}

FlashTick() {
    global g_flashing, g_flashCount, g_muted, g_icoGreen, g_icoRed
    ; Even ticks (0,2,4) show the OPPOSITE icon; odd ticks (1,3,5) show correct
    showOpposite := (Mod(g_flashCount, 2) = 0)
    if showOpposite {
        ; Show the opposite of current state
        if g_muted {
            if (g_icoGreen != "")
                TraySetIcon(g_icoGreen)
            else
                TraySetIcon("imageres.dll", 109)
        } else {
            if (g_icoRed != "")
                TraySetIcon(g_icoRed)
            else
                TraySetIcon("shell32.dll", 131)
        }
    } else {
        SetTrayIcon()   ; restore correct icon
    }
    g_flashCount++
    if (g_flashCount >= 6) {
        SetTimer(FlashTick, 0)   ; stop timer
        g_flashing := false
        SetTrayIcon()            ; ensure final state is correct
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
    if (hr < 0) {
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
        if g_muteLock {
            ; Mute lock ON — fight back: re-apply our state (F-11)
            if g_lockDebounce {
                g_lockDebounce := false
                return   ; skip this cycle to avoid infinite toggle war
            }
            ComCall(14, g_pAEV, "Int", g_muted, "Ptr", 0, "Int")   ; SetMute
            g_lockDebounce := true
        } else {
            ; Normal behavior — accept external change
            g_muted := externalMuted
            SyncTray()
        }
    } else {
        g_lockDebounce := false   ; reset debounce when states agree
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
; ║  Hotkey registration & mode handling (P2-01)                             ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Register or re-register the hotkey based on current g_mode.
RegisterHotkey() {
    global g_hotkey, g_mode
    ; Unregister any existing binding first (ignore errors if none exists)
    try Hotkey(g_hotkey, "Off")
    try Hotkey(g_hotkey " Up", "Off")
    try {
        if (g_mode = "push-to-talk") {
            Hotkey(g_hotkey, (*) => PushToTalk())
        } else if (g_mode = "push-to-mute") {
            Hotkey(g_hotkey, (*) => PushToMute())
        } else if (g_mode = "hybrid") {
            Hotkey(g_hotkey, (*) => HybridMode())
        } else {
            ; Default: toggle mode
            Hotkey(g_hotkey, (*) => ToggleMute())
        }
    } catch as e {
        MsgBox("Invalid hotkey: `"" g_hotkey "`"`n`n" e.Message
            . "`n`nFalling back to tray-only mode."
            . "`nEdit the hotkey in MicMute.ini or MicMute.ahk.", "MicMute", "Icon!")
    }
}

; Push-to-talk: key down → unmute, key up → re-mute.
; Uses KeyWait to block the hotkey thread until the key is released.
PushToTalk() {
    global g_hotkey
    SetMuteState(false)   ; unmute while held
    keyName := ExtractKeyName(g_hotkey)
    KeyWait(keyName, "T30")   ; 30s safety timeout
    SetMuteState(true)    ; re-mute on release (or timeout)
}

; Push-to-mute: key down → mute, key up → re-unmute.
PushToMute() {
    global g_hotkey
    SetMuteState(true)    ; mute while held
    keyName := ExtractKeyName(g_hotkey)
    KeyWait(keyName, "T30")   ; 30s safety timeout
    SetMuteState(false)   ; re-unmute on release (or timeout)
}

; Hybrid PTT/Toggle: short press (<threshold) = toggle, long press = PTT (F-06).
; On key-down, starts a delayed timer. If key released before timer fires,
; it's a toggle. If timer fires while held, unmute (PTT) until release.
HybridMode() {
    global g_hotkey, g_hybridThreshold, g_hybridPTTActive
    g_hybridPTTActive := false
    ; Start delayed PTT activation — fires only if key is still held
    SetTimer(HybridPTTActivate, -g_hybridThreshold)
    keyName := ExtractKeyName(g_hotkey)
    KeyWait(keyName, "T30")   ; block until key release (30s safety)
    SetTimer(HybridPTTActivate, 0)   ; cancel timer if it hasn't fired
    if g_hybridPTTActive {
        ; Long press — PTT was activated by timer; re-mute on release
        SetMuteState(true)
    } else {
        ; Short press — timer never fired, perform a toggle
        ToggleMute()
    }
}

; Timer callback for hybrid mode — unmute when threshold elapses (key still held).
HybridPTTActivate() {
    global g_hybridPTTActive
    g_hybridPTTActive := true
    SetMuteState(false)
}

; Extract the key name from a hotkey string for KeyWait.
; Strips all AHK modifier/prefix symbols: # ^ ! + ~ * $ < >
; e.g. "#+a" → "a", "^!F13" → "F13", "~*#+a" → "a"
ExtractKeyName(hk) {
    return RegExReplace(hk, "^[#^!+~*$<>]+", "")
}

; Switch mode and re-register hotkey.
SetMode(newMode) {
    global g_mode
    g_mode := newMode
    RegisterHotkey()
    BuildTrayMenu()   ; rebuild to update checkmarks
    SaveConfig()
    TrayTip("Mode: " FormatModeName(newMode), "MicMute", "Iconi")
    SetTimer(() => TrayTip(), -3000)
}

FormatModeName(mode) {
    if (mode = "push-to-talk")
        return "Push-to-Talk"
    if (mode = "push-to-mute")
        return "Push-to-Mute"
    if (mode = "hybrid")
        return "Hybrid (PTT/Toggle)"
    return "Toggle"
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Deafen mode — mic + speakers (F-20)                                     ║
; ╚══════════════════════════════════════════════════════════════════════════╝

RegisterDeafenHotkey() {
    global g_deafenHotkey
    if (g_deafenHotkey = "")
        return
    try {
        Hotkey(g_deafenHotkey, (*) => ToggleDeafen())
    } catch as e {
        TrayTip("Invalid deafen hotkey: " g_deafenHotkey, "MicMute", "Icon!")
        SetTimer(() => TrayTip(), -5000)
    }
}

ToggleDeafen() {
    global g_pAEV, g_muted, g_deafened, g_speakerWasMuted
    if !g_pAEV
        return
    if !g_deafened {
        ; Enter deafen: mute mic + mute speakers
        try
            g_speakerWasMuted := SoundGetMute()   ; remember current speaker state
        catch
            g_speakerWasMuted := false
        if !g_muted
            SetMuteState(true)
        try SoundSetMute(true)   ; mute speakers
        g_deafened := true
        SetTrayIcon()        ; update tooltip suffix
        TrayTip("DEAFENED — mic + speakers muted", "MicMute", "Icon!")
    } else {
        ; Exit deafen: unmute mic + restore speakers
        g_lockDebounce := true   ; prevent mute lock from immediately re-muting
        SetMuteState(false)
        try SoundSetMute(g_speakerWasMuted)   ; restore previous speaker state
        g_deafened := false
        SetTrayIcon()        ; update tooltip suffix
        TrayTip("Undeafened — audio restored", "MicMute", "Iconi")
    }
    SetTimer(() => TrayTip(), -3000)
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Live hotkey rebinding (F-13)                                            ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Open a dialog to change the global hotkey at runtime.
; Provides both a Hotkey control (for standard combos) and a text input
; (for Win key combos like #+a that the Hotkey control doesn't support).
ShowHotkeyDialog() {
    global g_hotkey
    dlg := Gui("+AlwaysOnTop", "MicMute — Change Hotkey")
    dlg.SetFont("s10", "Segoe UI")
    dlg.Add("Text", , "Press a key combination:")
    hkCtrl := dlg.Add("Hotkey", "w250 vNewHotkey")
    dlg.Add("Text", "y+15", "Or type AHK syntax (e.g. #+a for Win+Shift+A):")
    txtCtrl := dlg.Add("Edit", "w250 vRawHotkey")
    dlg.Add("Text", "y+10 cGray", "Current: " HotkeyToReadable(g_hotkey))
    btnOK := dlg.Add("Button", "Default w80 y+15", "OK")
    btnCancel := dlg.Add("Button", "x+10 w80", "Cancel")
    btnOK.OnEvent("Click", (*) => ApplyNewHotkey(dlg, hkCtrl, txtCtrl))
    btnCancel.OnEvent("Click", (*) => dlg.Destroy())
    dlg.OnEvent("Close", (*) => dlg.Destroy())
    dlg.Show()
}

ApplyNewHotkey(dlg, hkCtrl, txtCtrl) {
    global g_hotkey
    ; Prefer raw text input (supports Win key combos), fall back to Hotkey control
    rawHK := Trim(txtCtrl.Value)
    newHK := (rawHK != "") ? rawHK : hkCtrl.Value
    if (newHK = "") {
        MsgBox("No hotkey entered. Keeping current hotkey.", "MicMute", "Icon!")
        return
    }
    ; Unregister old hotkey
    try Hotkey(g_hotkey, "Off")
    try Hotkey(g_hotkey " Up", "Off")
    g_hotkey := newHK
    RegisterHotkey()
    BuildTrayMenu()
    SaveConfig()
    dlg.Destroy()
    TrayTip("Hotkey changed to: " HotkeyToReadable(g_hotkey), "MicMute", "Iconi")
    SetTimer(() => TrayTip(), -3000)
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Audio device selector (P2-02)                                           ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Enumerate capture devices and return an array of {name, id} objects.
EnumCaptureDevices() {
    devices := []
    CLSID_MMEnum := Buffer(16)
    IID_MMEnum   := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", "{BCDE0395-E52F-467C-8E3D-C4579291692E}", "Ptr", CLSID_MMEnum)
    DllCall("ole32\CLSIDFromString", "WStr", "{A95664D2-9614-4F35-A746-DE8DB63617E6}", "Ptr", IID_MMEnum)

    hr := DllCall("ole32\CoCreateInstance",
        "Ptr",  CLSID_MMEnum,
        "Ptr",  0,
        "UInt", 1,
        "Ptr",  IID_MMEnum,
        "Ptr*", &pEnum := 0,
        "Int")
    if (hr < 0 || !pEnum)
        return devices

    ; EnumAudioEndpoints(eCapture=1, DEVICE_STATE_ACTIVE=1)
    hr := ComCall(3, pEnum, "UInt", 1, "UInt", 1, "Ptr*", &pCollection := 0, "Int")
    ObjRelease(pEnum)
    if (hr < 0 || !pCollection)
        return devices

    ; GetCount
    hr := ComCall(3, pCollection, "UInt*", &count := 0, "Int")
    if (hr < 0) {
        ObjRelease(pCollection)
        return devices
    }

    ; PKEY_Device_FriendlyName: {A45C254E-DF1C-4EFD-8020-67D146A850E0}, pid 14
    PKEY := Buffer(20, 0)
    DllCall("ole32\CLSIDFromString", "WStr", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "Ptr", PKEY)
    NumPut("UInt", 14, PKEY, 16)

    loop count {
        idx := A_Index - 1
        ; Item(idx)
        hr := ComCall(4, pCollection, "UInt", idx, "Ptr*", &pDev := 0, "Int")
        if (hr < 0 || !pDev)
            continue

        ; GetId — returns an LPWSTR that must be CoTaskMemFree'd
        hr := ComCall(5, pDev, "Ptr*", &pIdStr := 0, "Int")
        devId := ""
        if (hr = 0 && pIdStr) {
            devId := StrGet(pIdStr, "UTF-16")
            DllCall("ole32\CoTaskMemFree", "Ptr", pIdStr)
        }

        ; OpenPropertyStore(STGM_READ=0)
        friendlyName := ""
        hr := ComCall(4, pDev, "UInt", 0, "Ptr*", &pStore := 0, "Int")
        if (hr = 0 && pStore) {
            ; GetValue(PKEY, &PROPVARIANT)
            pv := Buffer(24, 0)
            hr := ComCall(5, pStore, "Ptr", PKEY, "Ptr", pv, "Int")
            if (hr = 0) {
                vt := NumGet(pv, 0, "UShort")
                if (vt = 31) {   ; VT_LPWSTR
                    pStr := NumGet(pv, 8, "Ptr")
                    if pStr
                        friendlyName := StrGet(pStr, "UTF-16")
                }
                ; PropVariantClear
                DllCall("ole32\PropVariantClear", "Ptr", pv)
            }
            ObjRelease(pStore)
        }

        ObjRelease(pDev)

        if (devId != "" && friendlyName != "")
            devices.Push({name: friendlyName, id: devId})
    }

    ObjRelease(pCollection)
    return devices
}

; Switch to a specific device by ID. Empty string = system default.
SelectDevice(deviceId, *) {
    global g_pAEV, g_muted, g_deviceId
    g_deviceId := deviceId
    ; Release current endpoint
    if g_pAEV {
        ObjRelease(g_pAEV)
        g_pAEV := 0
    }
    g_pAEV := InitMicEndpoint()
    if g_pAEV {
        hr := ComCall(15, g_pAEV, "Int*", &_m := 0, "Int")
        g_muted := (hr = 0 && _m != 0)
    } else {
        g_muted := false
    }
    SyncTray()
    BuildTrayMenu()
    SaveConfig()
    if (deviceId = "")
        TrayTip("Using system default microphone.", "MicMute", "Iconi")
    else
        TrayTip("Switched microphone.", "MicMute", "Iconi")
    SetTimer(() => TrayTip(), -3000)
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Tray menu                                                               ║
; ╚══════════════════════════════════════════════════════════════════════════╝

BuildTrayMenu() {
    global g_hotkey, g_version, g_soundFeedback, g_mode, g_deviceId
    hotkeyLabel := "Hotkey: " HotkeyToReadable(g_hotkey)

    A_TrayMenu.Delete()
    A_TrayMenu.Add("Toggle Mute",       (*) => ToggleMute())
    A_TrayMenu.Add(hotkeyLabel,          (*) => 0)
    A_TrayMenu.Disable(hotkeyLabel)
    A_TrayMenu.Add("Change Hotkey…",     (*) => ShowHotkeyDialog())
    A_TrayMenu.Add()

    ; ── Mode submenu (P2-01) ──
    modeMenu := Menu()
    modeMenu.Add("Toggle",              (*) => SetMode("toggle"))
    modeMenu.Add("Push-to-Talk",        (*) => SetMode("push-to-talk"))
    modeMenu.Add("Push-to-Mute",        (*) => SetMode("push-to-mute"))
    modeMenu.Add("Hybrid (PTT/Toggle)", (*) => SetMode("hybrid"))
    if (g_mode = "toggle")
        modeMenu.Check("Toggle")
    else if (g_mode = "push-to-talk")
        modeMenu.Check("Push-to-Talk")
    else if (g_mode = "push-to-mute")
        modeMenu.Check("Push-to-Mute")
    else if (g_mode = "hybrid")
        modeMenu.Check("Hybrid (PTT/Toggle)")
    A_TrayMenu.Add("Mode", modeMenu)

    ; ── Device submenu (P2-02) ──
    devMenu := Menu()
    devMenu.Add("System Default", SelectDevice.Bind(""))
    if (g_deviceId = "")
        devMenu.Check("System Default")
    devMenu.Add()
    devList := EnumCaptureDevices()
    for dev in devList {
        ; Use Bind to capture device ID by value in the closure
        devMenu.Add(dev.name, SelectDevice.Bind(dev.id))
        if (g_deviceId = dev.id)
            devMenu.Check(dev.name)
    }
    A_TrayMenu.Add("Microphone", devMenu)

    A_TrayMenu.Add()
    A_TrayMenu.Add("Sound Feedback",     (*) => ToggleSoundFeedback())
    if g_soundFeedback
        A_TrayMenu.Check("Sound Feedback")
    A_TrayMenu.Add("Mute Lock",          (*) => ToggleMuteLock())
    if g_muteLock
        A_TrayMenu.Check("Mute Lock")
    A_TrayMenu.Add("On-Screen Display",  (*) => ToggleOSD())
    if g_osdEnabled
        A_TrayMenu.Check("On-Screen Display")
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

ToggleMuteLock() {
    global g_muteLock, g_lockDebounce
    g_muteLock := !g_muteLock
    g_lockDebounce := false
    if g_muteLock
        A_TrayMenu.Check("Mute Lock")
    else
        A_TrayMenu.Uncheck("Mute Lock")
    SaveConfig()
    TrayTip("Mute Lock: " (g_muteLock ? "ON" : "OFF"), "MicMute", "Iconi")
    SetTimer(() => TrayTip(), -3000)
}

ToggleOSD() {
    global g_osdEnabled
    g_osdEnabled := !g_osdEnabled
    if g_osdEnabled
        A_TrayMenu.Check("On-Screen Display")
    else
        A_TrayMenu.Uncheck("On-Screen Display")
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
    global g_hotkey, g_soundFeedback, g_muteOnLock, g_mode, g_deviceId
    ini := A_ScriptDir "\MicMute.ini"
    if !FileExist(ini)
        return
    g_hotkey        := IniRead(ini, "General", "Hotkey", g_hotkey)
    g_soundFeedback := (Trim(IniRead(ini, "General", "SoundFeedback", "1")) = "1")
    g_muteOnLock    := (Trim(IniRead(ini, "General", "MuteOnLock", "0")) = "1")
    g_mode          := Trim(IniRead(ini, "General", "Mode", "toggle"))
    g_deviceId      := Trim(IniRead(ini, "General", "DeviceId", ""))
    g_unmuteOnExit  := (Trim(IniRead(ini, "General", "UnmuteOnExit", "1")) = "1")
    g_iconMuted     := Trim(IniRead(ini, "General", "IconMuted", ""))
    g_iconActive    := Trim(IniRead(ini, "General", "IconActive", ""))
    g_ledIndicator  := StrLower(Trim(IniRead(ini, "General", "LEDIndicator", "")))
    g_muteLock      := (Trim(IniRead(ini, "General", "MuteLock", "0")) = "1")
    g_muteSound     := Trim(IniRead(ini, "General", "MuteSound", ""))
    g_unmuteSound   := Trim(IniRead(ini, "General", "UnmuteSound", ""))
    g_hybridThreshold := Integer(Trim(IniRead(ini, "General", "HybridThreshold", "300")))
    if (g_hybridThreshold < 50)
        g_hybridThreshold := 50   ; floor to prevent accidental zero
    g_osdEnabled    := (Trim(IniRead(ini, "General", "OSD_Enabled", "0")) = "1")
    g_osdPosition   := StrLower(Trim(IniRead(ini, "General", "OSD_Position", "bottom")))
    g_osdDuration   := Integer(Trim(IniRead(ini, "General", "OSD_Duration", "1500")))
    if (g_osdPosition != "top" && g_osdPosition != "bottom" && g_osdPosition != "center")
        g_osdPosition := "bottom"
    if (g_osdDuration < 500)
        g_osdDuration := 500
    g_deafenHotkey  := Trim(IniRead(ini, "General", "DeafenHotkey", ""))
    ; Validate mode
    if (g_mode != "toggle" && g_mode != "push-to-talk" && g_mode != "push-to-mute" && g_mode != "hybrid")
        g_mode := "toggle"
}

; Save current settings to MicMute.ini.
SaveConfig() {
    global g_hotkey, g_soundFeedback, g_muteOnLock, g_mode, g_deviceId
    ini := A_ScriptDir "\MicMute.ini"
    IniWrite(g_hotkey, ini, "General", "Hotkey")
    IniWrite(g_soundFeedback ? "1" : "0", ini, "General", "SoundFeedback")
    IniWrite(g_muteOnLock ? "1" : "0", ini, "General", "MuteOnLock")
    IniWrite(g_mode, ini, "General", "Mode")
    IniWrite(g_deviceId, ini, "General", "DeviceId")
    IniWrite(g_unmuteOnExit ? "1" : "0", ini, "General", "UnmuteOnExit")
    IniWrite(g_iconMuted, ini, "General", "IconMuted")
    IniWrite(g_iconActive, ini, "General", "IconActive")
    IniWrite(g_ledIndicator, ini, "General", "LEDIndicator")
    IniWrite(g_hybridThreshold, ini, "General", "HybridThreshold")
    IniWrite(g_osdEnabled ? "1" : "0", ini, "General", "OSD_Enabled")
    IniWrite(g_osdPosition, ini, "General", "OSD_Position")
    IniWrite(g_osdDuration, ini, "General", "OSD_Duration")
    IniWrite(g_muteLock ? "1" : "0", ini, "General", "MuteLock")
    IniWrite(g_muteSound, ini, "General", "MuteSound")
    IniWrite(g_unmuteSound, ini, "General", "UnmuteSound")
    IniWrite(g_deafenHotkey, ini, "General", "DeafenHotkey")
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

; Initialise IAudioEndpointVolume for a capture (mic) device.
; If g_deviceId is set, uses that specific device. Otherwise uses the system default.
; Returns the COM pointer on success, or 0 on failure (shows a message box
; but does NOT exit — the script stays alive so the user can reinitialise).
; If silent=true, suppresses MsgBox dialogs (used by periodic auto-detect).
InitMicEndpoint(silent := false) {
    global g_deviceId
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
    if (hr < 0 || !pEnum) {
        if !silent
            MsgBox("CoCreateInstance failed: 0x" Format("{:08X}", hr & 0xFFFFFFFF) "`n`nUse Tray → Reinitialise Mic after connecting a microphone.", "MicMute", "Icon!")
        return 0
    }

    pDev := 0
    if (g_deviceId != "") {
        ; Use specific device by ID: IMMDeviceEnumerator::GetDevice(pwstrId)
        hr := ComCall(5, pEnum, "WStr", g_deviceId, "Ptr*", &pDev := 0, "Int")
        if (hr < 0 || !pDev) {
            ; Specific device not found — fall back to system default
            if !silent
                TrayTip("Saved device not found — using system default.", "MicMute", "Icon!")
            hr := ComCall(4, pEnum, "UInt", 1, "UInt", 0, "Ptr*", &pDev := 0, "Int")
        }
    } else {
        ; GetDefaultAudioEndpoint(eCapture=1, eConsole=0)
        hr := ComCall(4, pEnum, "UInt", 1, "UInt", 0, "Ptr*", &pDev := 0, "Int")
    }
    ObjRelease(pEnum)
    if (hr < 0 || !pDev) {
        if !silent
            MsgBox("GetDefaultAudioEndpoint failed: 0x" Format("{:08X}", hr & 0xFFFFFFFF) "`n`nMake sure a microphone is connected, then use Tray → Reinitialise Mic.", "MicMute", "Icon!")
        return 0
    }

    ; CLSCTX_INPROC_SERVER = 1 (standard context for audio endpoint activation)
    hr := ComCall(3, pDev, "Ptr", IID_AEV, "UInt", 1, "Ptr", 0, "Ptr*", &pAEV := 0, "Int")
    ObjRelease(pDev)
    if (hr < 0 || !pAEV) {
        if !silent
            MsgBox("Activate IAudioEndpointVolume failed: 0x" Format("{:08X}", hr & 0xFFFFFFFF) "`n`nUse Tray → Reinitialise Mic to retry.", "MicMute", "Icon!")
        return 0
    }

    return pAEV
}

; Release COM handle and clean up on exit.
Cleanup(*) {
    global g_pAEV, g_muteOnLock, g_unmuteOnExit, g_muted, g_ledIndicator
    global g_deafened, g_speakerWasMuted
    ; Restore speaker state if deafened (F-20)
    if g_deafened
        try SoundSetMute(g_speakerWasMuted)
    ; Restore LED to its pre-MicMute state (F-16)
    if (g_ledIndicator != "") {
        currentLED := GetKeyState(g_ledIndicator, "T")
        if (currentLED != g_ledInitialState)
            SendInput("{" g_ledIndicator "}")
    }
    ; Unmute mic on exit to prevent "dead mic" after quitting (F-10)
    if g_unmuteOnExit && g_pAEV && g_muted
        try ComCall(14, g_pAEV, "Int", false, "Ptr", 0, "Int")   ; SetMute(false)
    if g_muteOnLock
        DllCall("Wtsapi32\WTSUnRegisterSessionNotification", "Ptr", A_ScriptHwnd)
    if g_pAEV
        ObjRelease(g_pAEV)
}
