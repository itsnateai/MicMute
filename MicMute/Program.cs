using System.Diagnostics;

namespace MicMute;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        // Single-instance enforcement: kill previous instances
        string processName = Path.GetFileNameWithoutExtension(Environment.ProcessPath ?? "MicMute");
        foreach (var p in Process.GetProcessesByName(processName))
        {
            using (p)
            {
                if (p.Id != Environment.ProcessId)
                {
                    try { p.Kill(); } catch { /* already exiting */ }
                }
            }
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new TrayApp());
    }
}
