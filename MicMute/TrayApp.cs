using System.Runtime.InteropServices;

namespace MicMute;

/// <summary>
/// Main application form — runs as a hidden window with a system tray icon.
/// Handles global hotkeys, mute state management, periodic sync, and all UI.
/// </summary>
internal sealed class TrayApp : Form
{
    private const int HOTKEY_ID_MAIN = 1;
    private const int HOTKEY_ID_DEAFEN = 2;

    private readonly Config _config;
    private readonly AudioManager _audio;
    private readonly NotifyIcon _trayIcon;
    private readonly ContextMenuStrip _trayMenu;
    private readonly System.Windows.Forms.Timer _syncTimer;
    private readonly OsdForm _osdForm;

    // Cached icons — loaded once at startup
    private Icon _iconActive;
    private Icon _iconMuted;

    // State
    private bool _muted;
    private bool _deafened;
    private bool _speakerWasMuted;
    private bool _lockDebounce;
    private bool _flashing;
    private int _flashCount;
    private readonly System.Windows.Forms.Timer _flashTimer;

    // Explorer restart detection
    private readonly uint _wmTaskbarCreated;

    // Cached tooltip strings — only rebuilt on state change
    private string _cachedTooltipMuted = "";
    private string _cachedTooltipActive = "";
    private string _cachedTooltipMode = "";
    private bool _tooltipDirty = true;

    // Track registered hotkeys for cleanup
    private bool _mainHotkeyRegistered;
    private bool _deafenHotkeyRegistered;

    // Singleton dialogs
    private SettingsDialog _settingsDialog;

    // Device menu lazy loading
    private ToolStripMenuItem _deviceMenuItem;
    private bool _deviceMenuPopulated;

    private bool _disposed;

    public TrayApp()
    {
        // Hidden window — no taskbar presence
        ShowInTaskbar = false;
        WindowState = FormWindowState.Minimized;
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        Opacity = 0;
        Size = Size.Empty;

        _config = new Config();
        _config.Load();

        _audio = new AudioManager();

        // Load icons
        LoadIcons();

        // Initialize audio endpoint
        bool hasAudio = _audio.Initialize(_config.DeviceId);

        // Read initial mute state
        if (hasAudio)
        {
            bool? currentMute = _audio.GetMute();
            _muted = currentMute ?? false;
            ApplyStartupMutePreference();
        }

        // Tray icon
        _trayMenu = new ContextMenuStrip();
        _trayIcon = new NotifyIcon
        {
            Visible = true,
            ContextMenuStrip = _trayMenu,
        };
        _trayIcon.MouseClick += OnTrayMouseClick;

        // Build menu
        BuildTrayMenu();
        InvalidateTooltipCache();
        SyncTrayIcon();

        // Register hotkeys
        RegisterMainHotkey();
        RegisterDeafenHotkey();

        // Explorer restart recovery
        _wmTaskbarCreated = NativeMethods.RegisterWindowMessage("TaskbarCreated");

        // Flash timer (reusable, not started)
        _flashTimer = new System.Windows.Forms.Timer { Interval = 100 };
        _flashTimer.Tick += OnFlashTick;

        // OSD form (reusable)
        _osdForm = new OsdForm();

        // Periodic sync timer — 5 seconds
        _syncTimer = new System.Windows.Forms.Timer { Interval = 5000 };
        _syncTimer.Tick += OnSyncTick;
        _syncTimer.Start();

        // Show notification if no mic found
        if (!hasAudio)
        {
            ShowTimedTooltip("No microphone detected.\nPlug one in \u2014 MicMute will auto-detect it.", 5000);
        }
    }

    // ── Icon Loading ──────────────────────────────────────────────────────

    private void LoadIcons()
    {
        _iconActive = LoadIcon(_config.IconActive, "mic_on.ico");
        _iconMuted = LoadIcon(_config.IconMuted, "mic_off.ico");
    }

