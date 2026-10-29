using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using Tecnomatix.Engineering;

namespace TxAi.Addin
{
    /// <summary>
    /// Ribbon command that hosts the AI bridge inside Process Simulate.
    /// Clicking it starts the pipe server (if needed) and shows its status.
    /// </summary>
    public class TxAiCommand : TxButtonCommand
    {
        private static UiThreadDispatcher _ui;
        private static TaskLoader _loader;
        private static PipeServer _server;
        private static AddinConfig _config;

        public override string Category
        {
            get { return "AI"; }
        }

        public override string Name
        {
            get { return "AI Bridge"; }
        }

        public override string Tooltip
        {
            get { return "Starts the local AI bridge that runs task DLLs requested by the agent."; }
        }

        public override string Description
        {
            get { return "Starts the local AI bridge (named pipe) that runs task DLLs requested by the agent."; }
        }

        public override ITxCommandEnabler CommandEnabler
        {
            get { return new TxCommandEnabler(true); }
        }

        public override bool Connect()
        {
            // Connect may run on the UI thread at startup; failure here must never break PS.
            try
            {
                string addinDirectory = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
                if (AddinConfig.Load(addinDirectory).AutoStart)
                {
                    EnsureStarted();
                }
            }
            catch (Exception ex)
            {
                Trace.TraceError("TxAi auto-start failed: " + ex);
            }
            return base.Connect();
        }

        public override void Disconnect()
        {
            try
            {
                if (_server != null)
                {
                    _server.Stop();
                }
                if (_loader != null)
                {
                    _loader.Detach();
                }
                if (_ui != null)
                {
                    _ui.Dispose();
                }
            }
            catch (Exception ex)
            {
                Trace.TraceError("TxAi shutdown failed: " + ex);
            }
            finally
            {
                _server = null;
                _loader = null;
                _ui = null;
            }
            base.Disconnect();
        }

        public override void Execute(object cmdParams)
        {
            try
            {
                EnsureStarted();
                MessageBox.Show(
                    "AI Bridge is running." + Environment.NewLine +
                    "Pipe: " + _server.PipePath + Environment.NewLine +
                    "Config: " + (_config.LoadedFrom ?? (AddinConfig.UserConfigPath + " (not found)")) + Environment.NewLine +
                    "Crash log: " + CrashLog.LogPath + Environment.NewLine +
                    "Allowed task directories:" + Environment.NewLine +
                    (_config.AllowedDirectories.Count == 0
                        ? "(none - add the task folder to the config)"
                        : string.Join(Environment.NewLine, _config.AllowedDirectories.ToArray())),
                    "AI Bridge",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(TaskLoader.Describe(ex), "AI Bridge", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static void EnsureStarted()
        {
            if (_server != null && _server.IsRunning)
            {
                return;
            }

            string addinDirectory = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            _config = AddinConfig.Load(addinDirectory);
            CrashLog.Init(5000);
            _ui = new UiThreadDispatcher();
            _loader = new TaskLoader(_config);
            _server = new PipeServer(_config, _ui, _loader);
            _server.Start();
        }
    }
}
