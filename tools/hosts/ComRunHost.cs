// Runs a skill DLL: calls its single public static int Run(string[]) on an STA thread (COM automation).
using System;
using System.IO;
using System.Reflection;

public static class ComRunHost
{
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Length < 1) { Console.Error.WriteLine("Usage: ComRunHost <skill.dll> [args...]"); return 2; }
        try
        {
            string dll = Path.GetFullPath(args[0]);
            Assembly asm = Assembly.Load(File.ReadAllBytes(dll));
            MethodInfo entry = null;
            foreach (Type type in asm.GetExportedTypes())
            {
                MethodInfo m = type.GetMethod("Run", BindingFlags.Public | BindingFlags.Static, null, new Type[] { typeof(string[]) }, null);
                if (m != null && m.ReturnType == typeof(int)) { entry = m; break; }
            }
            if (entry == null) throw new Exception("No public static int Run(string[]) found in " + dll);

            string[] rest = new string[args.Length - 1];
            Array.Copy(args, 1, rest, 0, rest.Length);
            int rc = (int)entry.Invoke(null, new object[] { rest });
            Console.Out.Flush();
            return rc;
        }
        catch (TargetInvocationException e) { Console.Error.WriteLine(e.InnerException.ToString()); return 13; }
        catch (Exception e) { Console.Error.WriteLine(e.ToString()); return 13; }
    }
}
