; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  MicMute.ahk  —  Global microphone mute toggle                         ║
; ║  Version: 1.8.2                                                         ║
; ║  Requires: AutoHotKey v2  (https://www.autohotkey.com/)                ║
; ║                                                                          ║
; ║  • Left-click  tray icon  → toggle mute                                 ║
; ║  • Right-click tray icon  → menu (toggle / reinitialise / sound / exit) ║
; ║  • Hotkey below           → toggle mute from anywhere                   ║
; ║  • Green icon = mic active  |  Red icon = mic muted                     ║
; ║                                                                          ║
; ║  Modes:                                                                  ║
; ║    Toggle (default)    — press hotkey to flip mute on/off               ║
; ║    Push-to-Talk        — hold hotkey to unmute, release to re-mute      ║
; ║                                                                          ║
; ║  Features:                                                               ║
; ║    Custom sounds, OSD overlay, mute lock, deafen mode,                 ║
; ║    live hotkey rebinding, custom icon colors, unmute on exit            ║
; ║                                                                          ║
; ║  Files (place in same folder, or use compiled .exe with icons embedded): ║
; ║    mic_on.ico   — mic active (green) — embedded in .exe as resource 10 ║
; ║    mic_off.ico  — mic muted  (red)   — embedded in .exe as resource 11 ║
; ║    MicMute.ini  — optional config file (auto-created via tray menu)     ║
; ║                                                                          ║
; ║  Note: MicMute auto-detects when you change or unplug your mic.        ║
; ║  You can also use Tray → "Reinitialise Mic" to manually reconnect.     ║
; ╚══════════════════════════════════════════════════════════════════════════╝

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ── Embed icons as PE resources so compiled .exe works standalone ────────────
;@Ahk2Exe-AddResource mic_on.ico, 10
;@Ahk2Exe-AddResource mic_off.ico, 11

; ── CONFIGURATION ────────────────────────────────────────────────────────────
;  Version string displayed in tray menu and tooltip.
global g_version := "1.8.2"

;  Defaults — overridden by MicMute.ini if present.
;  Change g_hotkey to whatever combo you prefer.
;  Modifier symbols:  #=Win  ^=Ctrl  !=Alt  +=Shift
;  Examples:
;    "^!m"   →  Ctrl + Alt + M
;    "#+a"   →  Win  + Shift + A
;    "F13"   →  F13 key (if your keyboard has it)
global g_hotkey        := "#+a"
global g_soundFeedback := true
global g_mode          := "toggle"     ; "toggle", "push-to-talk"
global g_deviceId      := ""           ; empty = system default
global g_iconMuted     := ""           ; custom .ico path for muted state (F-17)
global g_iconActive    := ""           ; custom .ico path for active state (F-17)
global g_ledIndicator  := ""           ; DEPRECATED: LED sync removed (was F-16, interfered with actual key function)
global g_muteSound     := ""           ; custom .wav for mute feedback (F-04)
global g_unmuteSound   := ""           ; custom .wav for unmute feedback (F-04)
global g_muteLock      := false        ; prevent external apps from changing mute state (F-11)
global g_lockDebounce  := false        ; skip one sync cycle after enforcement (F-11)
global g_osdEnabled    := false        ; show floating overlay on toggle (F-02)
global g_osdDuration   := 1500         ; OSD display time in ms (F-02)
global g_osdGui        := 0            ; GUI object reference for current OSD (F-02)
global g_deafenHotkey  := ""           ; separate hotkey for deafen mode (F-20)
global g_deafened      := false        ; true when deafened (mic + speakers muted) (F-20)
global g_ledInitialState := false      ; DEPRECATED: kept for INI compat
global g_speakerWasMuted := false      ; remember speaker state before deafen (F-20)
global g_startMuted     := "no"        ; startup mute: "no", "yes", "unmuted", "last" (F-14)
global g_middleClickToggle := true     ; middle-click tray icon to toggle between Toggle/PTT modes

; Load overrides from INI (if it exists)
LoadConfig()

; LED sync removed (F-16) — was unreliable and interfered with actual key function

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
    ; Apply startup mute preference (F-14)
    if (g_startMuted = "yes" && !g_muted) {
        ComCall(14, g_pAEV, "Int", true, "Ptr", 0, "Int")
        g_muted := true
    } else if (g_startMuted = "unmuted" && g_muted) {
        ComCall(14, g_pAEV, "Int", false, "Ptr", 0, "Int")
        g_muted := false
    } else if (g_startMuted = "last") {
        ini := A_ScriptDir "\MicMute.ini"
        lastState := (Trim(IniRead(ini, "General", "LastMuteState", "0")) = "1")
        if (lastState != g_muted) {
            ComCall(14, g_pAEV, "Int", lastState, "Ptr", 0, "Int")
            g_muted := lastState
        }
    }
}

; ── TRAY ICONS ───────────────────────────────────────────────────────────────
; Priority: custom INI path > .ico file on disk > embedded PE resource > Windows built-in
; Compiled .exe embeds mic_on.ico (resource 10) and mic_off.ico (resource 11).
global g_icoGreen := (g_iconActive != "" && FileExist(g_iconActive)) ? g_iconActive
    : FileExist(A_ScriptDir "\mic_on.ico")  ? A_ScriptDir "\mic_on.ico"  : ""
global g_icoRed   := (g_iconMuted != "" && FileExist(g_iconMuted)) ? g_iconMuted
    : FileExist(A_ScriptDir "\mic_off.ico") ? A_ScriptDir "\mic_off.ico" : ""

; ── FLASH ANIMATION STATE ──────────────────────────────────────────────────
global g_flashEnabled := false  ; set to true to enable icon flash on toggle
global g_flashing   := false   ; true while flash animation is running
global g_flashCount := 0       ; counts 0..1 (1 on/off cycle)

; ── TRAY MENU ────────────────────────────────────────────────────────────────
BuildTrayMenu()

; ── HOTKEY ───────────────────────────────────────────────────────────────────
; Validate the hotkey string — fall back to tray-only mode on error (P0-03).
RegisterHotkey()
RegisterDeafenHotkey()

; ── INITIALISE ICON ──────────────────────────────────────────────────────────
; Defer icon update so the shell has time to register the tray icon.
; Using SetTimer instead of Sleep to avoid blocking startup.
SetTimer(SyncTray, -150)

