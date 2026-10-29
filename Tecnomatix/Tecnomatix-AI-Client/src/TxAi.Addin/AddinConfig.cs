using System;
using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json;

namespace TxAi.Addin
{
    /// <summary>Config file: %LOCALAPPDATA%\TxAi\txai.config.json (preferred), else txai.config.json next to TxAi.Addin.dll.</summary>
    public sealed class AddinConfig
    {
        public const string DefaultPipeName = "TxAiClient";
        public const string FileName = "txai.config.json";

        public static string UserConfigPath
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TxAi", FileName);
            }
        }

        /// <summary>The file the settings were read from; null when defaults are used.</summary>
        public string LoadedFrom { get; private set; }

        public AddinConfig()
        {
            PipeName = DefaultPipeName;
            AllowedDirectories = new List<string>();
            DefaultTimeoutMs = 120000;
            AutoStart = false;
        }

        public string PipeName { get; set; }

        /// <summary>Start the bridge when PS loads the command (Connect). Default false: start by clicking the ribbon button.</summary>
        public bool AutoStart { get; set; }

        /// <summary>Task DLLs may only be loaded from these directories (or their subdirectories).</summary>
        public List<string> AllowedDirectories { get; set; }

        public int DefaultTimeoutMs { get; set; }

        public static AddinConfig Load(string addinDirectory)
        {
            AddinConfig config = new AddinConfig();
            string file = File.Exists(UserConfigPath) ? UserConfigPath : Path.Combine(addinDirectory, FileName);
            if (File.Exists(file))
            {
                AddinConfig loaded = JsonConvert.DeserializeObject<AddinConfig>(File.ReadAllText(file));
                if (loaded != null)
                {
                    config = loaded;
                    config.LoadedFrom = file;
                }
            }

            if (string.IsNullOrWhiteSpace(config.PipeName))
            {
                config.PipeName = DefaultPipeName;
            }
            if (config.AllowedDirectories == null)
            {
                config.AllowedDirectories = new List<string>();
            }
            if (config.DefaultTimeoutMs <= 0)
            {
                config.DefaultTimeoutMs = 120000;
            }
            return config;
        }
    }
}
