namespace MicMute;

/// <summary>
/// Borderless, always-on-top, click-through OSD overlay that shows mute state
/// or arbitrary notification text. Positioned above the taskbar, auto-dismisses.
/// </summary>
internal sealed class OsdForm : Form
{
    private readonly System.Windows.Forms.Timer _dismissTimer;
    private bool _disposed;

    // Cached brushes and font — created once, reused across the app lifetime
    private static readonly Font s_dotFont = new("Segoe UI", 10f);
    private static readonly Font s_labelFont = new("Segoe UI Semibold", 9f);
    private static readonly SolidBrush s_bgBrush = new(Color.FromArgb(0x1E, 0x1E, 0x1E));
    private static readonly SolidBrush s_textBrush = new(Color.FromArgb(0xE0, 0xE0, 0xE0));
    private static readonly SolidBrush s_mutedDotBrush = new(Color.FromArgb(0xE0, 0x40, 0x40));
    private static readonly SolidBrush s_activeDotBrush = new(Color.FromArgb(0x2E, 0xCC, 0x71));

    // Cached display strings for mute state
    private static readonly string s_mutedLabel = "Mic Muted";
    private static readonly string s_activeLabel = "Mic Active";
    private const string DotChar = "\u25CF"; // ●

    private bool _showMuted;
    private string _customText;

    public OsdForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.FromArgb(0x1E, 0x1E, 0x1E);
        SetStyle(ControlStyles.SupportsTransparentBackColor, true);

        _dismissTimer = new System.Windows.Forms.Timer();
        _dismissTimer.Tick += (_, _) =>
        {
            _dismissTimer.Stop();
            Hide();
        };
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW — no taskbar entry
            cp.ExStyle |= 0x00000020; // WS_EX_TRANSPARENT — click-through
            cp.ExStyle |= 0x00000008; // WS_EX_TOPMOST
            return cp;
        }
    }

    protected override bool ShowWithoutActivation => true;

    /// <summary>
    /// Show the OSD with standard mute/active state display.
    /// </summary>
    public void ShowOsd(bool muted, int durationMs)
    {
        _showMuted = muted;
        _customText = null;
        ShowInternal(muted ? s_mutedLabel : s_activeLabel, durationMs);
    }

    /// <summary>
    /// Show the OSD with custom notification text.
    /// </summary>
    public void ShowNotification(string text, bool isMuted, int durationMs)
    {
        _showMuted = isMuted;
        _customText = text;
        ShowInternal(text, durationMs);
    }

    private void ShowInternal(string displayText, int durationMs)
    {
        // Measure text
        using var g = CreateGraphics();
        var labelSize = g.MeasureString(displayText, s_labelFont);
        int w = 12 + 14 + (int)labelSize.Width + 16;
        int h = 32;

        // Position above taskbar
        var screen = Screen.PrimaryScreen ?? Screen.AllScreens[0];
        int xPos = screen.WorkingArea.Right - w - 12;
        int yPos = screen.WorkingArea.Bottom - h - 8;

        // Try to find taskbar for more precise positioning
        nint trayHwnd = NativeMethods.FindWindow("Shell_TrayWnd", "");
        if (trayHwnd != 0)
        {
            if (NativeMethods.GetWindowRect(trayHwnd, out var rect))
            {
                xPos = rect.Right - w - 12;
                yPos = rect.Top - h - 8;
            }
        }

        SetBounds(xPos, yPos, w, h);

        // Try Win11 rounded corners
        try
        {
            int preference = NativeMethods.DWMWCP_ROUND;
            NativeMethods.DwmSetWindowAttribute(Handle,
                NativeMethods.DWMWA_WINDOW_CORNER_PREFERENCE, ref preference, sizeof(int));
        }
        catch
        {
            // Older Windows — ignore
        }

        Opacity = 235.0 / 255.0;
        Invalidate();

        if (!Visible)
            Show();

        _dismissTimer.Stop();
        _dismissTimer.Interval = durationMs;
        _dismissTimer.Start();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.FillRectangle(s_bgBrush, ClientRectangle);

        var dotBrush = _showMuted ? s_mutedDotBrush : s_activeDotBrush;
        g.DrawString(DotChar, s_dotFont, dotBrush, 12, 6);

        string label = _customText ?? (_showMuted ? s_mutedLabel : s_activeLabel);
        g.DrawString(label, s_labelFont, s_textBrush, 28, 6);
    }

    protected override void Dispose(bool disposing)
    {
        if (!_disposed && disposing)
        {
            _dismissTimer.Stop();
            _dismissTimer.Dispose();
            _disposed = true;
        }
        base.Dispose(disposing);
    }
}
