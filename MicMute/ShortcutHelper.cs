using System.Runtime.InteropServices;

namespace MicMute;

/// <summary>
/// Creates Windows .lnk shortcuts using WScript.Shell COM interop.
/// </summary>
internal static class ShortcutHelper
{
    public static void CreateShortcut(string shortcutPath, string targetPath)
    {
        try
        {
            var shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null)
                return;

            object shell = Activator.CreateInstance(shellType)!;
            try
            {
                object shortcut = shellType.InvokeMember("CreateShortcut",
                    System.Reflection.BindingFlags.InvokeMethod, null, shell,
                    new object[] { shortcutPath })!;

                var scType = shortcut.GetType();
                scType.InvokeMember("TargetPath",
                    System.Reflection.BindingFlags.SetProperty, null, shortcut,
                    new object[] { targetPath });
                scType.InvokeMember("WorkingDirectory",
                    System.Reflection.BindingFlags.SetProperty, null, shortcut,
                    new object[] { Path.GetDirectoryName(targetPath) ?? "" });
                scType.InvokeMember("Description",
                    System.Reflection.BindingFlags.SetProperty, null, shortcut,
                    new object[] { "MicMute \u2014 Global mic mute toggle" });
                scType.InvokeMember("IconLocation",
                    System.Reflection.BindingFlags.SetProperty, null, shortcut,
                    new object[] { targetPath + ",0" });
                scType.InvokeMember("Save",
                    System.Reflection.BindingFlags.InvokeMethod, null, shortcut, null);

                Marshal.ReleaseComObject(shortcut);
            }
            finally
            {
                Marshal.ReleaseComObject(shell);
            }
        }
        catch
        {
            // Shortcut creation is best-effort
        }
    }
}