; Show a brief tooltip if no mic was found so the user knows what's up
if !g_pAEV {
    ToolTip("No microphone detected.`nPlug one in — MicMute will auto-detect it.")
    SetTimer(() => ToolTip(), -5000)
}

; ── PERIODIC SYNC ────────────────────────────────────────────────────────────
; Every 5 seconds, verify the audio endpoint is still valid and sync
; the tray icon if another app (or Windows Settings) changed the mute state.
; Handles both device hotplug (P1-01) and external mute changes (P1-02).
SetTimer(SyncMuteState, 5000)

; ── TRAY NOTIFICATION HANDLER ────────────────────────────────────────────
; Handle middle-click (mode toggle) and right-click (device menu) on tray icon.
OnMessage(0x404, OnTrayNotify)

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Core functions                                                          ║
; ╚══════════════════════════════════════════════════════════════════════════╝

ToggleMute() {
    global g_muted, g_pAEV, g_soundFeedback
    if !g_pAEV {
        ToolTip("No microphone available.`nTry Tray → Reinitialise Mic.")
        SetTimer(() => ToolTip(), -5000)
        return
    }
    newState := !g_muted
    hr := ComCall(14, g_pAEV, "Int", newState, "Ptr", 0, "Int")   ; SetMute
    if (hr < 0) {
        ToolTip("SetMute failed (0x" Format("{:08X}", hr & 0xFFFFFFFF) ").`nDevice may have changed — try Reinitialise Mic.")
        SetTimer(() => ToolTip(), -5000)
        return
    }
    g_muted := newState
    SaveLastMuteState()
    SyncTray()
    if g_flashEnabled
        FlashIcon()
    ShowOSD()
    PlayFeedback()
}

; Set mute to a specific state (used by PTT and deafen).
; quiet=true skips flash/OSD/sound for instant transitions (e.g. PTT hold/release).
SetMuteState(muted, quiet := false) {
    global g_muted, g_pAEV
    if !g_pAEV
        return
    if (g_muted = muted)
        return
    hr := ComCall(14, g_pAEV, "Int", muted, "Ptr", 0, "Int")   ; SetMute
    if (hr < 0)
        return
    g_muted := muted
    SaveLastMuteState()
    SyncTray()
    if !quiet {
        if g_flashEnabled
            FlashIcon()
        ShowOSD()
        PlayFeedback()
    }
}

; Persist current mute state to INI for "last" mode (F-14).
; Only writes when StartMuted=last to avoid unnecessary disk I/O in PTT mode.
SaveLastMuteState() {
    global g_startMuted, g_muted
    if (g_startMuted != "last")
        return
    ini := A_ScriptDir "\MicMute.ini"
    IniWrite(g_muted ? "1" : "0", ini, "General", "LastMuteState")
}

; Play audible feedback on toggle (F-04).
; Uses custom WAV files if configured, otherwise Android-style two-tone beep.
PlayFeedback() {
    global g_muted, g_soundFeedback, g_muteSound, g_unmuteSound
    if !g_soundFeedback
        return
    soundFile := g_muted ? g_muteSound : g_unmuteSound
    if (soundFile != "" && FileExist(soundFile)) {
        try
            SoundPlay(soundFile, true)   ; synchronous — throws on bad file
        catch
            PlayToneSequence(g_muted)
    } else {
        PlayToneSequence(g_muted)
    }
}

; Single-tone feedback: low for mute, high for unmute.
PlayToneSequence(muted) {
    SoundBeep(muted ? 587 : 880, 80)
}

; Show an on-screen display overlay indicating mute state (F-02).
; Borderless, always-on-top, click-through GUI that auto-dismisses.
ShowOSD() {
    global g_muted, g_osdEnabled, g_osdDuration, g_osdGui
    if !g_osdEnabled
        return
    ; Cancel any pending dismiss timer before touching the GUI
    SetTimer(DismissOSD, 0)
    ; Destroy previous OSD if still showing
    if g_osdGui {
        try g_osdGui.Destroy()
        g_osdGui := 0
    }
    ; Modern dark toast bubble — click-through, always on top
    osd := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    osd.BackColor := "1E1E1E"
    osd.MarginX := 0
    osd.MarginY := 0
    accentColor := g_muted ? "E04040" : "2ECC71"
    label := g_muted ? "Mic Muted" : "Mic Active"
    ; Colored status dot
    osd.SetFont("s10 c" accentColor, "Segoe UI")
    osd.Add("Text", "x12 y6 w14 h20 +0x200", Chr(0x25CF))   ; ● dot
    ; Label text
    osd.SetFont("s9 cE0E0E0", "Segoe UI Semibold")
    osd.Add("Text", "x28 y6 h20 +0x200", label)
    ; Show first to measure, then reposition above the clock
    osd.Show("NoActivate AutoSize")
    osd.GetPos(, , &osdW, &osdH)
    ; Pad width for breathing room
    osdW += 12
    osdH := 32
    ; Win11 rounded corners via DWM (silently ignored on older Windows)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", osd.Hwnd,
        "Int", 33, "Int*", 2, "Int", 4)   ; DWMWCP_ROUND
    ; Find the notification area (clock) position via Shell_TrayWnd
    xPos := A_ScreenWidth - osdW - 12
    yPos := A_ScreenHeight - osdH - 60   ; fallback above taskbar
    try {
        trayHwnd := WinExist("ahk_class Shell_TrayWnd")
        if trayHwnd {
            WinGetPos(&tbX, &tbY, &tbW, &tbH, "ahk_id " trayHwnd)
            xPos := tbX + tbW - osdW - 12
            yPos := tbY - osdH - 8
        }
    }
    osd.Show("NoActivate x" xPos " y" yPos " w" osdW " h" osdH)
    WinSetTransparent(235, "ahk_id " osd.Hwnd)
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
    global g_muted, g_icoGreen, g_icoRed, g_version, g_deafened, g_mode
    suffix := g_deafened ? " [DEAFENED]" : ""
    modeName := (g_mode = "push-to-talk") ? " [PTT]" : ""
    if g_muted {
        ; Red / muted — custom file > embedded resource > Windows built-in
        if (g_icoRed != "")
            TraySetIcon(g_icoRed)
        else if A_IsCompiled
            TraySetIcon(A_ScriptFullPath, -11, true)
        else
            TraySetIcon("shell32.dll", 131)
        A_IconTip := "MicMute v" g_version " — Mic: MUTED" modeName suffix
    } else {
        ; Green / active — custom file > embedded resource > Windows built-in
        if (g_icoGreen != "")
            TraySetIcon(g_icoGreen)
        else if A_IsCompiled
            TraySetIcon(A_ScriptFullPath, -10, true)
        else
            TraySetIcon("imageres.dll", 109)
        A_IconTip := "MicMute v" g_version " — Mic: Active" modeName suffix
    }
}