    private static Icon LoadIcon(string customPath, string embeddedName)
    {
        // Priority: custom path > file on disk next to exe > embedded resource
        if (!string.IsNullOrEmpty(customPath) && File.Exists(customPath))
        {
            try { return new Icon(customPath); }
            catch { /* fall through */ }
        }

        string dir = Path.GetDirectoryName(Environment.ProcessPath ?? "") ?? "";
        string diskPath = Path.Combine(dir, embeddedName);
        if (File.Exists(diskPath))
        {
            try { return new Icon(diskPath); }
            catch { /* fall through */ }
        }

        // Embedded resource
        var stream = typeof(TrayApp).Assembly.GetManifestResourceStream(embeddedName);
        if (stream != null)
            return new Icon(stream);

        // Ultimate fallback — system icon
        return SystemIcons.Application;
    }

    // ── Tray Icon / Tooltip ──────────────────────────────────────────────

    private void InvalidateTooltipCache()
    {
        string modeName = _config.Mode == "push-to-talk" ? " [PTT]" : "";
        string suffix = _deafened ? " [DEAFENED]" : "";
        _cachedTooltipMode = modeName + suffix;
        _cachedTooltipMuted = "MicMute v" + Config.Version + " \u2014 Mic: MUTED" + _cachedTooltipMode;
        _cachedTooltipActive = "MicMute v" + Config.Version + " \u2014 Mic: Active" + _cachedTooltipMode;
        _tooltipDirty = false;
    }

    private void SyncTrayIcon()
    {
        if (_flashing)
            return;
        SetTrayIcon();
    }

    private void SetTrayIcon()
    {
        if (_tooltipDirty)
            InvalidateTooltipCache();

        var icon = _muted ? _iconMuted : _iconActive;
        var tooltip = _muted ? _cachedTooltipMuted : _cachedTooltipActive;

        if (_trayIcon.Icon != icon)
            _trayIcon.Icon = icon;
        // NotifyIcon tooltip max 63 chars
        if (tooltip.Length > 63)
            tooltip = tooltip[..63];
        if (_trayIcon.Text != tooltip)
            _trayIcon.Text = tooltip;
    }

    // ── Core Mute Operations ─────────────────────────────────────────────

    private void ToggleMute()
    {
        if (!_audio.HasEndpoint)
        {
            ShowTimedTooltip("No microphone available.\nTry Tray \u2192 Reinitialise Mic.", 5000);
            return;
        }

        bool newState = !_muted;
        if (!_audio.SetMute(newState))
        {
            ShowTimedTooltip("SetMute failed. Device may have changed \u2014 try Reinitialise Mic.", 5000);
            return;
        }

        _muted = newState;
        _config.SaveLastMuteState(_muted);
        SyncTrayIcon();
        FlashIcon();
        ShowOsd();
        PlayFeedback();
    }

    private void SetMuteState(bool muted, bool quiet = false)
    {
        if (!_audio.HasEndpoint || _muted == muted)
            return;

        if (!_audio.SetMute(muted))
            return;

        _muted = muted;
        _config.SaveLastMuteState(_muted);
        SyncTrayIcon();

        if (!quiet)
        {
            FlashIcon();
            ShowOsd();
            PlayFeedback();
        }
    }

    // ── Sound Feedback ───────────────────────────────────────────────────

    private void PlayFeedback()
    {
        if (!_config.SoundFeedback)
            return;

        string soundFile = _muted ? _config.MuteSound : _config.UnmuteSound;
        if (!string.IsNullOrEmpty(soundFile) && File.Exists(soundFile))
        {
            if (!NativeMethods.PlaySound(soundFile, 0,
                NativeMethods.SND_FILENAME | NativeMethods.SND_SYNC | NativeMethods.SND_NODEFAULT))
            {
                PlayToneSequence(_muted);
            }
        }
        else
        {
            PlayToneSequence(_muted);
        }
    }

    private static void PlayToneSequence(bool muted)
    {
        NativeMethods.Beep(muted ? 587u : 880u, 80);
    }

    private static void PlayModeChirp(string mode)
    {
        NativeMethods.Beep(mode == "push-to-talk" ? 1568u : 1175u, 50);
    }

    // ── OSD ──────────────────────────────────────────────────────────────

    private void ShowOsd()
    {
        if (!_config.OsdEnabled)
            return;
        _osdForm.ShowOsd(_muted, _config.OsdDuration);
    }

    // ── Icon Flash ───────────────────────────────────────────────────────

