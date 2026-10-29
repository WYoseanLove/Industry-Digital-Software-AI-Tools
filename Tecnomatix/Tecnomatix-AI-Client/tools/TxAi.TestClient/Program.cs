using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using Newtonsoft.Json.Linq;

namespace TxAi.TestClient
{
    /// <summary>
    /// Usage:
    ///   TxAi.TestClient ping
    ///   TxAi.TestClient status
    ///   TxAi.TestClient run &lt;dllPath&gt; [argsJson] [timeoutMs]
    /// Env TXAI_PIPE overrides the pipe name (default TxAiClient).
    /// </summary>
    internal static class Program
    {
        private static int Main(string[] args)
        {
            if (args.Length == 0)
            {
                Console.Error.WriteLine("Usage: TxAi.TestClient ping | status | run <dllPath> [argsJson] [timeoutMs]");
                return 2;
            }

            JObject request = new JObject();
            request["id"] = Guid.NewGuid().ToString("N");
            JObject parameters = new JObject();

            switch (args[0])
            {
                case "ping":
                    request["method"] = "ping";
                    break;
                case "status":
                    request["method"] = "get_status";
                    break;
                case "run":
                    if (args.Length < 2)
                    {
                        Console.Error.WriteLine("run requires <dllPath>");
                        return 2;
                    }
                    request["method"] = "run_dll";
                    parameters["path"] = args[1];
                    if (args.Length > 2)
                    {
                        parameters["args"] = JObject.Parse(args[2]);
                    }
                    if (args.Length > 3)
                    {
                        parameters["timeoutMs"] = int.Parse(args[3]);
                    }
                    break;
                default:
                    Console.Error.WriteLine("Unknown command: " + args[0]);
                    return 2;
            }
            request["params"] = parameters;

            string pipeName = Environment.GetEnvironmentVariable("TXAI_PIPE") ?? "TxAiClient";
            try
            {
                using (NamedPipeClientStream pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut))
                {
                    pipe.Connect(3000);
                    UTF8Encoding utf8 = new UTF8Encoding(false);
                    StreamWriter writer = new StreamWriter(pipe, utf8);
                    writer.AutoFlush = true;
                    StreamReader reader = new StreamReader(pipe, utf8);

                    writer.WriteLine(request.ToString(Newtonsoft.Json.Formatting.None));
                    string response = reader.ReadLine();
                    if (response == null)
                    {
                        Console.Error.WriteLine("Connection closed without a response.");
                        return 1;
                    }

                    JObject parsed = JObject.Parse(response);
                    Console.WriteLine(parsed.ToString(Newtonsoft.Json.Formatting.Indented));
                    return (bool)parsed["ok"] ? 0 : 1;
                }
            }
            catch (TimeoutException)
            {
                Console.Error.WriteLine("Could not connect to pipe '" + pipeName + "'. Is the AI Bridge started in Process Simulate?");
                return 3;
            }
        }
    }
}