; ── ICON FLASH (P4-03) ──────────────────────────────────────────────────────
; Flash the tray icon 3 times on toggle to draw attention.
; Uses a fast timer (100ms) with 2 ticks: tick 0=opposite, 1=current (settled).

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
            else if A_IsCompiled
                TraySetIcon(A_ScriptFullPath, -10, true)
            else
                TraySetIcon("imageres.dll", 109)
        } else {
            if (g_icoRed != "")
                TraySetIcon(g_icoRed)
            else if A_IsCompiled
                TraySetIcon(A_ScriptFullPath, -11, true)
            else
                TraySetIcon("shell32.dll", 131)
        }
    } else {
        SetTrayIcon()   ; restore correct icon
    }
    g_flashCount++
    if (g_flashCount >= 2) {
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
        g_pAEV := InitMicEndpoint(true)   ; silent mode — no ToolTip
        if !g_pAEV
            return
        ; New device found — read its mute state
        ToolTip("Microphone detected — auto-connected.")
        SetTimer(() => ToolTip(), -3000)
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
        ToolTip("Microphone disconnected.`nWill auto-reconnect when available.")
        SetTimer(() => ToolTip(), -5000)
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
    ToolTip("Microphone reinitialised.")
    SetTimer(() => ToolTip(), -3000)
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Hotkey registration & mode handling (P2-01)                             ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Register or re-register the hotkey based on current g_mode.
; Tracks previous hotkey so mode/key changes properly clean up the old binding.
RegisterHotkey() {
    global g_hotkey, g_mode
    static prevHotkey := ""
    ; If the physical key changed, disable the old binding first
    if (prevHotkey != "" && prevHotkey != g_hotkey) {
        try Hotkey(prevHotkey, "Off")
        try Hotkey(prevHotkey " Up", "Off")
    }
    ; Register with new callback — Hotkey() replaces the callback even if key
    ; was already registered.  No need to Off/On cycle the same key, which can
    ; confuse AHK's internal hotkey state on mode switches (PTT→Toggle bug).
    try {
        if (g_mode = "push-to-talk") {
            Hotkey(g_hotkey, (*) => PushToTalk(), "On")
        } else {
            Hotkey(g_hotkey, (*) => ToggleMute(), "On")
        }
        prevHotkey := g_hotkey
    } catch as e {
        prevHotkey := ""
        ToolTip("Invalid hotkey: " g_hotkey "`nFalling back to tray-only mode.")
        SetTimer(() => ToolTip(), -5000)
    }
}

; Push-to-talk: key down → unmute, key up → re-mute.
; Uses KeyWait to block the hotkey thread until the key is released.
PushToTalk() {
    global g_hotkey, g_mode
    SetMuteState(false, true)   ; unmute while held (quiet — no flash/OSD)
    Sleep(10)                   ; yield so tray icon repaints before KeyWait blocks
    keyName := ExtractKeyName(g_hotkey)
    KeyWait(keyName, "T30")   ; 30s safety timeout
    ; Guard: if mode was switched while we were blocked on KeyWait, don't re-mute
    if (g_mode != "push-to-talk")
        return
    SetMuteState(true, true)    ; re-mute on release (quiet — no flash/OSD)
}


; Extract the key name from a hotkey string for KeyWait.
; Strips all AHK modifier/prefix symbols: # ^ ! + ~ * $ < >
; e.g. "#+a" → "a", "^!F13" → "F13", "~*#+a" → "a"
ExtractKeyName(hk) {
    return RegExReplace(hk, "^[#^!+~*$<>]+", "")
}

; Switch mode and re-register hotkey.
SetMode(newMode) {
    global g_mode, g_soundFeedback
    g_mode := newMode
    ; PTT starts muted — ensure mic is off when entering PTT mode
    if (newMode = "push-to-talk")
        SetMuteState(true, true)
    RegisterHotkey()
    BuildTrayMenu()   ; rebuild to update checkmarks
    SetTrayIcon()     ; update tooltip with mode name
    SaveConfig()
    ; Quick two-tone chirp for mode switch — distinct from single mute/unmute beeps
    if g_soundFeedback
        PlayModeChirp(newMode)
    ToolTip("Mode: " FormatModeName(newMode))
    SetTimer(() => ToolTip(), -3000)
}

; Single-tone mode switch feedback — distinct from mute/unmute beeps.
; 1175Hz = switched to Toggle, 1568Hz = switched to PTT.
PlayModeChirp(mode) {
    SoundBeep(mode = "push-to-talk" ? 1568 : 1175, 50)
}

FormatModeName(mode) {
    if (mode = "push-to-talk")
        return "Push-to-Talk"
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
        ToolTip("Invalid deafen hotkey: " g_deafenHotkey)
        SetTimer(() => ToolTip(), -5000)
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
        ToolTip("DEAFENED — mic + speakers muted")
    } else {
        ; Exit deafen: unmute mic + restore speakers
        g_lockDebounce := true   ; prevent mute lock from immediately re-muting
        SetMuteState(false)
        try SoundSetMute(g_speakerWasMuted)   ; restore previous speaker state
        g_deafened := false
        SetTrayIcon()        ; update tooltip suffix
        ToolTip("Undeafened — audio restored")
    }
    SetTimer(() => ToolTip(), -3000)
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
        ToolTip("No hotkey entered. Keeping current hotkey.")
        SetTimer(() => ToolTip(), -5000)
        return
    }
    g_hotkey := newHK
    RegisterHotkey()   ; handles unregistering the old key via prevHotkey tracking
    BuildTrayMenu()
    SaveConfig()
    dlg.Destroy()
    ToolTip("Hotkey changed to: " HotkeyToReadable(g_hotkey))
    SetTimer(() => ToolTip(), -3000)
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Help Window                                                            ║
; ╚══════════════════════════════════════════════════════════════════════════╝

