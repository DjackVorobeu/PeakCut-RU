using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Threading;

static class Launcher
{
    const int Port = 8765;

    static string Root;

    static bool IsUp()
    {
        try
        {
            using (TcpClient client = new TcpClient())
            {
                IAsyncResult ar = client.BeginConnect("127.0.0.1", Port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(500)) return false;
                client.EndConnect(ar);
                return true;
            }
        }
        catch
        {
            return false;
        }
    }

    static void Log(string text)
    {
        try
        {
            File.AppendAllText(Path.Combine(Root, "data", "launcher.log"),
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + text + Environment.NewLine);
        }
        catch
        {
        }
    }

    static void Main()
    {
        Root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        string data = Path.Combine(Root, "data");
        Directory.CreateDirectory(data);

        if (!IsUp())
        {
            string python = Path.Combine(Root, ".venv\\Scripts\\python.exe");
            string log = Path.Combine(data, "server.log");
            if (!File.Exists(python))
            {
                Log("python not found: " + python);
                Process.Start("notepad.exe", log);
                return;
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "cmd.exe";
            psi.Arguments = "/c \"\"" + python + "\" -m studio.server >> \"" + log + "\" 2>&1\"";
            psi.WorkingDirectory = Root;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.EnvironmentVariables["PATH"] = Path.Combine(Root, "bin") + ";" + Environment.GetEnvironmentVariable("PATH");
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";

            try
            {
                Process.Start(psi);
                Log("server starting");
            }
            catch (Exception ex)
            {
                Log("start failed: " + ex.Message);
            }

            for (int i = 0; i < 240; i++)
            {
                Thread.Sleep(500);
                if (IsUp()) break;
            }
        }

        if (IsUp())
        {
            Process.Start("http://127.0.0.1:" + Port + "/");
            Log("browser opened");
        }
        else
        {
            Log("server did not come up, opening the log");
            Process.Start("notepad.exe", Path.Combine(data, "server.log"));
        }
    }
}
