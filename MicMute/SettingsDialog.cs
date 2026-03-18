namespace MicMute;

/// <summary>
/// Settings GUI matching the AHK version's layout and functionality.
/// </summary>
internal sealed class SettingsDialog : Form
{
    private readonly Config _config;
    private readonly Action _onApply;
    private readonly Font _dialogFont;
    private readonly List<Font> _sectionFonts = new();

    // Behavior
    private readonly CheckBox _chkSoundFeedback;
    private readonly CheckBox _chkOsd;
    private readonly TextBox _edtOsdDuration;
    private readonly CheckBox _chkMuteLock;
    private readonly CheckBox _chkMiddleClick;
    private readonly CheckBox _chkRunAtStartup;
    private readonly ComboBox _ddlStartMuted;

    // Hotkeys
    private readonly TextBox _edtDeafenHK;

    // Custom files
    private readonly TextBox _edtIconMuted;
    private readonly Label _lblIconMuted;
    private readonly TextBox _edtIconActive;
    private readonly Label _lblIconActive;
    private readonly TextBox _edtMuteSound;
    private readonly Label _lblMuteSound;
    private readonly TextBox _edtUnmuteSound;
    private readonly Label _lblUnmuteSound;

    public SettingsDialog(Config config, Action onApply)
    {
        _config = config;
        _onApply = onApply;

        Text = "MicMute v" + Config.Version + " \u2014 Settings";
        TopMost = true;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;
        _dialogFont = new Font("Segoe UI", 9f);
        Font = _dialogFont;
        AutoScaleMode = AutoScaleMode.Dpi;

        int y = 14;
        int leftMargin = 16;
        int indent = 28;

        // ── Behavior ──
        AddSectionHeader("Behavior", leftMargin, ref y);

        _chkSoundFeedback = AddCheckBox("Sound feedback on mute/unmute", indent, ref y, config.SoundFeedback);
        _chkOsd = AddCheckBox("On-screen display bubble on mute/unmute", indent, ref y, config.OsdEnabled);

        // OSD duration
        var durLabel = new Label { Text = "Duration (ms):", AutoSize = true, ForeColor = Color.FromArgb(0x88, 0x88, 0x88), Location = new Point(48, y + 2) };
        Controls.Add(durLabel);
        _edtOsdDuration = new TextBox { Text = config.OsdDuration.ToString(), Width = 55, Location = new Point(durLabel.Right + 6, y - 1) };
        Controls.Add(_edtOsdDuration);
        y += 28;

        _chkMuteLock = AddCheckBox("Mute Lock (prevent external apps from changing mute state)", indent, ref y, config.MuteLock);
        _chkMiddleClick = AddCheckBox("Middle-click tray icon to toggle Toggle/PTT mode", indent, ref y, config.MiddleClickToggle);

        string startupPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Startup), "MicMute.lnk");
        _chkRunAtStartup = AddCheckBox("Run at startup", indent, ref y, File.Exists(startupPath));

        // On startup dropdown
        var startLabel = new Label { Text = "On startup:", AutoSize = true, Location = new Point(indent, y + 2) };
        Controls.Add(startLabel);
        _ddlStartMuted = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 130,
            Location = new Point(startLabel.Right + 8, y - 1),
        };
        _ddlStartMuted.Items.AddRange(new[] { "Don't change", "Always muted", "Always unmuted", "Remember last" });
        _ddlStartMuted.SelectedIndex = config.StartMuted switch
        {
            "yes" => 1,
            "unmuted" => 2,
            "last" => 3,
            _ => 0,
        };
        Controls.Add(_ddlStartMuted);
        y += 30;

        // ── Hotkeys ──
        AddSectionHeader("Hotkeys", leftMargin, ref y);

        var deafenLabel = new Label { Text = "Global deafen hotkey:", AutoSize = true, Location = new Point(indent, y + 2) };
        Controls.Add(deafenLabel);
        _edtDeafenHK = new TextBox
        {
            Text = config.DeafenHotkey,
            Width = 130,
            Location = new Point(deafenLabel.Right + 8, y - 1),
        };
        Controls.Add(_edtDeafenHK);
        var hkHintLabel = new Label
        {
            Text = "AHK syntax: # = Win, ^ = Ctrl, ! = Alt, + = Shift",
            AutoSize = true,
            ForeColor = Color.FromArgb(0x88, 0x88, 0x88),
            Location = new Point(indent, y + 22),
        };
        Controls.Add(hkHintLabel);
        y += 48;

        // ── Custom Files ──
        AddSectionHeader("Custom Files", leftMargin, ref y);

        (_edtIconMuted, _lblIconMuted) = AddFileRow("Muted icon:", config.IconMuted, "Icon files (*.ico)|*.ico", indent, ref y);
        (_edtIconActive, _lblIconActive) = AddFileRow("Active icon:", config.IconActive, "Icon files (*.ico)|*.ico", indent, ref y);
        (_edtMuteSound, _lblMuteSound) = AddFileRow("Mute sound:", config.MuteSound, "Sound files (*.wav)|*.wav", indent, ref y);
        (_edtUnmuteSound, _lblUnmuteSound) = AddFileRow("Unmute sound:", config.UnmuteSound, "Sound files (*.wav)|*.wav", indent, ref y);

        // ── Buttons ──
        y += 8;
        var btnGitHub = new Button { Text = "GitHub", Width = 80, Location = new Point(leftMargin, y) };
        btnGitHub.Click += (_, _) =>
        {
            using var proc = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "https://github.com/itsnateai/MicMute",
                UseShellExecute = true,
            });
        };
        Controls.Add(btnGitHub);

        var btnHelp = new Button { Text = "Help", Width = 55, Location = new Point(btnGitHub.Right + 6, y) };
        btnHelp.Click += (_, _) => HelpWindow.ShowInstance();
        Controls.Add(btnHelp);

        var btnOK = new Button { Text = "OK", Width = 80, Location = new Point(170, y) };
        btnOK.Click += (_, _) => { ApplySettings(); Close(); };
        Controls.Add(btnOK);

        var btnApply = new Button { Text = "Apply", Width = 80, Location = new Point(258, y) };
        btnApply.Click += (_, _) => ApplySettings();
        Controls.Add(btnApply);

        var btnCancel = new Button { Text = "Cancel", Width = 80, Location = new Point(346, y) };
        btnCancel.Click += (_, _) => Close();
        Controls.Add(btnCancel);
        CancelButton = btnCancel;

        ClientSize = new Size(440, y + 38);
    }

    private void ApplySettings()
    {
        _config.SoundFeedback = _chkSoundFeedback.Checked;
        _config.OsdEnabled = _chkOsd.Checked;
        if (int.TryParse(_edtOsdDuration.Text, out int dur))
            _config.OsdDuration = Math.Max(500, dur);
        _config.MuteLock = _chkMuteLock.Checked;
        _config.MiddleClickToggle = _chkMiddleClick.Checked;

        _config.StartMuted = _ddlStartMuted.SelectedIndex switch
        {
            1 => "yes",
            2 => "unmuted",
            3 => "last",
            _ => "no",
        };

        // Startup shortcut
        string startupPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Startup), "MicMute.lnk");
        if (_chkRunAtStartup.Checked && !File.Exists(startupPath))
            ShortcutHelper.CreateShortcut(startupPath, Environment.ProcessPath ?? "");
        else if (!_chkRunAtStartup.Checked && File.Exists(startupPath))
            try { File.Delete(startupPath); } catch { /* ignore */ }

        // Deafen hotkey
        _config.DeafenHotkey = _edtDeafenHK.Text.Trim();

        // Custom files
        _config.IconMuted = _edtIconMuted.Text.Trim();
        _config.IconActive = _edtIconActive.Text.Trim();
        _config.MuteSound = _edtMuteSound.Text.Trim();
        _config.UnmuteSound = _edtUnmuteSound.Text.Trim();

        _config.Save();
        _onApply();
    }

    private void AddSectionHeader(string text, int x, ref int y)
    {
        var boldFont = new Font("Segoe UI", 9f, FontStyle.Bold);
        _sectionFonts.Add(boldFont);
        var label = new Label
        {
            Text = text,
            Font = boldFont,
            ForeColor = Color.FromArgb(0x44, 0x44, 0x44),
            AutoSize = true,
            Location = new Point(x, y),
        };
        Controls.Add(label);
        y += label.Height + 3;

        // Separator line
        var sep = new Label
        {
            BorderStyle = BorderStyle.Fixed3D,
            Height = 1,
            Width = 410,
            Location = new Point(x, y),
        };
        Controls.Add(sep);
        y += 8;
    }

    private CheckBox AddCheckBox(string text, int x, ref int y, bool isChecked)
    {
        var chk = new CheckBox
        {
            Text = text,
            AutoSize = true,
            Checked = isChecked,
            Location = new Point(x, y),
        };
        Controls.Add(chk);
        y += chk.Height + 4;
        return chk;
    }

    private (TextBox edit, Label lbl) AddFileRow(string labelText, string currentPath, string filter, int x, ref int y)
    {
        var lbl = new Label { Text = labelText, Width = 75, AutoSize = false, Location = new Point(x, y + 4) };
        Controls.Add(lbl);

        var edit = new TextBox { Text = currentPath, Visible = false, Width = 0, Location = new Point(0, 0) };
        Controls.Add(edit);

        var btnBrowse = new Button { Text = "Browse\u2026", Width = 65, Location = new Point(106, y) };
        Controls.Add(btnBrowse);

        var btnClear = new Button { Text = "Clear", Width = 45, Location = new Point(btnBrowse.Right + 3, y) };
        Controls.Add(btnClear);

        var fileLbl = new Label
        {
            Text = FileLabel(currentPath),
            ForeColor = Color.FromArgb(0x55, 0x55, 0x55),
            AutoSize = true,
            Location = new Point(btnClear.Right + 6, y + 4),
        };
        Controls.Add(fileLbl);

        btnBrowse.Click += (_, _) =>
        {
            using var ofd = new OpenFileDialog { Filter = filter };
            if (ofd.ShowDialog() == DialogResult.OK)
            {
                edit.Text = ofd.FileName;
                fileLbl.Text = FileLabel(ofd.FileName);
            }
        };

        btnClear.Click += (_, _) =>
        {
            edit.Text = "";
            fileLbl.Text = "(none)";
        };

        y += 30;
        return (edit, fileLbl);
    }

    private static string FileLabel(string path)
    {
        if (string.IsNullOrEmpty(path))
            return "(none)";
        return Path.GetFileName(path);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _dialogFont?.Dispose();
            foreach (var f in _sectionFonts)
                f.Dispose();
            _sectionFonts.Clear();
        }
        base.Dispose(disposing);
    }
}