global g_helpGui := 0

ShowHelpWindow() {
    global g_helpGui
    if g_helpGui {
        try {
            g_helpGui.Show()
            return
        }
        g_helpGui := 0
    }
    hlp := Gui("+AlwaysOnTop +Resize +MinSize400x300", "MicMute v" g_version " — Help")
    hlp.BackColor := "FFFFFF"
    hlp.SetFont("s9", "Segoe UI")

    helpText := "
    (
MICMUTE — Global Microphone Mute Toggle

MicMute lets you mute and unmute your microphone system-wide using a hotkey or the tray icon. It works at the Windows audio level, so it affects all apps at once — Zoom, Discord, Teams, etc.

Green tray icon = mic is active (unmuted)
Red tray icon = mic is muted

─── BASIC USAGE ─────────────────────────────────

• Left-click the tray icon to toggle mute.
• Press your hotkey (default: Win+Shift+A) to toggle from anywhere.
• Right-click the tray icon for the full menu (change mode, pick a mic, open settings, etc.).
• Change your hotkey anytime via Tray → "Hotkey: ..." in the menu.

─── MODES ───────────────────────────────────────

Toggle (default): Press the hotkey once to mute, press again to unmute.

Push-to-Talk: Hold the hotkey to unmute. Releasing it mutes you again. Useful for noisy environments where you only want to be heard while actively speaking.

Switch modes via the tray menu (Mode → Toggle / Push-to-Talk), or enable "Middle-click tray icon to toggle" in Settings to quickly swap between them.

─── DEAFEN MODE ─────────────────────────────────

Deafen mutes both your microphone AND your speakers at the same time. Useful for stepping away or silencing everything quickly. Assign a hotkey in Settings under the Hotkeys section. Press again to undeafen (restores both to their previous state).

─── SETTINGS ────────────────────────────────────

Sound feedback: Plays a short tone when you mute or unmute. Mute plays a lower pitch (B4), unmute plays a higher pitch (A5). You can replace these with custom .wav files under Custom Files.

On-screen display (OSD): Shows a small dark floating bubble above the taskbar when you toggle mute. The Duration setting controls how long it stays visible (minimum 500 ms).

Mute Lock: Prevents other applications from silently unmuting or muting your mic. MicMute checks every few seconds and re-applies its own mute state if something changed it. Useful if apps like Zoom or Teams override your mute.

Middle-click toggle: When enabled, middle-clicking the tray icon swaps between Toggle and Push-to-Talk mode. A quick way to switch without opening the menu.

Run at startup: Creates a Windows startup shortcut so MicMute launches automatically when you log in.

On startup: Controls what happens to your mic when MicMute starts:
  • Don't change — leaves your mic however it was.
  • Always muted — forces mic muted on launch.
  • Always unmuted — forces mic unmuted on launch.
  • Remember last — restores the mute state from your last session.

─── HOTKEYS ─────────────────────────────────────

Your main mute/unmute hotkey is set via the tray menu (right-click → "Hotkey: ..."). The Settings window has a separate field for the Deafen hotkey.

Both support Windows key combinations (like Win+Shift+D). Use the "WinKey..." button to enter these using AHK syntax:
  # = Win,  ^ = Ctrl,  ! = Alt,  + = Shift
  Example: #+d means Win+Shift+D

─── CUSTOM FILES ────────────────────────────────

Muted icon / Active icon: Replace the default red/green tray icons with your own .ico files. Useful for colorblind users or personal preference.

Mute sound / Unmute sound: Replace the default beep tones with your own .wav files for audio feedback.

Use Browse to pick a file, or Clear to revert to the defaults.

─── MIC SOURCE ──────────────────────────────────

Right-click the tray icon → "Mic Source" to choose which microphone MicMute controls. By default it uses your Windows system default. If you switch mics or plug in a new one, MicMute auto-detects the change and reconnects.

You can also use Tray → "Reinit Mic" to manually force a reconnect.
    )"

    hlp.Add("Edit", "x10 y10 w440 h400 ReadOnly -E0x200 Multi +VScroll", helpText)
    hlp.OnEvent("Close", (*) => (g_helpGui.Destroy(), g_helpGui := 0))
    hlp.OnEvent("Size", HelpResize)
    g_helpGui := hlp
    hlp.Show("w460 h420")
}

