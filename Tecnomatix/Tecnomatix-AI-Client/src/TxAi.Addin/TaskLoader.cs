using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using TxAi.Contracts;

namespace TxAi.Addin
{
    /// <summary>Loads task DLLs from whitelisted directories and runs their ITxAiTask implementation.</summary>
    public sealed class TaskLoader
    {
        private readonly AddinConfig _config;

        public TaskLoader(AddinConfig config)
        {
            _config = config;
            AppDomain.CurrentDomain.AssemblyResolve += OnAssemblyResolve;
        }

        public void Detach()
        {
            AppDomain.CurrentDomain.AssemblyResolve -= OnAssemblyResolve;
        }

        /// <summary>Throws InvalidOperationException when the path is not an allowed task DLL.</summary>
        public string ValidatePath(string path)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                throw new InvalidOperationException("path is required.");
            }
            if (!Path.IsPathRooted(path))
            {
                throw new InvalidOperationException("path must be absolute.");
            }

            string full = Path.GetFullPath(path);
            if (!string.Equals(Path.GetExtension(full), ".dll", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Only .dll files are allowed.");
            }
            if (!File.Exists(full))
            {
                throw new InvalidOperationException("File not found: " + full);
            }

            if (_config.AllowedDirectories.Count == 0)
            {
                throw new InvalidOperationException(
                    "No AllowedDirectories configured. Add the task folder to " + AddinConfig.UserConfigPath);
            }

            foreach (string dir in _config.AllowedDirectories)
            {
                string root = Path.GetFullPath(dir).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (full.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                {
                    return full;
                }
            }
            throw new InvalidOperationException("Path is outside the allowed directories: " + full);
        }

        /// <summary>Must be called on the UI thread. Never throws; failures are returned as TxAiResult.Fail.</summary>
        public TxAiResult Run(string fullPath, TxAiContext context)
        {
            try
            {
                // Load from bytes so the file is not locked and can be rebuilt/redeployed without restarting PS.
                Assembly assembly = Assembly.Load(File.ReadAllBytes(fullPath));

                List<Type> candidates = new List<Type>();
                foreach (Type type in GetLoadableTypes(assembly))
                {
                    if (type.IsClass && !type.IsAbstract && typeof(ITxAiTask).IsAssignableFrom(type))
                    {
                        candidates.Add(type);
                    }
                }

                if (candidates.Count == 0)
                {
                    return TxAiResult.Fail("No ITxAiTask implementation found in " + Path.GetFileName(fullPath));
                }

                string typeName = context.GetString("type", null);
                Type taskType = null;
                if (typeName != null)
                {
                    foreach (Type candidate in candidates)
                    {
                        if (candidate.FullName == typeName || candidate.Name == typeName)
                        {
                            taskType = candidate;
                            break;
                        }
                    }
                    if (taskType == null)
                    {
                        return TxAiResult.Fail("Task type not found: " + typeName);
                    }
                }
                else if (candidates.Count == 1)
                {
                    taskType = candidates[0];
                }
                else
                {
                    return TxAiResult.Fail("Multiple ITxAiTask implementations found; pass args.type.");
                }

                ITxAiTask task = (ITxAiTask)Activator.CreateInstance(taskType);
                TxAiResult result = task.Run(context);
                return result ?? TxAiResult.Fail("Task returned null.");
            }
            catch (TargetInvocationException ex)
            {
                return TxAiResult.Fail(Describe(ex.InnerException ?? ex));
            }
            catch (Exception ex)
            {
                return TxAiResult.Fail(Describe(ex));
            }
        }

        private static IEnumerable<Type> GetLoadableTypes(Assembly assembly)
        {
            try
            {
                return assembly.GetTypes();
            }
            catch (ReflectionTypeLoadException ex)
            {
                List<Type> types = new List<Type>();
                foreach (Type type in ex.Types)
                {
                    if (type != null)
                    {
                        types.Add(type);
                    }
                }
                return types;
            }
        }

        public static string Describe(Exception ex)
        {
            return ex.GetType().FullName + ": " + ex.Message + Environment.NewLine + ex.StackTrace;
        }

        private Assembly OnAssemblyResolve(object sender, ResolveEventArgs args)
        {
            AssemblyName name = new AssemblyName(args.Name);
            if (string.Equals(name.Name, "TxAi.Contracts", StringComparison.OrdinalIgnoreCase))
            {
                return typeof(ITxAiTask).Assembly;
            }
            return null;
        }
    }
}
