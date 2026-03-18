namespace MicMute;

/// <summary>
/// Dialog for changing the global mute hotkey at runtime.
/// Supports both standard key combos and raw AHK syntax for Win key combos.
/// </summary>
internal sealed class HotkeyDialog : Form
{
    private readonly TextBox _rawTextBox;
    private readonly Label _currentLabel;

    public string ResultHotkey { get; private set; } = "";

    public HotkeyDialog(string currentHotkey)
    {
        Text = "MicMute \u2014 Change Hotkey";
        TopMost = true;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10f);
        ClientSize = new Size(320, 160);

        var label = new Label
        {
            Text = "Type AHK syntax (e.g. #+a for Win+Shift+A):",
            AutoSize = true,
            Location = new Point(16, 16),
        };
        Controls.Add(label);

        _rawTextBox = new TextBox
        {
            Location = new Point(16, 44),
            Width = 250,
        };
        Controls.Add(_rawTextBox);

        _currentLabel = new Label
        {
            Text = "Current: " + Config.HotkeyToReadable(currentHotkey),
            ForeColor = Color.Gray,
            AutoSize = true,
            Location = new Point(16, 76),
        };
        Controls.Add(_currentLabel);

        var btnOK = new Button
        {
            Text = "OK",
            Width = 80,
            Location = new Point(80, 110),
            DialogResult = DialogResult.OK,
        };
        btnOK.Click += (_, _) =>
        {
            string raw = _rawTextBox.Text.Trim();
            if (!string.IsNullOrEmpty(raw))
                ResultHotkey = raw;
        };
        Controls.Add(btnOK);
        AcceptButton = btnOK;

        var btnCancel = new Button
        {
            Text = "Cancel",
            Width = 80,
            Location = new Point(170, 110),
            DialogResult = DialogResult.Cancel,
        };
        Controls.Add(btnCancel);
        CancelButton = btnCancel;
    }
}