HelpResize(hlp, minMax, w, h) {
    if minMax = -1  ; minimized
        return
    try hlp["Edit1"].Move(10, 10, w - 20, h - 20)
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Settings GUI (F-05)                                                    ║
; ╚══════════════════════════════════════════════════════════════════════════╝

global g_settingsGui := 0

ShowSettingsGUI() {
    global
    ; Singleton — bring existing window to front if open
    if g_settingsGui {
        try {
            g_settingsGui.Show()
            return
        }
        g_settingsGui := 0
    }
    dlg := Gui("+AlwaysOnTop", "MicMute v" g_version " — Settings")
    dlg.BackColor := "FFFFFF"
    dlg.SetFont("s9", "Segoe UI")

    ; ── Behavior ──
    dlg.SetFont("s9 Bold", "Segoe UI")
    dlg.Add("Text", "x16 y14 w410 c444444", "Behavior")
    dlg.SetFont("s9 norm", "Segoe UI")
    dlg.Add("Progress", "x16 y+3 w410 h1 BackgroundE0E0E0 cE0E0E0", 100)
    dlg.Add("CheckBox", "x28 y+10 vChkSoundFeedback" (g_soundFeedback ? " Checked" : ""), "Sound feedback on mute/unmute")
    dlg.Add("CheckBox", "x28 y+6 vChkOSD" (g_osdEnabled ? " Checked" : ""), "On-screen display bubble on mute/unmute")
    dlg.Add("Text", "x48 y+4 c888888", "Duration (ms):")
    dlg.Add("Edit", "x+6 yp-3 w55 Number vEdtOSDDur", g_osdDuration)
    dlg.Add("CheckBox", "x28 y+6 vChkMuteLock" (g_muteLock ? " Checked" : ""), "Mute Lock (prevent external apps from changing mute state)")
    dlg.Add("CheckBox", "x28 y+6 vChkMiddleClick" (g_middleClickToggle ? " Checked" : ""), "Middle-click tray icon to toggle Toggle/PTT mode")
    dlg.Add("CheckBox", "x28 y+6 vChkRunAtStartup" (FileExist(A_Startup "\MicMute.lnk") ? " Checked" : ""), "Run at startup")
    dlg.Add("Text", "x28 y+10", "On startup:")
    startOpts := ["Don't change", "Always muted", "Always unmuted", "Remember last"]
    ddlStart := dlg.Add("DropDownList", "x+8 yp-3 w130 vDdlStartMuted", startOpts)
    _startIdx := Map("no", 1, "yes", 2, "unmuted", 3, "last", 4)
    ddlStart.Value := _startIdx.Has(g_startMuted) ? _startIdx[g_startMuted] : 1

    ; ── Hotkeys ──
    dlg.SetFont("s9 Bold", "Segoe UI")
    dlg.Add("Text", "x16 y+14 w410 c444444", "Hotkeys")
    dlg.SetFont("s9 norm", "Segoe UI")
    dlg.Add("Progress", "x16 y+3 w410 h1 BackgroundE0E0E0 cE0E0E0", 100)
    dlg.Add("Text", "x28 y+10", "Global deafen hotkey:")
    dlg.Add("Hotkey", "x+8 yp-3 w130 vHkDeafen", g_deafenHotkey)
    dlg.Add("Edit", "x+0 yp w0 h0 vEdtDeafenHK Hidden")  ; hidden store for manual WinKey value
    dlg.Add("Button", "x+6 yp w90", "WinKey…").OnEvent("Click", (*) => ShowManualDeafenHK(dlg))

    ; ── Custom Files ──
    dlg.SetFont("s9 Bold", "Segoe UI")
    dlg.Add("Text", "x16 y+14 w410 c444444", "Custom Files")
    dlg.SetFont("s9 norm", "Segoe UI")
    dlg.Add("Progress", "x16 y+3 w410 h1 BackgroundE0E0E0 cE0E0E0", 100)
    dlg.Add("Text", "x28 y+10 w75", "Muted icon:")
    dlg.Add("Edit", "x+0 yp w0 h0 vEdtIconMuted Hidden", g_iconMuted)
    dlg.Add("Button", "x106 yp-3 w65", "Browse…").OnEvent("Click", (*) => BrowseForFile(dlg, "EdtIconMuted", "LblIconMuted", "Icon files (*.ico)"))
    dlg.Add("Button", "x+3 yp w45", "Clear").OnEvent("Click", (*) => ClearFileField(dlg, "EdtIconMuted", "LblIconMuted"))
    dlg.Add("Text", "x+6 yp+3 c555555 vLblIconMuted", FileLabel(g_iconMuted))
    dlg.Add("Text", "x28 y+8 w75", "Active icon:")
    dlg.Add("Edit", "x+0 yp w0 h0 vEdtIconActive Hidden", g_iconActive)
    dlg.Add("Button", "x106 yp-3 w65", "Browse…").OnEvent("Click", (*) => BrowseForFile(dlg, "EdtIconActive", "LblIconActive", "Icon files (*.ico)"))
    dlg.Add("Button", "x+3 yp w45", "Clear").OnEvent("Click", (*) => ClearFileField(dlg, "EdtIconActive", "LblIconActive"))
    dlg.Add("Text", "x+6 yp+3 c555555 vLblIconActive", FileLabel(g_iconActive))
    dlg.Add("Text", "x28 y+8 w75", "Mute sound:")
    dlg.Add("Edit", "x+0 yp w0 h0 vEdtMuteSound Hidden", g_muteSound)
    dlg.Add("Button", "x106 yp-3 w65", "Browse…").OnEvent("Click", (*) => BrowseForFile(dlg, "EdtMuteSound", "LblMuteSound", "Sound files (*.wav)"))
    dlg.Add("Button", "x+3 yp w45", "Clear").OnEvent("Click", (*) => ClearFileField(dlg, "EdtMuteSound", "LblMuteSound"))
    dlg.Add("Text", "x+6 yp+3 c555555 vLblMuteSound", FileLabel(g_muteSound))
    dlg.Add("Text", "x28 y+8 w75", "Unmute sound:")
    dlg.Add("Edit", "x+0 yp w0 h0 vEdtUnmuteSound Hidden", g_unmuteSound)
    dlg.Add("Button", "x106 yp-3 w65", "Browse…").OnEvent("Click", (*) => BrowseForFile(dlg, "EdtUnmuteSound", "LblUnmuteSound", "Sound files (*.wav)"))
    dlg.Add("Button", "x+3 yp w45", "Clear").OnEvent("Click", (*) => ClearFileField(dlg, "EdtUnmuteSound", "LblUnmuteSound"))
    dlg.Add("Text", "x+6 yp+3 c555555 vLblUnmuteSound", FileLabel(g_unmuteSound))

    ; ── Buttons ──
    dlg.Add("Button", "x16 y+18 w80", "GitHub").OnEvent("Click", (*) => Run("https://github.com/itsnateai/MicMute"))
    dlg.Add("Button", "x+6 yp w55", "Help").OnEvent("Click", (*) => ShowHelpWindow())
    dlg.Add("Button", "x170 yp w80 Default", "OK").OnEvent("Click", (*) => ApplySettingsGUI(dlg, true))
    dlg.Add("Button", "x+8 w80", "Apply").OnEvent("Click", (*) => ApplySettingsGUI(dlg, false))
    dlg.Add("Button", "x+8 w80", "Cancel").OnEvent("Click", (*) => CloseSettingsGUI(dlg))
    dlg.OnEvent("Close", (*) => CloseSettingsGUI(dlg))
    g_settingsGui := dlg
    dlg.Show("AutoSize")
}

CloseSettingsGUI(dlg) {
    global g_settingsGui
    dlg.Destroy()
    g_settingsGui := 0
}

BrowseForFile(dlg, editName, lblName, filter) {
    picked := FileSelect(1, , "Select file", filter)
    if (picked != "") {
        dlg[editName].Value := picked
        dlg[lblName].Value := FileLabel(picked)
    }
}

ClearFileField(dlg, editName, lblName) {
    dlg[editName].Value := ""
    dlg[lblName].Value := "(none)"
}

FileLabel(path) {
    if (path = "")
        return "(none)"
    SplitPath(path, &name)
    return name
}

ShowManualDeafenHK(parentDlg) {
    pop := Gui("+AlwaysOnTop +Owner" parentDlg.Hwnd, "Manual WinKey Hotkey")
    pop.SetFont("s10", "Segoe UI")
    pop.Add("Text", , "Type AHK hotkey syntax:")
    edt := pop.Add("Edit", "w200 vManualHK", parentDlg["EdtDeafenHK"].Value)
    pop.Add("Text", "y+6 c888888", "Examples:  #+d = Win+Shift+D    #F9 = Win+F9")
    pop.Add("Button", "Default w70 y+12", "OK").OnEvent("Click", (*) => ApplyManualDeafenHK(pop, parentDlg, edt))
    pop.Add("Button", "x+8 w70", "Clear").OnEvent("Click", (*) => ClearManualDeafenHK(pop, parentDlg))
    pop.Add("Button", "x+8 w70", "Cancel").OnEvent("Click", (*) => pop.Destroy())
    pop.OnEvent("Close", (*) => pop.Destroy())
    pop.Show()
}

ApplyManualDeafenHK(pop, parentDlg, edt) {
    val := Trim(edt.Value)
    parentDlg["EdtDeafenHK"].Value := val
    if (val != "")
        parentDlg["HkDeafen"].Value := ""  ; clear Hotkey control — manual takes priority
    pop.Destroy()
}

ClearManualDeafenHK(pop, parentDlg) {
    parentDlg["EdtDeafenHK"].Value := ""
    pop.Destroy()
}

ApplySettingsGUI(dlg, close := true) {
    global
    ; Capture DDL index BEFORE Submit() — Submit can reset control state
    startValues := ["no", "yes", "unmuted", "last"]
    ddlIdx := dlg["DdlStartMuted"].Value
    startVal := (ddlIdx >= 1 && ddlIdx <= 4) ? startValues[ddlIdx] : "no"

    ; Submit(true) hides the GUI (OK), Submit(false) keeps it open (Apply)
    saved := dlg.Submit(close)

    ; Behavior
    g_soundFeedback := saved.ChkSoundFeedback
    g_osdEnabled := saved.ChkOSD
    g_muteLock := saved.ChkMuteLock
    g_lockDebounce := false
    g_middleClickToggle := saved.ChkMiddleClick
    g_startMuted := startVal
    ; Run at startup — create or remove shortcut
    shortcut := A_Startup "\MicMute.lnk"
    if saved.ChkRunAtStartup && !FileExist(shortcut) {
        if A_IsCompiled
            FileCreateShortcut(A_ScriptFullPath, shortcut, A_ScriptDir,
                , "MicMute — Global mic mute toggle", A_ScriptFullPath)
        else
            FileCreateShortcut(A_AhkPath, shortcut, A_ScriptDir,
                '`"' A_ScriptFullPath '`"', "MicMute — Global mic mute toggle")
    } else if !saved.ChkRunAtStartup && FileExist(shortcut) {
        FileDelete(shortcut)
    }
    ; OSD
    newDur := 1500
    try newDur := Integer(Trim(saved.EdtOSDDur))
    if (newDur < 500)
        newDur := 500
    g_osdDuration := newDur

    ; Deafen hotkey — prefer raw text (supports Win combos), fall back to Hotkey control
    rawDeafen := Trim(saved.EdtDeafenHK)
    newDeafenHK := (rawDeafen != "") ? rawDeafen : saved.HkDeafen
    if (newDeafenHK != g_deafenHotkey) {
        if (g_deafenHotkey != "")
            try Hotkey(g_deafenHotkey, "Off")
        g_deafenHotkey := newDeafenHK
        RegisterDeafenHotkey()
    }

    ; Custom icons — rebuild icon paths and refresh tray
    ; File paths stored here; embedded PE resources handled in SetTrayIcon() fallback
    g_iconMuted := Trim(saved.EdtIconMuted)
    g_iconActive := Trim(saved.EdtIconActive)
    g_icoRed := (g_iconMuted != "" && FileExist(g_iconMuted)) ? g_iconMuted
        : FileExist(A_ScriptDir "\mic_off.ico") ? A_ScriptDir "\mic_off.ico" : ""
    g_icoGreen := (g_iconActive != "" && FileExist(g_iconActive)) ? g_iconActive
        : FileExist(A_ScriptDir "\mic_on.ico") ? A_ScriptDir "\mic_on.ico" : ""
    SetTrayIcon()

    ; Custom sounds
    g_muteSound := Trim(saved.EdtMuteSound)
    g_unmuteSound := Trim(saved.EdtUnmuteSound)

    ; Persist and refresh
    SaveConfig()
    BuildTrayMenu()
    if close {
        dlg.Destroy()
        g_settingsGui := 0
    }
    if close {
        ToolTip("Settings saved.")
        SetTimer(() => ToolTip(), -3000)
    } else {
        ToolTip("Settings applied.")
        SetTimer(() => ToolTip(), -2000)
    }
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Audio device selector (P2-02)                                           ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Enumerate capture devices and return an array of {name, id} objects.
EnumCaptureDevices() {
    devices := []
    ; Static GUID/PKEY buffers — allocated once across calls
    static CLSID_MMEnum := 0, IID_MMEnum := 0, PKEY := 0, _guidsInit := false
    if !_guidsInit {
        CLSID_MMEnum := Buffer(16)
        IID_MMEnum   := Buffer(16)
        PKEY         := Buffer(20, 0)
        DllCall("ole32\CLSIDFromString", "WStr", "{BCDE0395-E52F-467C-8E3D-C4579291692E}", "Ptr", CLSID_MMEnum)
        DllCall("ole32\CLSIDFromString", "WStr", "{A95664D2-9614-4F35-A746-DE8DB63617E6}", "Ptr", IID_MMEnum)
        DllCall("ole32\CLSIDFromString", "WStr", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "Ptr", PKEY)
        NumPut("UInt", 14, PKEY, 16)
        _guidsInit := true
    }

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
        ToolTip("Using system default microphone.")
    else
        ToolTip("Switched microphone.")
    SetTimer(() => ToolTip(), -3000)
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Tray menu                                                               ║
; ╚══════════════════════════════════════════════════════════════════════════╝

BuildTrayMenu() {
    global g_hotkey, g_version, g_soundFeedback, g_mode, g_deviceId
    hotkeyLabel := "Hotkey: " HotkeyToReadable(g_hotkey)

    A_TrayMenu.Delete()
    titleItem := "Toggle Mute — v" g_version
    A_TrayMenu.Add(titleItem,            (*) => ToggleMute())
    A_TrayMenu.Default := titleItem       ; bold text — marks it as the primary action
    A_TrayMenu.Add()
    hotkeyItem := "Hotkey: " HotkeyToReadable(g_hotkey)
    A_TrayMenu.Add(hotkeyItem,          (*) => ShowHotkeyDialog())

    ; ── Mode submenu (P2-01) ──
    modeMenu := Menu()
    modeMenu.Add("Toggle",              (*) => SetMode("toggle"))
    modeMenu.Add("Push-to-Talk",        (*) => SetMode("push-to-talk"))
    if (g_mode = "push-to-talk")
        modeMenu.Check("Push-to-Talk")
    else
        modeMenu.Check("Toggle")
    modeLabel := "Mode: " FormatModeName(g_mode)
    A_TrayMenu.Add(modeLabel, modeMenu)

    ; ── Device submenu (P2-02) — lazy-loaded on first open ──
    global g_devMenu := Menu()
    g_devMenu.Add("Loading…", (*) => 0)
    g_devMenu.Disable("Loading…")
    A_TrayMenu.Add("Mic Source", g_devMenu)
    global g_devMenuPopulated := false

    A_TrayMenu.Add()
    A_TrayMenu.Add("Settings…",     (*) => ShowSettingsGUI())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reinit Mic",    (*) => ReinitMic())
    A_TrayMenu.Add("Sound Settings", (*) => Run("ms-settings:sound"))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit",          (*) => ExitApp())
    A_TrayMenu.Default    := titleItem
    A_TrayMenu.ClickCount := 1           ; single left-click fires default item
}

; Populate the Microphone submenu on demand (lazy-loaded to speed up startup).
PopulateDeviceMenu() {
    global g_deviceId, g_devMenu, g_devMenuPopulated
    g_devMenu.Delete()
    g_devMenu.Add("System Default", SelectDevice.Bind(""))
    if (g_deviceId = "")
        g_devMenu.Check("System Default")
    g_devMenu.Add()
    devList := EnumCaptureDevices()
    for dev in devList {
        label := StrLen(dev.name) > 40 ? SubStr(dev.name, 1, 37) "…" : dev.name
        g_devMenu.Add(label, SelectDevice.Bind(dev.id))
        if (g_deviceId = dev.id)
            g_devMenu.Check(label)
    }
    g_devMenuPopulated := true
}


; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Configuration (INI file)                                                ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Ensure INI file has correct encoding. UTF-16 LE without BOM confuses the
; Windows INI API (GetPrivateProfileString), causing reads to return truncated
; values.  If detected, re-encode to UTF-8 (which the API handles natively).
FixIniEncoding() {
    ini := A_ScriptDir "\MicMute.ini"
    if !FileExist(ini)
        return
    try {
        f := FileOpen(ini, "r", "RAW")
        if !f || f.Length < 4
            return
        b1 := f.ReadUChar()
        b2 := f.ReadUChar()
        f.Close()
        ; Already has UTF-16 BOM or is plain ANSI — nothing to fix
        if (b1 = 0xFF && b2 = 0xFE) || (b2 != 0x00)
            return
        ; UTF-16 LE without BOM — read as UTF-16 and rewrite as UTF-8
        content := FileRead(ini, "UTF-16-RAW")
        FileDelete(ini)
        FileAppend(content, ini, "CP0")
    }
}

; Read settings from MicMute.ini if it exists. Falls back to defaults.
LoadConfig() {
    global
    ini := A_ScriptDir "\MicMute.ini"
    if !FileExist(ini)
        return
    FixIniEncoding()
    g_hotkey        := IniRead(ini, "General", "Hotkey", g_hotkey)
    g_soundFeedback := (Trim(IniRead(ini, "General", "SoundFeedback", "1")) = "1")
    g_mode          := Trim(IniRead(ini, "General", "Mode", "toggle"))
    g_deviceId      := Trim(IniRead(ini, "General", "DeviceId", ""))
    g_iconMuted     := Trim(IniRead(ini, "General", "IconMuted", ""))
    g_iconActive    := Trim(IniRead(ini, "General", "IconActive", ""))
    ; g_ledIndicator removed (F-16 deprecated)
    g_muteLock      := (Trim(IniRead(ini, "General", "MuteLock", "0")) = "1")
    g_muteSound     := Trim(IniRead(ini, "General", "MuteSound", ""))
    g_unmuteSound   := Trim(IniRead(ini, "General", "UnmuteSound", ""))
    g_osdEnabled    := (Trim(IniRead(ini, "General", "OSD_Enabled", "0")) = "1")
    try g_osdDuration := Integer(Trim(IniRead(ini, "General", "OSD_Duration", "1500")))
    catch
        g_osdDuration := 1500
    if (g_osdDuration < 500)
        g_osdDuration := 500
    g_deafenHotkey  := Trim(IniRead(ini, "General", "DeafenHotkey", ""))
    g_middleClickToggle := (Trim(IniRead(ini, "General", "MiddleClickToggle", "1")) = "1")
    g_startMuted    := StrLower(Trim(IniRead(ini, "General", "StartMuted", "no")))
    if (g_startMuted != "no" && g_startMuted != "yes" && g_startMuted != "unmuted" && g_startMuted != "last")
        g_startMuted := "no"
    ; Validate mode
    if (g_mode != "toggle" && g_mode != "push-to-talk")
        g_mode := "toggle"
}

; Save current settings to MicMute.ini.
SaveConfig() {
    global
    ini := A_ScriptDir "\MicMute.ini"
    IniWrite(g_hotkey, ini, "General", "Hotkey")
    IniWrite(g_soundFeedback ? "1" : "0", ini, "General", "SoundFeedback")
    IniWrite(g_mode, ini, "General", "Mode")
    IniWrite(g_deviceId, ini, "General", "DeviceId")
    IniWrite(g_iconMuted, ini, "General", "IconMuted")
    IniWrite(g_iconActive, ini, "General", "IconActive")
    ; LEDIndicator removed (F-16 deprecated)
    IniWrite(g_osdEnabled ? "1" : "0", ini, "General", "OSD_Enabled")
    IniWrite(g_osdDuration, ini, "General", "OSD_Duration")
    IniWrite(g_muteLock ? "1" : "0", ini, "General", "MuteLock")
    IniWrite(g_muteSound, ini, "General", "MuteSound")
    IniWrite(g_unmuteSound, ini, "General", "UnmuteSound")
    IniWrite(g_deafenHotkey, ini, "General", "DeafenHotkey")
    IniWrite(g_middleClickToggle ? "1" : "0", ini, "General", "MiddleClickToggle")
    IniWrite(g_startMuted, ini, "General", "StartMuted")
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
    prefix := RegExMatch(hk, "^([<>#^!+]+)", &m) ? m[1] : ""
    key    := RegExReplace(hk, "^[<>#^!+]+", "")
    side   := InStr(prefix, "<") ? "L" : InStr(prefix, ">") ? "R" : ""
    if (InStr(prefix, "#"))
        mods .= side . "Win + "
    if (InStr(prefix, "^"))
        mods .= side . "Ctrl + "
    if (InStr(prefix, "!"))
        mods .= side . "Alt + "
    if (InStr(prefix, "+"))
        mods .= side . "Shift + "
    return mods . StrUpper(key)
}

; Initialise IAudioEndpointVolume for a capture (mic) device.
; If g_deviceId is set, uses that specific device. Otherwise uses the system default.
; Returns the COM pointer on success, or 0 on failure (shows a ToolTip
; but does NOT exit — the script stays alive so the user can reinitialise).
; If silent=true, suppresses ToolTip notifications (used by periodic auto-detect).
InitMicEndpoint(silent := false) {
    global g_deviceId
    ; Static GUID buffers — avoid re-allocating on every call (hot path in degraded mode)
    static CLSID_MMEnum := 0, IID_MMEnum := 0, IID_AEV := 0, _guidsInit := false
    if !_guidsInit {
        CLSID_MMEnum := Buffer(16)
        IID_MMEnum   := Buffer(16)
        IID_AEV      := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{BCDE0395-E52F-467C-8E3D-C4579291692E}", "Ptr", CLSID_MMEnum)
        DllCall("ole32\CLSIDFromString", "WStr", "{A95664D2-9614-4F35-A746-DE8DB63617E6}", "Ptr", IID_MMEnum)
        DllCall("ole32\CLSIDFromString", "WStr", "{5CDF2C82-841E-4546-9722-0CF74078229A}", "Ptr", IID_AEV)
        _guidsInit := true
    }

    hr := DllCall("ole32\CoCreateInstance",
        "Ptr",  CLSID_MMEnum,
        "Ptr",  0,
        "UInt", 1,
        "Ptr",  IID_MMEnum,
        "Ptr*", &pEnum := 0,
        "Int")
    if (hr < 0 || !pEnum) {
        if !silent {
            ToolTip("Audio init failed (0x" Format("{:08X}", hr & 0xFFFFFFFF) ").`nUse Tray → Reinitialise Mic.")
            SetTimer(() => ToolTip(), -5000)
        }
        return 0
    }

    pDev := 0
    if (g_deviceId != "") {
        ; Use specific device by ID: IMMDeviceEnumerator::GetDevice(pwstrId)
        hr := ComCall(5, pEnum, "WStr", g_deviceId, "Ptr*", &pDev := 0, "Int")
        if (hr < 0 || !pDev) {
            ; Specific device not found — fall back to system default
            if !silent
                ToolTip("Saved device not found — using system default.")
            hr := ComCall(4, pEnum, "UInt", 1, "UInt", 0, "Ptr*", &pDev := 0, "Int")
        }
    } else {
        ; GetDefaultAudioEndpoint(eCapture=1, eConsole=0)
        hr := ComCall(4, pEnum, "UInt", 1, "UInt", 0, "Ptr*", &pDev := 0, "Int")
    }
    ObjRelease(pEnum)
    if (hr < 0 || !pDev) {
        if !silent {
            ToolTip("No microphone found.`nConnect one and use Tray → Reinitialise Mic.")
            SetTimer(() => ToolTip(), -5000)
        }
        return 0
    }

    ; CLSCTX_INPROC_SERVER = 1 (standard context for audio endpoint activation)
    hr := ComCall(3, pDev, "Ptr", IID_AEV, "UInt", 1, "Ptr", 0, "Ptr*", &pAEV := 0, "Int")
    ObjRelease(pDev)
    if (hr < 0 || !pAEV) {
        if !silent {
            ToolTip("Mic activation failed (0x" Format("{:08X}", hr & 0xFFFFFFFF) ").`nUse Tray → Reinitialise Mic.")
            SetTimer(() => ToolTip(), -5000)
        }
        return 0
    }

    return pAEV
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Tray notification handler                                              ║
; ╚══════════════════════════════════════════════════════════════════════════╝

; Handle tray icon notification events (right-click, middle-click).
OnTrayNotify(wParam, lParam, msg, hwnd) {
    global g_devMenuPopulated, g_mode, g_middleClickToggle
    event := lParam & 0xFFFF
    if (event = 0x205) {   ; WM_RBUTTONUP — context menu about to open
        if !g_devMenuPopulated
            PopulateDeviceMenu()
    }
    if (event = 0x208) {   ; WM_MBUTTONUP — middle-click to toggle mode
        if g_middleClickToggle
            SetMode((g_mode = "toggle") ? "push-to-talk" : "toggle")
    }
    ; Return nothing — let AHK's default tray handler process the event
}

; Release COM handle and clean up on exit.
Cleanup(*) {
    global g_pAEV, g_muted
    global g_deafened, g_speakerWasMuted
    ; Restore speaker state if deafened (F-20)
    if g_deafened
        try SoundSetMute(g_speakerWasMuted)
    if g_pAEV {
        ; Unmute on exit (F-10) — prevent "dead mic" after MicMute closes
        if g_muted
            try ComCall(14, g_pAEV, "Int", false, "Ptr", 0, "Int")   ; SetMute(false)
        ObjRelease(g_pAEV)
    }
}

