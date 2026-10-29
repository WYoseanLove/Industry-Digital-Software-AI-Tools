using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace TxAi.Addin
{
    /// <summary>
    /// Crash forensics for the AI bridge. Every line is flushed to disk immediately, so the last
    /// lines survive a hard process kill. Log: %LOCALAPPDATA%\TxAi\logs\bridge-yyyyMMdd.log.
    /// Records: request begin/end (method, skill, thread, memory, GDI/USER handles), a heartbeat every
    /// few seconds while a request is running (a frozen heartbeat = UI thread blocked, a vanished
    /// heartbeat = process died), and managed unhandled exceptions.
    /// </summary>
    public static class CrashLog
    {
        [DllImport("user32.dll")]
        private static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);

        private static readonly object Sync = new object();
        private static string _path;
        private static Timer _heartbeat;
        private static string _current = "";
        private static long _currentStartTicks;
        private static bool _hooked;

        public static string LogPath
        {
            get { return _path; }
        }

        public static void Init(int heartbeatMs)
        {
            lock (Sync)
            {
                if (_hooked)
                {
                    return;
                }
                _hooked = true;
                try
                {
                    string dir = System.IO.Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TxAi", "logs");
                    Directory.CreateDirectory(dir);
                    _path = System.IO.Path.Combine(dir, "bridge-" + DateTime.Now.ToString("yyyyMMdd") + ".log");
                }
                catch (Exception)
                {
                    _path = null;
                }
            }

            AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs e)
            {
                Write("FATAL unhandled (terminating=" + e.IsTerminating + "): " + e.ExceptionObject);
            };
            AppDomain.CurrentDomain.ProcessExit += delegate { Write("ProcessExit"); };
            TaskSchedulerHook();

            Write("=== bridge log start pid=" + Process.GetCurrentProcess().Id + " " + Snapshot());
            _heartbeat = new Timer(delegate { Beat(); }, null, heartbeatMs, heartbeatMs);
        }

        private static void TaskSchedulerHook()
        {
            System.Threading.Tasks.TaskScheduler.UnobservedTaskException += delegate(object s, System.Threading.Tasks.UnobservedTaskExceptionEventArgs e)
            {
                Write("UnobservedTaskException: " + e.Exception);
            };
        }

        /// <summary>Marks the start of a request; the matching End must be called in a finally block.</summary>
        public static void Begin(string what)
        {
            _current = what;
            _currentStartTicks = Stopwatch.GetTimestamp();
            Write("BEGIN " + what + " " + Snapshot());
        }

        public static void End(string what, bool ok, string error)
        {
            Write("END   " + what + " ok=" + ok + (string.IsNullOrEmpty(error) ? "" : " error=" + Truncate(error, 400)) + " " + Snapshot());
            _current = "";
        }

        public static void Write(string message)
        {
            if (_path == null)
            {
                return;
            }
            try
            {
                string line = DateTime.Now.ToString("HH:mm:ss.fff") + " [t" + Thread.CurrentThread.ManagedThreadId + "] " + message + Environment.NewLine;
                lock (Sync)
                {
                    using (FileStream fs = new FileStream(_path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
                    {
                        byte[] bytes = new UTF8Encoding(false).GetBytes(line);
                        fs.Write(bytes, 0, bytes.Length);
                        fs.Flush(true);
                    }
                }
            }
            catch (Exception)
            {
            }
        }

        private static void Beat()
        {
            string current = _current;
            if (string.IsNullOrEmpty(current))
            {
                return;
            }
            double sec = (Stopwatch.GetTimestamp() - _currentStartTicks) / (double)Stopwatch.Frequency;
            Write("HEARTBEAT " + current + " running " + sec.ToString("F0") + "s " + Snapshot());
        }

        /// <summary>One-line process snapshot: working set, private bytes, handles, threads, GDI/USER objects, managed heap.</summary>
        public static string Snapshot()
        {
            try
            {
                Process p = Process.GetCurrentProcess();
                uint gdi = GetGuiResources(p.Handle, 0);
                uint usr = GetGuiResources(p.Handle, 1);
                return string.Format("ws={0}MB pm={1}MB handles={2} threads={3} gdi={4} user={5} managed={6}MB",
                    p.WorkingSet64 / 1048576, p.PrivateMemorySize64 / 1048576, p.HandleCount, p.Threads.Count,
                    gdi, usr, GC.GetTotalMemory(false) / 1048576);
            }
            catch (Exception ex)
            {
                return "snapshot-failed: " + ex.Message;
            }
        }

        private static string Truncate(string s, int max)
        {
            return s.Length <= max ? s : s.Substring(0, max) + "...";
        }
    }
}