    private void FlashIcon()
    {
        if (_flashing)
            _flashTimer.Stop();
        _flashing = true;
        _flashCount = 0;
        _flashTimer.Start();
    }

    private void OnFlashTick(object sender, EventArgs e)
    {
        bool showOpposite = (_flashCount % 2) == 0;
        if (showOpposite)
        {
            // Show opposite icon
            _trayIcon.Icon = _muted ? _iconActive : _iconMuted;
        }
        else
        {
            SetTrayIcon();
        }

        _flashCount++;
        if (_flashCount >= 2)
        {
            _flashTimer.Stop();
            _flashing = false;
            SetTrayIcon();
        }
    }

    // ── Periodic Sync ────────────────────────────────────────────────────

    private void OnSyncTick(object sender, EventArgs e)
    {
        if (!_audio.HasEndpoint)
        {
            // Try to find a newly plugged-in mic
            if (_audio.Initialize(_config.DeviceId))
            {
                ShowTimedTooltip("Microphone detected \u2014 auto-connected.", 3000);
                bool? m = _audio.GetMute();
                _muted = m ?? false;
                SyncTrayIcon();
            }
            return;
        }

        // Check if device is still valid
        bool? currentMute = _audio.GetMute();
        if (currentMute == null)
        {
            // Device went away
            _audio.Release();
            _muted = false;
            SyncTrayIcon();
            ShowTimedTooltip("Microphone disconnected.\nWill auto-reconnect when available.", 5000);
            return;
        }

        bool externalMuted = currentMute.Value;
        if (externalMuted != _muted)
        {
            if (_config.MuteLock)
            {
                // Fight back: re-apply our state
                if (_lockDebounce)
                {
                    _lockDebounce = false;
                    return;
                }
                _audio.SetMute(_muted);
                _lockDebounce = true;
            }
            else
            {
                // Accept external change
                _muted = externalMuted;
                SyncTrayIcon();
            }
        }
        else
        {
            _lockDebounce = false;
        }
    }

    // ── Hotkey Registration ──────────────────────────────────────────────

    private void RegisterMainHotkey()
    {
        UnregisterMainHotkey();

        if (!Config.ParseHotkey(_config.Hotkey, out uint mods, out uint vk))
        {
            ShowTimedTooltip("Invalid hotkey: " + _config.Hotkey + "\nFalling back to tray-only mode.", 5000);
            return;
        }

        if (NativeMethods.RegisterHotKey(Handle, HOTKEY_ID_MAIN, mods, vk))
            _mainHotkeyRegistered = true;
        else
            ShowTimedTooltip("Could not register hotkey: " + Config.HotkeyToReadable(_config.Hotkey), 5000);
    }

    private void UnregisterMainHotkey()
    {
        if (_mainHotkeyRegistered)
        {
            NativeMethods.UnregisterHotKey(Handle, HOTKEY_ID_MAIN);
            _mainHotkeyRegistered = false;
        }
    }

    private void RegisterDeafenHotkey()
    {
        UnregisterDeafenHotkey();

        if (string.IsNullOrEmpty(_config.DeafenHotkey))
            return;

        if (!Config.ParseHotkey(_config.DeafenHotkey, out uint mods, out uint vk))
        {
            ShowTimedTooltip("Invalid deafen hotkey: " + _config.DeafenHotkey, 5000);
            return;
        }

        if (NativeMethods.RegisterHotKey(Handle, HOTKEY_ID_DEAFEN, mods, vk))
            _deafenHotkeyRegistered = true;
        else
            ShowTimedTooltip("Could not register deafen hotkey.", 5000);
    }

    private void UnregisterDeafenHotkey()
    {
        if (_deafenHotkeyRegistered)
        {
            NativeMethods.UnregisterHotKey(Handle, HOTKEY_ID_DEAFEN);
            _deafenHotkeyRegistered = false;
        }
    }

