namespace MicMute;

/// <summary>
/// Singleton resizable help window displaying usage instructions.
/// </summary>
internal sealed class HelpWindow : Form
{
    private static HelpWindow s_instance = null!;
    private readonly TextBox _textBox;
    private readonly Font _windowFont;

    private static readonly string s_helpText = @"MICMUTE — Global Microphone Mute Toggle

MicMute lets you mute and unmute your microphone system-wide using a hotkey or the tray icon. It works at the Windows audio level, so it affects all apps at once — Zoom, Discord, Teams, etc.

Green tray icon = mic is active (unmuted)
Red tray icon = mic is muted

——— BASIC USAGE ———————————————————

• Left-click the tray icon to toggle mute.
• Press your hotkey (default: Win+Shift+A) to toggle from anywhere.
• Right-click the tray icon for the full menu (change mode, pick a mic, open settings, etc.).
• Change your hotkey anytime via Tray → ""Hotkey: ..."" in the menu.

——— MODES ————————————————————————

Toggle (default): Press the hotkey once to mute, press again to unmute.

Push-to-Talk: Hold the hotkey to unmute. Releasing it mutes you again. Useful for noisy environments where you only want to be heard while actively speaking.

Switch modes via the tray menu (Mode → Toggle / Push-to-Talk), or enable ""Middle-click tray icon to toggle"" in Settings to quickly swap between them.

——— DEAFEN MODE ———————————————————

Deafen mutes both your microphone AND your speakers at the same time. Useful for stepping away or silencing everything quickly. Assign a hotkey in Settings under the Hotkeys section. Press again to undeafen (restores both to their previous state).

——— SETTINGS —————————————————————

Sound feedback: Plays a short tone when you mute or unmute.

On-screen display (OSD): Shows a small dark floating bubble above the taskbar when you toggle mute. The Duration setting controls how long it stays visible (minimum 500 ms).

Mute Lock: Prevents other applications from silently unmuting or muting your mic.

Middle-click toggle: When enabled, middle-clicking the tray icon swaps between Toggle and Push-to-Talk mode.

Run at startup: Creates a Windows startup shortcut so MicMute launches automatically when you log in.

On startup: Controls what happens to your mic when MicMute starts:
  • Don't change — leaves your mic however it was.
  • Always muted — forces mic muted on launch.
  • Always unmuted — forces mic unmuted on launch.
  • Remember last — restores the mute state from your last session.

——— HOTKEYS —————————————————————

Your main mute/unmute hotkey is set via the tray menu (right-click → ""Hotkey: ...""). The Settings window has a separate field for the Deafen hotkey.

Both support Windows key combinations (like Win+Shift+D). Use AHK syntax:
  # = Win,  ^ = Ctrl,  ! = Alt,  + = Shift
  Example: #+d means Win+Shift+D

——— CUSTOM FILES ——————————————————

Muted icon / Active icon: Replace the default red/green tray icons with your own .ico files.

Mute sound / Unmute sound: Replace the default beep tones with your own .wav files for audio feedback.

Use Browse to pick a file, or Clear to revert to the defaults.

——— MIC SOURCE ———————————————————

Right-click the tray icon → ""Mic Source"" to choose which microphone MicMute controls. By default it uses your Windows system default. If you switch mics or plug in a new one, MicMute auto-detects the change and reconnects.";

    private HelpWindow()
    {
        Text = "MicMute v" + Config.Version + " \u2014 Help";
        TopMost = true;
        BackColor = Color.White;
        _windowFont = new Font("Segoe UI", 9f);
        Font = _windowFont;
        ClientSize = new Size(460, 420);
        MinimumSize = new Size(400, 300);

        _textBox = new TextBox
        {
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Vertical,
            BorderStyle = BorderStyle.None,
            Text = s_helpText,
            Location = new Point(10, 10),
            Size = new Size(440, 400),
        };
        Controls.Add(_textBox);

        Resize += (_, _) =>
        {
            _textBox.Size = new Size(ClientSize.Width - 20, ClientSize.Height - 20);
        };

        FormClosed += (_, _) => s_instance = null!;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            _windowFont?.Dispose();
        base.Dispose(disposing);
    }

    public static void ShowInstance()
    {
        if (s_instance != null && !s_instance.IsDisposed)
        {
            s_instance.Show();
            s_instance.BringToFront();
            return;
        }
        s_instance = new HelpWindow();
        s_instance.Show();
    }
}
