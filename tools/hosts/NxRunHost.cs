// Loads an NX Open C++ DLL and calls its exported extern "C" int NxMain(int argc, char* argv[]).
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class NxRunHost
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr LoadLibraryW(string path);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    static extern IntPtr GetProcAddress(IntPtr module, string name);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int MainFn(int argc, IntPtr[] argv);

    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Length < 1) { Console.Error.WriteLine("Usage: NxRunHost <skill.dll> [args...]"); return 2; }
        try
        {
            string dll = Path.GetFullPath(args[0]);
            IntPtr h = LoadLibraryW(dll);
            if (h == IntPtr.Zero)
                throw new Exception("LoadLibrary failed, Win32 error " + Marshal.GetLastWin32Error() + " (check PATH contains UGII_ROOT_DIR)");
            IntPtr f = GetProcAddress(h, "NxMain");
            if (f == IntPtr.Zero) throw new Exception("Export NxMain not found in " + dll);

            string[] all = args;
            all[0] = dll;
            IntPtr[] argv = new IntPtr[all.Length + 1];
            for (int i = 0; i < all.Length; i++) argv[i] = Marshal.StringToHGlobalAnsi(all[i]);
            argv[all.Length] = IntPtr.Zero;
            int rc = ((MainFn)Marshal.GetDelegateForFunctionPointer(f, typeof(MainFn)))(all.Length, argv);
            Console.Out.Flush();
            return rc;
        }
        catch (Exception e) { Console.Error.WriteLine(e.ToString()); return 13; }
    }
}
