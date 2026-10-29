using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Tecnomatix.Engineering;
using TxAi.Contracts;

namespace TxAi.Addin
{
    /// <summary>
    /// Line-delimited JSON over a per-user named pipe.
    /// Request : {"id":"1","method":"ping|get_status|run_dll","params":{...}}
    /// Response: {"id":"1","ok":true,"result":...,"error":null,"logs":[...],"durationMs":12}
    /// </summary>
    public sealed class PipeServer
    {
        private readonly AddinConfig _config;
        private readonly UiThreadDispatcher _ui;
        private readonly TaskLoader _loader;
        private readonly object _stateLock = new object();
        private Thread _acceptThread;
        private volatile bool _stopping;
        private long _requestCount;

        public PipeServer(AddinConfig config, UiThreadDispatcher ui, TaskLoader loader)
        {
            _config = config;
            _ui = ui;
            _loader = loader;
        }

        public bool IsRunning { get; private set; }

        public string PipePath
        {
            get { return @"\\.\pipe\" + _config.PipeName; }
        }

        public void Start()
        {
            lock (_stateLock)
            {
                if (IsRunning)
                {
                    return;
                }
                _stopping = false;
                _acceptThread = new Thread(AcceptLoop);
                _acceptThread.IsBackground = true;
                _acceptThread.Name = "TxAi.PipeServer";
                _acceptThread.Start();
                IsRunning = true;
            }
        }

        public void Stop()
        {
            lock (_stateLock)
            {
                if (!IsRunning)
                {
                    return;
                }
                _stopping = true;
                IsRunning = false;
            }

            // Unblock the pending WaitForConnection.
            try
            {
                using (NamedPipeClientStream wake = new NamedPipeClientStream(".", _config.PipeName, PipeDirection.InOut))
                {
                    wake.Connect(500);
                }
            }
            catch (Exception)
            {
            }
        }

        private NamedPipeServerStream CreatePipe()
        {
            PipeSecurity security = new PipeSecurity();
            security.AddAccessRule(new PipeAccessRule(
                WindowsIdentity.GetCurrent().User,
                PipeAccessRights.FullControl,
                AccessControlType.Allow));

            return new NamedPipeServerStream(
                _config.PipeName,
                PipeDirection.InOut,
                NamedPipeServerStream.MaxAllowedServerInstances,
                PipeTransmissionMode.Byte,
                PipeOptions.None,
                4096,
                4096,
                security);
        }

        private void AcceptLoop()
        {
            while (!_stopping)
            {
                NamedPipeServerStream pipe = null;
                try
                {
                    pipe = CreatePipe();
                    pipe.WaitForConnection();
                    if (_stopping)
                    {
                        pipe.Dispose();
                        break;
                    }

                    NamedPipeServerStream connected = pipe;
                    Thread worker = new Thread(delegate() { HandleClient(connected); });
                    worker.IsBackground = true;
                    worker.Name = "TxAi.PipeClient";
                    worker.Start();
                }
                catch (Exception ex)
                {
                    if (pipe != null)
                    {
                        pipe.Dispose();
                    }
                    Trace.TraceError("TxAi pipe accept failed: " + ex);
                    Thread.Sleep(1000);
                }
            }
        }

        private void HandleClient(NamedPipeServerStream pipe)
        {
            try
            {
                using (pipe)
                {
                    UTF8Encoding utf8 = new UTF8Encoding(false);
                    StreamReader reader = new StreamReader(pipe, utf8);
                    StreamWriter writer = new StreamWriter(pipe, utf8);
                    writer.AutoFlush = true;

                    string line;
                    while (!_stopping && (line = reader.ReadLine()) != null)
                    {
                        if (line.Length == 0)
                        {
                            continue;
                        }
                        string response = ProcessLine(line);
                        writer.WriteLine(response);
                    }
                }
            }
            catch (IOException)
            {
                // Client disconnected.
            }
            catch (Exception ex)
            {
                Trace.TraceError("TxAi pipe client failed: " + ex);
            }
        }

        private string ProcessLine(string line)
        {
            Stopwatch watch = Stopwatch.StartNew();
            List<string> logs = new List<string>();
            string id = null;
            bool ok = false;
            object result = null;
            string error = null;

            string logWhat = null;
            try
            {
                JObject request = JObject.Parse(line);
                id = (string)request["id"];
                string method = (string)request["method"];
                JObject parameters = request["params"] as JObject ?? new JObject();
                Interlocked.Increment(ref _requestCount);
                if (method != "ping")
                {
                    string argText = parameters["args"] != null ? parameters["args"].ToString(Formatting.None) : "";
                    if (argText.Length > 300)
                    {
                        argText = argText.Substring(0, 300) + "...";
                    }
                    logWhat = method + " " + (string)parameters["path"] + " args=" + argText;
                    CrashLog.Begin(logWhat);
                }

                switch (method)
                {
                    case "ping":
                        ok = true;
                        result = "pong";
                        break;
                    case "get_status":
                        ok = Invoke(GetStatus, _config.DefaultTimeoutMs, out result, out error);
                        break;
                    case "run_dll":
                        ok = RunDll(parameters, logs, out result, out error);
                        break;
                    default:
                        error = "Unknown method: " + method;
                        break;
                }
            }
            catch (Exception ex)
            {
                error = TaskLoader.Describe(ex);
            }

            watch.Stop();
            if (logWhat != null)
            {
                CrashLog.End(logWhat, ok, error);
            }
            JObject response = new JObject();
            response["id"] = id;
            response["ok"] = ok;
            response["result"] = result == null ? null : JToken.FromObject(result);
            response["error"] = error;
            response["logs"] = JArray.FromObject(logs);
            response["durationMs"] = watch.ElapsedMilliseconds;
            return response.ToString(Formatting.None);
        }

        private bool Invoke(Func<object> work, int timeoutMs, out object result, out string error)
        {
            object value;
            Exception exception;
            result = null;
            error = null;

            if (!_ui.TryInvoke<object>(work, timeoutMs, out value, out exception))
            {
                error = "Timed out waiting for the Process Simulate UI thread (is a modal dialog open?).";
                return false;
            }
            if (exception != null)
            {
                error = TaskLoader.Describe(exception);
                return false;
            }
            result = value;
            return true;
        }

        private object GetStatus()
        {
            Dictionary<string, object> status = new Dictionary<string, object>();
            status["addinVersion"] = typeof(PipeServer).Assembly.GetName().Version.ToString();
            status["processSimulateVersion"] = typeof(TxApplication).Assembly.GetName().Version.ToString();
            status["installationDirectory"] = TxApplication.InstallationDirectory;
            status["pipe"] = PipePath;
            status["requestCount"] = Interlocked.Read(ref _requestCount);
            status["allowedDirectories"] = _config.AllowedDirectories;
            status["hasActiveDocument"] = TxApplication.ActiveDocument != null;
            return status;
        }

        private bool RunDll(JObject parameters, List<string> logs, out object result, out string error)
        {
            result = null;
            error = null;

            string path = (string)parameters["path"];
            string fullPath;
            try
            {
                fullPath = _loader.ValidatePath(path);
            }
            catch (InvalidOperationException ex)
            {
                error = ex.Message;
                return false;
            }

            int timeoutMs = parameters["timeoutMs"] != null ? (int)parameters["timeoutMs"] : _config.DefaultTimeoutMs;
            JObject argsToken = parameters["args"] as JObject;
            Dictionary<string, object> args = argsToken != null
                ? argsToken.ToObject<Dictionary<string, object>>()
                : new Dictionary<string, object>();

            using (CancellationTokenSource cts = new CancellationTokenSource())
            {
                object syncRoot = logs;
                Action<string> log = delegate(string message)
                {
                    lock (syncRoot)
                    {
                        logs.Add(message);
                    }
                };
                TxAiContext context = new TxAiContext(args, cts.Token, log);

                object value;
                Exception exception;
                bool completed = _ui.TryInvoke<object>(delegate() { return _loader.Run(fullPath, context); }, timeoutMs, out value, out exception);
                if (!completed)
                {
                    cts.Cancel();
                    error = "Task timed out after " + timeoutMs + " ms. Cancellation was requested; a task that ignores it may still be running.";
                    return false;
                }
                if (exception != null)
                {
                    error = TaskLoader.Describe(exception);
                    return false;
                }

                TxAiResult taskResult = (TxAiResult)value;
                if (!string.IsNullOrEmpty(taskResult.Message))
                {
                    log("[result] " + taskResult.Message);
                }
                if (!taskResult.Ok)
                {
                    error = taskResult.Message;
                    return false;
                }
                result = taskResult.Data;
                return true;
            }
        }
    }
}
