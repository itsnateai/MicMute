using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace MicMute;

/// <summary>
/// Reads and writes MicMute.ini configuration using the Windows INI API.
/// </summary>
internal sealed class Config
{
    public const string Version = "1.8.3";

    // Settings with defaults
    public string Hotkey = "#+a";
    public bool SoundFeedback = true;
    public string Mode = "toggle"; // "toggle" or "push-to-talk"
    public string DeviceId = "";
    public string IconMuted = "";
    public string IconActive = "";
    public string MuteSound = "";
    public string UnmuteSound = "";
    public bool MuteLock;
    public bool OsdEnabled;
    public int OsdDuration = 1500;
    public string DeafenHotkey = "";
    public bool MiddleClickToggle = true;
    public string StartMuted = "no"; // "no", "yes", "unmuted", "last"
    public bool LastMuteState;

    private readonly string _iniPath;

    // Pre-compiled regex for hotkey parsing
    // s_modifierPrefix captures recognized modifier symbols for parsing
    // s_stripModifiers strips ALL AHK prefix symbols including ~*$ (passthrough/wildcard/hook)
    private static readonly Regex s_modifierPrefix = new(@"^[<>#^!+~*$]+", RegexOptions.Compiled);
    private static readonly Regex s_stripModifiers = new(@"^[<>#^!+~*$]+", RegexOptions.Compiled);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern uint GetPrivateProfileString(
        string lpAppName, string lpKeyName, string lpDefault,
        StringBuilder lpReturnedString, uint nSize, string lpFileName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WritePrivateProfileString(
        string lpAppName, string lpKeyName, string lpString, string lpFileName);

    public Config()
    {
        string dir = Path.GetDirectoryName(Environment.ProcessPath ?? "")
            ?? AppDomain.CurrentDomain.BaseDirectory;
        if (string.IsNullOrEmpty(dir))
            dir = AppDomain.CurrentDomain.BaseDirectory;
        _iniPath = Path.Combine(dir, "MicMute.ini");
    }

    public void Load()
    {
        if (!File.Exists(_iniPath))
            return;

        FixEncoding();

        Hotkey = ReadIni("Hotkey", Hotkey);
        SoundFeedback = ReadIni("SoundFeedback", "1") == "1";
        Mode = ReadIni("Mode", Mode).Trim();
        if (Mode != "toggle" && Mode != "push-to-talk")
            Mode = "toggle";
        DeviceId = ReadIni("DeviceId", "").Trim();
        IconMuted = ReadIni("IconMuted", "").Trim();
        IconActive = ReadIni("IconActive", "").Trim();
        MuteSound = ReadIni("MuteSound", "").Trim();
        UnmuteSound = ReadIni("UnmuteSound", "").Trim();
        MuteLock = ReadIni("MuteLock", "0") == "1";
        OsdEnabled = ReadIni("OSD_Enabled", "0") == "1";
        if (int.TryParse(ReadIni("OSD_Duration", "1500"), out int dur))
            OsdDuration = Math.Max(500, dur);
        DeafenHotkey = ReadIni("DeafenHotkey", "").Trim();
        MiddleClickToggle = ReadIni("MiddleClickToggle", "1") == "1";
        StartMuted = ReadIni("StartMuted", "no").Trim().ToLowerInvariant();
        if (StartMuted != "no" && StartMuted != "yes" && StartMuted != "unmuted" && StartMuted != "last")
            StartMuted = "no";
        LastMuteState = ReadIni("LastMuteState", "0") == "1";
    }

    public void Save()
    {
        WriteIni("Hotkey", Hotkey);
        WriteIni("SoundFeedback", SoundFeedback ? "1" : "0");
        WriteIni("Mode", Mode);
        WriteIni("DeviceId", DeviceId);
        WriteIni("IconMuted", IconMuted);
        WriteIni("IconActive", IconActive);
        WriteIni("MuteSound", MuteSound);
        WriteIni("UnmuteSound", UnmuteSound);
        WriteIni("MuteLock", MuteLock ? "1" : "0");
        WriteIni("OSD_Enabled", OsdEnabled ? "1" : "0");
        WriteIni("OSD_Duration", OsdDuration.ToString());
        WriteIni("DeafenHotkey", DeafenHotkey);
        WriteIni("MiddleClickToggle", MiddleClickToggle ? "1" : "0");
        WriteIni("StartMuted", StartMuted);
    }

    public void SaveLastMuteState(bool muted)
    {
        if (StartMuted != "last")
            return;
        LastMuteState = muted;
        WriteIni("LastMuteState", muted ? "1" : "0");
    }

    /// <summary>
    /// Converts AHK hotkey string to human-readable form.
    /// e.g. "#+a" → "Win + Shift + A"
    /// </summary>
    public static string HotkeyToReadable(string hk)
    {
        if (string.IsNullOrEmpty(hk))
            return "(none)";

        var prefixMatch = s_modifierPrefix.Match(hk);
        string prefix = prefixMatch.Success ? prefixMatch.Value : "";
        string key = s_modifierPrefix.Replace(hk, "");

        string side = prefix.Contains('<') ? "L" : prefix.Contains('>') ? "R" : "";
        var sb = new StringBuilder();
        if (prefix.Contains('#')) sb.Append(side).Append("Win + ");
        if (prefix.Contains('^')) sb.Append(side).Append("Ctrl + ");
        if (prefix.Contains('!')) sb.Append(side).Append("Alt + ");
        if (prefix.Contains('+')) sb.Append(side).Append("Shift + ");
        sb.Append(key.ToUpperInvariant());
        return sb.ToString();
    }

    /// <summary>
    /// Extracts the key name from an AHK hotkey string (strips modifier symbols).
    /// </summary>
    public static string ExtractKeyName(string hk)
    {
        return s_stripModifiers.Replace(hk, "");
    }

    /// <summary>
    /// Parses AHK modifier symbols into Win32 modifier flags + virtual key code.
    /// Returns false if the key cannot be mapped.
    /// </summary>
    public static bool ParseHotkey(string hk, out uint modifiers, out uint vk)
    {
        modifiers = 0;
        vk = 0;

        if (string.IsNullOrEmpty(hk))
            return false;

        var prefixMatch = s_modifierPrefix.Match(hk);
        string prefix = prefixMatch.Success ? prefixMatch.Value : "";
        string keyName = s_modifierPrefix.Replace(hk, "");

        if (prefix.Contains('#')) modifiers |= NativeMethods.MOD_WIN;
        if (prefix.Contains('^')) modifiers |= NativeMethods.MOD_CONTROL;
        if (prefix.Contains('!')) modifiers |= NativeMethods.MOD_ALT;
        if (prefix.Contains('+')) modifiers |= NativeMethods.MOD_SHIFT;
        modifiers |= NativeMethods.MOD_NOREPEAT;

        vk = KeyNameToVk(keyName);
        return vk != 0;
    }

    private static uint KeyNameToVk(string keyName)
    {
        if (string.IsNullOrEmpty(keyName))
            return 0;

        // Single character: A-Z, 0-9
        if (keyName.Length == 1)
        {
            char c = char.ToUpperInvariant(keyName[0]);
            if (c is >= 'A' and <= 'Z')
                return (uint)c;
            if (c is >= '0' and <= '9')
                return (uint)c;
        }

        // Function keys F1-F24
        if (keyName.StartsWith('F') && int.TryParse(keyName.AsSpan(1), out int fNum) && fNum is >= 1 and <= 24)
            return (uint)(0x6F + fNum); // VK_F1=0x70

        // Named keys
        return keyName.ToUpperInvariant() switch
        {
            "SPACE" => 0x20,
            "ENTER" or "RETURN" => 0x0D,
            "TAB" => 0x09,
            "ESCAPE" or "ESC" => 0x1B,
            "BACKSPACE" or "BS" => 0x08,
            "DELETE" or "DEL" => 0x2E,
            "INSERT" or "INS" => 0x2D,
            "HOME" => 0x24,
            "END" => 0x23,
            "PGUP" or "PAGEUP" => 0x21,
            "PGDN" or "PAGEDOWN" => 0x22,
            "UP" => 0x26,
            "DOWN" => 0x28,
            "LEFT" => 0x25,
            "RIGHT" => 0x27,
            "CAPSLOCK" => 0x14,
            "NUMLOCK" => 0x90,
            "SCROLLLOCK" => 0x91,
            "PRINTSCREEN" => 0x2C,
            "PAUSE" => 0x13,
            "NUMPAD0" => 0x60,
            "NUMPAD1" => 0x61,
            "NUMPAD2" => 0x62,
            "NUMPAD3" => 0x63,
            "NUMPAD4" => 0x64,
            "NUMPAD5" => 0x65,
            "NUMPAD6" => 0x66,
            "NUMPAD7" => 0x67,
            "NUMPAD8" => 0x68,
            "NUMPAD9" => 0x69,
            "NUMPADADD" or "NUMPAD+" => 0x6B,
            "NUMPADSUB" or "NUMPAD-" => 0x6D,
            "NUMPADMULT" or "NUMPAD*" => 0x6A,
            "NUMPADDIV" or "NUMPAD/" => 0x6F,
            "NUMPADDOT" or "NUMPAD." => 0x6E,
            "NUMPADENTER" => 0x0D, // same VK, distinguishable by extended flag
            _ => 0,
        };
    }

    private string ReadIni(string key, string defaultValue)
    {
        var sb = new StringBuilder(512);
        GetPrivateProfileString("General", key, defaultValue, sb, 512, _iniPath);
        return sb.ToString().Trim();
    }

    private void WriteIni(string key, string value)
    {
        WritePrivateProfileString("General", key, value, _iniPath);
    }

    /// <summary>
    /// Fix UTF-16 LE without BOM encoding issue (mirrors AHK FixIniEncoding).
    /// </summary>
    private void FixEncoding()
    {
        try
        {
            byte[] bytes = File.ReadAllBytes(_iniPath);
            if (bytes.Length < 4)
                return;
            // Check for UTF-16 LE BOM or plain ANSI
            if ((bytes[0] == 0xFF && bytes[1] == 0xFE) || bytes[1] != 0x00)
                return;
            // UTF-16 LE without BOM — re-encode to UTF-8
            string content = Encoding.Unicode.GetString(bytes);
            File.WriteAllText(_iniPath, content, new UTF8Encoding(false));
        }
        catch
        {
            // Ignore encoding fix failures
        }
    }
}
