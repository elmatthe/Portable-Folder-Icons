using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using PortableFolderIcons.SelectionBroker;

internal sealed class SyntheticSelection : ISelectionPathSource
{
    private readonly IList<string> paths;
    internal readonly List<uint> RequestedIndexes = new List<uint>();

    internal SyntheticSelection(IList<string> paths) { this.paths = paths; }
    public uint Count { get { return (uint)paths.Count; } }
    public string GetPath(uint index)
    {
        RequestedIndexes.Add(index);
        return paths[(int)index];
    }
}

internal static class SelectionBrokerHarness
{
    private static int passed;

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
        passed++;
    }

    private static readonly BindingFlags PrivateInstance = BindingFlags.Instance | BindingFlags.NonPublic;

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class RegistryProperties : IPropertyBag
    {
        private readonly string action;
        private readonly string hash;
        public RegistryProperties(string action, string hash) { this.action = action; this.hash = hash; }
        public int Read(string name, ref Variant value, IntPtr errorLog)
        {
            string text = name == "PfiAction" ? action : name == "PfiIconHash" ? hash : null;
            if (String.IsNullOrEmpty(text)) return unchecked((int)0x80070057);
            value.Type = 8;
            value.Pointer = Marshal.StringToBSTR(text);
            return 0;
        }
        public int Write(string name, ref Variant value) { return unchecked((int)0x80004001); }
    }

    private static bool InitializeAndValidate(string name, string action, string hash)
    {
        SelectionCommand command = new SelectionCommand();
        Assert(command.Initialize(name, new RegistryProperties(action, hash)) == 0,
            "The registration-derived command could not initialize.");
        object[] arguments = new object[] { null };
        bool accepted = (bool)typeof(SelectionCommand).GetMethod("ValidateCommand", PrivateInstance).Invoke(command, arguments);
        Assert(String.Equals((string)typeof(SelectionCommand).GetField("action", PrivateInstance).GetValue(command), action,
            StringComparison.Ordinal), "Initialization changed the registered action.");
        return accepted;
    }

    private static void CheckContracts(string file)
    {
        int applyCount = 0;
        int resetCount = 0;
        foreach (string line in File.ReadAllLines(file))
        {
            string[] fields = line.Split('\t');
            Assert(fields.Length == 3, "A registration-derived contract is malformed.");
            Assert(InitializeAndValidate(fields[0], fields[1], fields[2]),
                "The broker rejected the registered verb: " + fields[0]);
            if (fields[1] == "Apply") applyCount++;
            if (fields[1] == "Reset") resetCount++;
        }
        Assert(applyCount > 0 && resetCount == 1, "Contracts must cover Apply and exactly one Reset.");
        Assert(!InitializeAndValidate("PortableFolderIcons.Reset", "Reset", ""),
            "The old unregistered Reset identity was accepted.");
        Assert(!InitializeAndValidate(SelectionCommand.ResetCommandName, "Reset", new string('a', 64)),
            "Reset accepted an Apply icon identity.");
        Assert(!InitializeAndValidate("PortableFolderIcons.Apply.0001", "Reset", ""),
            "An Apply verb accepted Reset semantics.");
        Assert(!InitializeAndValidate("PortableFolderIcons.Apply.0001", "Apply", "bad"),
            "Apply accepted a malformed icon identity.");
    }

    [DllImport("ole32.dll")]
    private static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint context, ref Guid iid, out IntPtr instance);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHParseDisplayName(string name, IntPtr bindContext, out IntPtr pidl, uint attributes, out uint resultAttributes);
    [DllImport("shell32.dll")]
    private static extern int SHCreateShellItemArrayFromIDLists(uint count, IntPtr[] pidls, out IShellItemArray selection);

    private static int InvokeInstalled(string registryPath, string pathFile)
    {
        string name = registryPath.Substring(registryPath.LastIndexOf('\\') + 1);
        using (RegistryKey key = Registry.CurrentUser.OpenSubKey(registryPath))
        using (RegistryKey commandKey = Registry.CurrentUser.OpenSubKey(registryPath + @"\command"))
        {
            if (key == null || commandKey == null) throw new InvalidOperationException("Installed verb is missing.");
            string action = (string)key.GetValue("PfiAction");
            string hash = (string)key.GetValue("PfiIconHash", "");
            if (!InitializeAndValidate(name, action, hash)) throw new InvalidOperationException("Installed identity is invalid.");
            Guid clsid = new Guid((string)commandKey.GetValue("DelegateExecute"));
            if (clsid != new Guid("10DE6C30-6CD5-4B62-BCFA-18DD3687C531"))
                throw new InvalidOperationException("Refusing an unrelated COM server.");
            Guid iid = typeof(IInitializeCommand).GUID;
            IntPtr pointer;
            Marshal.ThrowExceptionForHR(CoCreateInstance(ref clsid, IntPtr.Zero, 4, ref iid, out pointer));
            object remote;
            try { remote = Marshal.GetObjectForIUnknown(pointer); }
            finally { Marshal.Release(pointer); }
            string[] paths = File.ReadAllLines(pathFile);
            IntPtr[] pidls = new IntPtr[paths.Length];
            IShellItemArray selection = null;
            try
            {
                for (int index = 0; index < paths.Length; index++)
                {
                    uint attributes;
                    Marshal.ThrowExceptionForHR(SHParseDisplayName(paths[index], IntPtr.Zero, out pidls[index], 0, out attributes));
                }
                Marshal.ThrowExceptionForHR(SHCreateShellItemArrayFromIDLists((uint)pidls.Length, pidls, out selection));
                Marshal.ThrowExceptionForHR(((IInitializeCommand)remote).Initialize(name, new RegistryProperties(action, hash)));
                Marshal.ThrowExceptionForHR(((IObjectWithSelection)remote).SetSelection(selection));
                Marshal.ThrowExceptionForHR(((IExecuteCommand)remote).Execute());
                Console.WriteLine("Installed COM dispatch accepted: {0}; verb={1}; targets={2}", action, name, paths.Length);
                return 0;
            }
            finally
            {
                foreach (IntPtr pidl in pidls) if (pidl != IntPtr.Zero) Marshal.FreeCoTaskMem(pidl);
                if (selection != null) Marshal.ReleaseComObject(selection);
                Marshal.ReleaseComObject(remote);
            }
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 3 && args[0] == "--invoke-installed") return InvokeInstalled(args[1], args[2]);
        Assert(Marshal.SizeOf(typeof(Variant)) == (IntPtr.Size == 8 ? 24 : 16),
            "IPropertyBag VARIANT does not match the native architecture layout.");
        List<string> expected = new List<string>();
        for (int index = 0; index < 125; index++)
            expected.Add(@"C:\Selection\Item " + index.ToString("D3") + @" (ü) % ! & O'Brien");
        expected.Insert(63, expected[2]);
        SyntheticSelection source = new SyntheticSelection(expected);
        List<string> actual = SelectionTransport.ReadAll(source);
        Assert(actual.Count == 126, "The handler seam truncated a >100 selection.");
        Assert(source.RequestedIndexes.Count == 126, "The handler seam did not enumerate every item.");
        for (int index = 0; index < actual.Count; index++)
        {
            Assert(source.RequestedIndexes[index] == (uint)index, "The handler seam requested items out of order.");
            Assert(String.Equals(expected[index], actual[index], StringComparison.Ordinal),
                "The handler seam changed, sorted, or deduplicated a path.");
        }
        Assert(SelectionTransport.ReadAll(new SyntheticSelection(new List<string>())).Count == 0,
            "The handler seam did not preserve an empty selection for safe rejection upstream.");
        bool rejectedNull = false;
        try { SelectionTransport.ReadAll(null); }
        catch (ArgumentNullException) { rejectedNull = true; }
        Assert(rejectedNull, "The handler seam accepted a null selection source.");
        if (args.Length == 1) CheckContracts(args[0]);
        Console.WriteLine("Selection broker harness: {0} passed", passed);
        return 0;
    }
}