    // ── WndProc ──────────────────────────────────────────────────────────

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == NativeMethods.WM_HOTKEY)
        {
            int id = m.WParam.ToInt32();
            if (id == HOTKEY_ID_MAIN)
            {
                if (_config.Mode == "push-to-talk")
                    HandlePushToTalk();
                else
                    ToggleMute();
            }
            else if (id == HOTKEY_ID_DEAFEN)
            {
                ToggleDeafen();
            }
        }
        else if (_wmTaskbarCreated != 0 && m.Msg == (int)_wmTaskbarCreated)
        {
            // Explorer restarted — re-show tray icon
            _trayIcon.Visible = true;
            SyncTrayIcon();
        }

        base.WndProc(ref m);
    }

    // ── Push-to-Talk ─────────────────────────────────────────────────────
    // Win32 RegisterHotKey doesn't directly support key-up events.
    // We use a low-level approach: on WM_HOTKEY, unmute and start polling
    // for key release via a short timer, then re-mute on release.

    private System.Windows.Forms.Timer _pttTimer;
    private uint _pttVk;

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    private void HandlePushToTalk()
    {
        SetMuteState(false, true); // unmute while held

        // Parse the VK for polling
        if (!Config.ParseHotkey(_config.Hotkey, out _, out uint vk))
            return;
        _pttVk = vk;

        // Start polling for key release
        if (_pttTimer == null)
        {
            _pttTimer = new System.Windows.Forms.Timer { Interval = 30 };
            _pttTimer.Tick += OnPttPoll;
        }
        _pttTimer.Start();
    }

    private void OnPttPoll(object sender, EventArgs e)
    {
        // Check if the key is still held
        short state = GetAsyncKeyState((int)_pttVk);
        bool held = (state & 0x8000) != 0;
        if (!held)
        {
            _pttTimer.Stop();
            if (_config.Mode == "push-to-talk") // guard against mode switch while held
                SetMuteState(true, true);
        }
    }

    // ── Deafen Mode ──────────────────────────────────────────────────────

    private void ToggleDeafen()
    {
        if (!_audio.HasEndpoint)
            return;

        if (!_deafened)
        {
            // Enter deafen
            try { _speakerWasMuted = AudioManager.GetSpeakerMute(); }
            catch { _speakerWasMuted = false; }

            if (!_muted)
                SetMuteState(true);
            try { AudioManager.SetSpeakerMute(true); }
            catch { /* ignore */ }

            _deafened = true;
            _tooltipDirty = true;
            SetTrayIcon();
            ShowTimedTooltip("DEAFENED \u2014 mic + speakers muted", 3000);
        }
        else
        {
            // Exit deafen
            _lockDebounce = true;
            SetMuteState(false);
            try { AudioManager.SetSpeakerMute(_speakerWasMuted); }
            catch { /* ignore */ }

            _deafened = false;
            _tooltipDirty = true;
            SetTrayIcon();
            ShowTimedTooltip("Undeafened \u2014 audio restored", 3000);
        }
    }

    // ── Mode Switching ───────────────────────────────────────────────────

    private void SetMode(string newMode)
    {
        _config.Mode = newMode;
        if (newMode == "push-to-talk")
            SetMuteState(true, true);
        RegisterMainHotkey();
        BuildTrayMenu();
        _tooltipDirty = true;
        SetTrayIcon();
        _config.Save();

        if (_config.SoundFeedback)
            PlayModeChirp(newMode);

        string modeName = newMode == "push-to-talk" ? "Push-to-Talk" : "Toggle";
        ShowTimedTooltip("Mode: " + modeName, 3000);
    }

    // ── Tray Menu ────────────────────────────────────────────────────────

    private void BuildTrayMenu()
    {
        _trayMenu.Items.Clear();

        string hotkeyReadable = Config.HotkeyToReadable(_config.Hotkey);

        // Title / toggle
        var titleItem = new ToolStripMenuItem("Toggle Mute \u2014 v" + Config.Version);
        titleItem.Font = new Font(_trayMenu.Font, FontStyle.Bold);
        titleItem.Click += (_, _) => ToggleMute();
        _trayMenu.Items.Add(titleItem);
        _trayMenu.Items.Add(new ToolStripSeparator());

        // Hotkey
        var hotkeyItem = new ToolStripMenuItem("Hotkey: " + hotkeyReadable);
        hotkeyItem.Click += (_, _) => ShowHotkeyDialog();
        _trayMenu.Items.Add(hotkeyItem);

        // Mode submenu
        string modeLabel = "Mode: " + (_config.Mode == "push-to-talk" ? "Push-to-Talk" : "Toggle");
        var modeItem = new ToolStripMenuItem(modeLabel);
        var toggleModeItem = new ToolStripMenuItem("Toggle");
        toggleModeItem.Checked = _config.Mode == "toggle";
        toggleModeItem.Click += (_, _) => SetMode("toggle");
        var pttModeItem = new ToolStripMenuItem("Push-to-Talk");
        pttModeItem.Checked = _config.Mode == "push-to-talk";
        pttModeItem.Click += (_, _) => SetMode("push-to-talk");
        modeItem.DropDownItems.Add(toggleModeItem);
        modeItem.DropDownItems.Add(pttModeItem);
        _trayMenu.Items.Add(modeItem);

        // Device submenu (lazy-loaded)
        _deviceMenuItem = new ToolStripMenuItem("Mic Source");
        var loadingItem = new ToolStripMenuItem("Loading\u2026") { Enabled = false };
        _deviceMenuItem.DropDownItems.Add(loadingItem);
        _deviceMenuItem.DropDownOpening += OnDeviceMenuOpening;
        _deviceMenuPopulated = false;
        _trayMenu.Items.Add(_deviceMenuItem);

        _trayMenu.Items.Add(new ToolStripSeparator());

        // Settings
        var settingsItem = new ToolStripMenuItem("Settings\u2026");
        settingsItem.Click += (_, _) => ShowSettingsDialog();
        _trayMenu.Items.Add(settingsItem);

        _trayMenu.Items.Add(new ToolStripSeparator());

        // Reinit
        var reinitItem = new ToolStripMenuItem("Reinit Mic");
        reinitItem.Click += (_, _) => ReinitMic();
        _trayMenu.Items.Add(reinitItem);

        // Sound settings
        var soundItem = new ToolStripMenuItem("Sound Settings");
        soundItem.Click += (_, _) =>
        {
            using var proc = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "ms-settings:sound",
                UseShellExecute = true,
            });
        };
        _trayMenu.Items.Add(soundItem);

        _trayMenu.Items.Add(new ToolStripSeparator());

        // Exit
        var exitItem = new ToolStripMenuItem("Exit");
        exitItem.Click += (_, _) => ExitApplication();
        _trayMenu.Items.Add(exitItem);
    }

    private void OnDeviceMenuOpening(object sender, EventArgs e)
    {
        if (_deviceMenuPopulated)
            return;
        PopulateDeviceMenu();
    }

    private void PopulateDeviceMenu()
    {
        _deviceMenuItem.DropDownItems.Clear();

        var defaultItem = new ToolStripMenuItem("System Default");
        defaultItem.Checked = string.IsNullOrEmpty(_config.DeviceId);
        defaultItem.Click += (_, _) => SelectDevice("");
        _deviceMenuItem.DropDownItems.Add(defaultItem);
        _deviceMenuItem.DropDownItems.Add(new ToolStripSeparator());

        var devices = AudioManager.EnumerateCaptureDevices();
        foreach (var dev in devices)
        {
            string label = dev.Name.Length > 40 ? dev.Name[..37] + "\u2026" : dev.Name;
            var item = new ToolStripMenuItem(label);
            item.Checked = _config.DeviceId == dev.Id;
            string devId = dev.Id; // capture for closure
            item.Click += (_, _) => SelectDevice(devId);
            _deviceMenuItem.DropDownItems.Add(item);
        }

        _deviceMenuPopulated = true;
    }

    private void SelectDevice(string deviceId)
    {
        _config.DeviceId = deviceId;
        _audio.Release();
        if (_audio.Initialize(deviceId))
        {
            bool? m = _audio.GetMute();
            _muted = m ?? false;
        }
        else
        {
            _muted = false;
        }
        SyncTrayIcon();
        BuildTrayMenu();
        _config.Save();

        ShowTimedTooltip(string.IsNullOrEmpty(deviceId)
            ? "Using system default microphone."
            : "Switched microphone.", 3000);
    }

    // ── Reinitialize Mic ─────────────────────────────────────────────────

    private void ReinitMic()
    {
        _audio.Release();
        if (_audio.Initialize(_config.DeviceId))
        {
            bool? m = _audio.GetMute();
            _muted = m ?? false;
            SyncTrayIcon();
            ShowTimedTooltip("Microphone reinitialised.", 3000);
        }
        else
        {
            ShowTimedTooltip("No microphone found.", 5000);
        }
    }

    // ── Startup Mute Preference ──────────────────────────────────────────

    private void ApplyStartupMutePreference()
    {
        switch (_config.StartMuted)
        {
            case "yes" when !_muted:
                _audio.SetMute(true);
                _muted = true;
                break;
            case "unmuted" when _muted:
                _audio.SetMute(false);
                _muted = false;
                break;
            case "last":
                if (_config.LastMuteState != _muted)
                {
                    _audio.SetMute(_config.LastMuteState);
                    _muted = _config.LastMuteState;
                }
                break;
        }
    }

    // ── Dialogs ──────────────────────────────────────────────────────────

    private void ShowHotkeyDialog()
    {
        using var dlg = new HotkeyDialog(_config.Hotkey);
        if (dlg.ShowDialog() == DialogResult.OK && !string.IsNullOrEmpty(dlg.ResultHotkey))
        {
            _config.Hotkey = dlg.ResultHotkey;
            RegisterMainHotkey();
            BuildTrayMenu();
            _config.Save();
            ShowTimedTooltip("Hotkey changed to: " + Config.HotkeyToReadable(_config.Hotkey), 3000);
        }
    }

    private void ShowSettingsDialog()
    {
        if (_settingsDialog != null && !_settingsDialog.IsDisposed)
        {
            _settingsDialog.Show();
            _settingsDialog.BringToFront();
            return;
        }

        _settingsDialog = new SettingsDialog(_config, OnSettingsApplied);
        _settingsDialog.FormClosed += (_, _) => _settingsDialog = null;
        _settingsDialog.Show();
    }

    private void OnSettingsApplied()
    {
        // Reload icons if custom paths changed
        _iconActive?.Dispose();
        _iconMuted?.Dispose();
        LoadIcons();

        // Re-register hotkeys
        RegisterDeafenHotkey();

        // Refresh tray
        _tooltipDirty = true;
        BuildTrayMenu();
        SetTrayIcon();
    }

    // ── Tray Click Handling ──────────────────────────────────────────────

    private void OnTrayMouseClick(object sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            ToggleMute();
        }
        else if (e.Button == MouseButtons.Middle && _config.MiddleClickToggle)
        {
            SetMode(_config.Mode == "toggle" ? "push-to-talk" : "toggle");
        }
    }

    // ── Timed Notification ────────────────────────────────────────────────

    private void ShowTimedTooltip(string text, int durationMs)
    {
        // Reuse the OSD form for transient notifications (avoids BalloonTip toasts)
        _osdForm.ShowOsd(_muted, Math.Min(durationMs, 3000));
    }

    // ── Exit & Cleanup ───────────────────────────────────────────────────

    private void ExitApplication()
    {
        // Unmute on exit (F-10) + restore speakers if deafened (F-20)
        if (_deafened)
        {
            try { AudioManager.SetSpeakerMute(_speakerWasMuted); }
            catch { /* ignore */ }
        }

        if (_audio.HasEndpoint && _muted)
            _audio.SetMute(false);

        Application.Exit();
    }

    protected override void Dispose(bool disposing)
    {
        if (!_disposed && disposing)
        {
            // Unregister hotkeys
            UnregisterMainHotkey();
            UnregisterDeafenHotkey();

            // Stop and dispose timers
            _syncTimer.Stop();
            _syncTimer.Dispose();

            _flashTimer.Stop();
            _flashTimer.Dispose();

            if (_pttTimer != null)
            {
                _pttTimer.Stop();
                _pttTimer.Dispose();
                _pttTimer = null;
            }

            // Dispose OSD
            _osdForm.Dispose();

            // Dispose tray icon
            _trayIcon.Visible = false;
            _trayIcon.Dispose();

            // Dispose menu
            _trayMenu.Dispose();

            // Dispose icons
            _iconActive?.Dispose();
            _iconMuted?.Dispose();

            // Dispose audio
            _audio.Dispose();

            // Dispose dialogs
            _settingsDialog?.Dispose();

            _disposed = true;
        }

        base.Dispose(disposing);
    }
}
