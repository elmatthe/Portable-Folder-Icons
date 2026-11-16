using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

[assembly: System.Reflection.AssemblyTitle("Portable Folder Icons Selection Broker")]
[assembly: System.Reflection.AssemblyDescription("Classic Explorer selection transport for Portable Folder Icons")]
[assembly: System.Reflection.AssemblyCompany("elmatthe")]
[assembly: System.Reflection.AssemblyProduct("Portable Folder Icons")]
[assembly: System.Reflection.AssemblyCopyright("Copyright (c) 2026 elmatthe")]
[assembly: System.Reflection.AssemblyVersion("0.1.1.0")]
[assembly: System.Reflection.AssemblyFileVersion("0.1.1.0")]

namespace PortableFolderIcons.SelectionBroker
{
    [ComVisible(true), Guid("7F9185B0-CB92-43C5-80A9-92277A4F7B54"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IExecuteCommand
    {
        [PreserveSig] int SetKeyState(uint keyState);
        [PreserveSig] int SetParameters([MarshalAs(UnmanagedType.LPWStr)] string parameters);
        [PreserveSig] int SetPosition(Point point);
        [PreserveSig] int SetShowWindow(int showWindow);
        [PreserveSig] int SetNoShowUI([MarshalAs(UnmanagedType.Bool)] bool noShowUi);
        [PreserveSig] int SetDirectory([MarshalAs(UnmanagedType.LPWStr)] string directory);
        [PreserveSig] int Execute();
    }

    [ComVisible(true), Guid("1C9CD5BB-98E9-4491-A60F-31AACC72B83C"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IObjectWithSelection
    {
        [PreserveSig] int SetSelection([MarshalAs(UnmanagedType.Interface)] IShellItemArray selection);
        [PreserveSig] int GetSelection(ref Guid riid, out IntPtr selection);
    }

    [ComVisible(true), Guid("85075ACF-231F-40EA-9610-D26B7B58F638"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IInitializeCommand
    {
        [PreserveSig] int Initialize(
            [MarshalAs(UnmanagedType.LPWStr)] string commandName,
            [MarshalAs(UnmanagedType.Interface)] IPropertyBag propertyBag);
    }

    [ComImport, Guid("55272A00-42CB-11CE-8135-00AA004BB851"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyBag
    {
        [PreserveSig] int Read(
            [MarshalAs(UnmanagedType.LPWStr)] string name,
            ref Variant value,
            IntPtr errorLog);
        [PreserveSig] int Write(
            [MarshalAs(UnmanagedType.LPWStr)] string name,
            ref Variant value);
    }

    [ComImport, Guid("B63EA76D-1F85-456F-A19C-48159EFA858B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItemArray
    {
        [PreserveSig] int BindToHandler(IntPtr bindContext, ref Guid handler, ref Guid riid, out IntPtr result);
        [PreserveSig] int GetPropertyStore(int flags, ref Guid riid, out IntPtr result);
        [PreserveSig] int GetPropertyDescriptionList(IntPtr keyType, ref Guid riid, out IntPtr result);
        [PreserveSig] int GetAttributes(uint flags, uint mask, out uint attributes);
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetItemAt(uint index, out IShellItem item);
        [PreserveSig] int EnumItems(out IntPtr enumerator);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItem
    {
        [PreserveSig] int BindToHandler(IntPtr bindContext, ref Guid handler, ref Guid riid, out IntPtr result);
        [PreserveSig] int GetParent(out IShellItem parent);
        [PreserveSig] int GetDisplayName(uint displayNameType, out IntPtr name);
        [PreserveSig] int GetAttributes(uint mask, out uint attributes);
        [PreserveSig] int Compare(IShellItem other, uint hint, out int order);
    }

    [ComVisible(true), Guid("00000001-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IClassFactory
    {
        [PreserveSig] int CreateInstance(IntPtr outer, ref Guid riid, out IntPtr instance);
        [PreserveSig] int LockServer([MarshalAs(UnmanagedType.Bool)] bool locked);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct VariantRecord
    {
        public IntPtr Record;
        public IntPtr RecordInfo;
    }

    // The native VARIANT union includes two pointers at offset 8: 24 bytes on
    // x64 and 16 on x86. A fixed 16-byte buffer is unsafe for IPropertyBag.
    [StructLayout(LayoutKind.Explicit)]
    public struct Variant
    {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public IntPtr Pointer;
        [FieldOffset(8)] public VariantRecord Record;
    }

    [DataContract]
    internal sealed class SelectionPayload
    {
        [DataMember(Order = 0)] public int schemaVersion;
        [DataMember(Order = 1)] public string token;
        [DataMember(Order = 2)] public string createdUtc;
        [DataMember(Order = 3)] public string action;
        [DataMember(Order = 4, EmitDefaultValue = false)] public string iconHash;
        [DataMember(Order = 5)] public List<string> paths;
    }

    [DataContract]
    internal sealed class InstalledSettings
    {
        [DataMember(Order = 0)] public int schemaVersion = 0;
        [DataMember(Order = 1)] public bool developerMode = false;
    }

    public interface ISelectionPathSource
    {
        uint Count { get; }
        string GetPath(uint index);
    }

    public static class SelectionTransport
    {
        public static List<string> ReadAll(ISelectionPathSource source)
        {
            if (source == null) throw new ArgumentNullException("source");
            List<string> paths = new List<string>();
            for (uint index = 0; index < source.Count; index++)
            {
                string path = source.GetPath(index);
                if (String.IsNullOrEmpty(path))
                    throw new InvalidOperationException("A selected Shell item has no filesystem path.");
                paths.Add(path);
            }
            return paths;
        }
    }

    internal sealed class ShellSelectionPathSource : ISelectionPathSource
    {
        private const uint SigDnFileSystemPath = 0x80058000;
        private readonly IShellItemArray selection;
        private readonly uint count;

        internal ShellSelectionPathSource(IShellItemArray selection)
        {
            this.selection = selection;
            int result = selection.GetCount(out count);
            if (result < 0) Marshal.ThrowExceptionForHR(result);
        }

        public uint Count { get { return count; } }

        public string GetPath(uint index)
        {
            IShellItem item;
            int result = selection.GetItemAt(index, out item);
            if (result < 0) Marshal.ThrowExceptionForHR(result);
            IntPtr value = IntPtr.Zero;
            try
            {
                result = item.GetDisplayName(SigDnFileSystemPath, out value);
                if (result < 0) Marshal.ThrowExceptionForHR(result);
                return Marshal.PtrToStringUni(value);
            }
            finally
            {
                if (value != IntPtr.Zero) Marshal.FreeCoTaskMem(value);
                if (item != null && Marshal.IsComObject(item)) Marshal.ReleaseComObject(item);
            }
        }
    }

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class SelectionCommand : IExecuteCommand, IObjectWithSelection, IInitializeCommand
    {
        public const string ResetCommandName = "Utility_0100_Reset";
        private static readonly Regex ApplyCommand = new Regex(
            @"^PortableFolderIcons\.Apply\.[0-9]{4}$",
            RegexOptions.CultureInvariant);
        private IShellItemArray selection;
        private string commandName;
        private string action;
        private string iconHash;

        public int Initialize(string name, IPropertyBag propertyBag)
        {
            commandName = name;
            if (propertyBag != null)
            {
                action = ReadPropertyString(propertyBag, "PfiAction");
                iconHash = ReadPropertyString(propertyBag, "PfiIconHash");
            }
            return 0;
        }

        public int SetSelection(IShellItemArray items)
        {
            selection = items;
            return items == null ? unchecked((int)0x80070057) : 0;
        }

        public int GetSelection(ref Guid riid, out IntPtr result)
        {
            result = IntPtr.Zero;
            if (selection == null) return unchecked((int)0x80004005);
            IntPtr unknown = Marshal.GetIUnknownForObject(selection);
            try { return Marshal.QueryInterface(unknown, ref riid, out result); }
            finally { Marshal.Release(unknown); }
        }

        public int Execute()
        {
            string validationError;
            if (!ValidateCommand(out validationError) || selection == null)
            {
                ShowError(validationError ?? "Explorer did not supply a folder selection.");
                return unchecked((int)0x80070057);
            }
            Thread worker = new Thread(RunBroker);
            worker.Name = "Portable Folder Icons selection bridge";
            worker.IsBackground = false;
            worker.SetApartmentState(ApartmentState.MTA);
            worker.Start();
            return 0;
        }

        private bool ValidateCommand(out string error)
        {
            error = null;
            if (String.Equals(action, "Apply", StringComparison.Ordinal))
            {
                if (!ApplyCommand.IsMatch(commandName ?? String.Empty))
                    error = "The selected Apply command identity is invalid.";
                else if (!Regex.IsMatch(iconHash ?? String.Empty, "^[a-fA-F0-9]{64}$", RegexOptions.CultureInvariant))
                    error = "The selected icon identity is invalid.";
                else
                    iconHash = iconHash.ToLowerInvariant();
            }
            else if (String.Equals(action, "Reset", StringComparison.Ordinal))
            {
                if (!String.Equals(commandName, ResetCommandName, StringComparison.Ordinal))
                    error = "The selected Reset command identity is invalid.";
                else if (!String.IsNullOrEmpty(iconHash))
                    error = "Reset must not specify an icon identity.";
            }
            else
            {
                error = "The selected Portable Folder Icons action is invalid.";
            }
            return error == null;
        }

        private void RunBroker()
        {
            string payloadPath = null;
            try
            {
                List<string> paths = EnumerateSelection();
                if (paths.Count == 0) throw new InvalidOperationException("Explorer supplied an empty folder selection.");
                string installRoot = ResolveInstallRoot();
                CleanupStalePayloads(installRoot);
                string token;
                string payloadHash;
                WritePayload(installRoot, paths, out token, out payloadHash, out payloadPath);
                LaunchDispatcher(installRoot, token, payloadHash);
                payloadPath = null;
            }
            catch (Exception exception)
            {
                if (!String.IsNullOrEmpty(payloadPath))
                {
                    try { if (File.Exists(payloadPath)) File.Delete(payloadPath); }
                    catch { }
                }
                ShowError("The Explorer selection could not be delivered safely.\r\n\r\n" + exception.Message);
            }
            finally
            {
                if (selection != null && Marshal.IsComObject(selection))
                {
                    try { Marshal.ReleaseComObject(selection); }
                    catch { }
                }
                selection = null;
                Server.RequestExit();
            }
        }

        private List<string> EnumerateSelection()
        {
            return SelectionTransport.ReadAll(new ShellSelectionPathSource(selection));
        }

        private string ResolveInstallRoot()
        {
            string executable = Path.GetFullPath(Process.GetCurrentProcess().MainModule.FileName);
            DirectoryInfo selectionDirectory = new FileInfo(executable).Directory;
            if (selectionDirectory == null || !String.Equals(selectionDirectory.Name, "SelectionHandler", StringComparison.Ordinal))
                throw new InvalidOperationException("The selection broker is outside its installed runtime location.");
            DirectoryInfo runtimeDirectory = selectionDirectory.Parent;
            if (runtimeDirectory == null || !String.Equals(runtimeDirectory.Name, "runtime", StringComparison.Ordinal))
                throw new InvalidOperationException("The selection broker runtime location is invalid.");
            DirectoryInfo installDirectory = runtimeDirectory.Parent;
            if (installDirectory == null) throw new InvalidOperationException("The installed root is unavailable.");
            string expected = Path.GetFullPath(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Portable-Folder-Icons"));
            string actual = Path.GetFullPath(installDirectory.FullName);
            if (!String.Equals(actual.TrimEnd('\\'), expected.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The selection broker is outside the current-user install root.");
            return actual;
        }

        private void WritePayload(
            string installRoot,
            List<string> paths,
            out string token,
            out string payloadHash,
            out string payloadPath)
        {
            token = Guid.NewGuid().ToString("N");
            string requests = Path.Combine(installRoot, "state", "requests");
            Directory.CreateDirectory(requests);
            string fileName = "request-" + token + ".json";
            payloadPath = Path.Combine(requests, fileName);
            string temporary = Path.Combine(requests, ".request-" + token + ".tmp");
            SelectionPayload payload = new SelectionPayload
            {
                schemaVersion = 1,
                token = token,
                createdUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                action = action,
                iconHash = String.Equals(action, "Apply", StringComparison.Ordinal) ? iconHash : null,
                paths = paths
            };
            byte[] bytes;
            DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(SelectionPayload));
            using (MemoryStream memory = new MemoryStream())
            {
                serializer.WriteObject(memory, payload);
                bytes = memory.ToArray();
            }
            try
            {
                using (FileStream stream = new FileStream(
                    temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                    4096, FileOptions.WriteThrough))
                {
                    stream.Write(bytes, 0, bytes.Length);
                    stream.Flush(true);
                }
                File.Move(temporary, payloadPath);
            }
            finally
            {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
            using (SHA256 sha = SHA256.Create())
                payloadHash = ToHex(sha.ComputeHash(bytes));
        }

        private void LaunchDispatcher(string installRoot, string token, string payloadHash)
        {
            string runtime = Path.Combine(installRoot, "runtime");
            string dispatcher = Path.Combine(runtime, "Invoke-PortableFolderIcons.ps1");
            string hiddenLauncher = Path.Combine(runtime, "Invoke-PortableFolderIcons.Hidden.vbs");
            if (!File.Exists(dispatcher) || !File.Exists(hiddenLauncher))
                throw new FileNotFoundException("The installed action dispatcher is incomplete.");
            bool developerMode = ReadDeveloperMode(Path.Combine(installRoot, "settings.json"));
            ProcessStartInfo start = new ProcessStartInfo();
            start.UseShellExecute = false;
            if (developerMode)
            {
                start.FileName = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                    "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
                start.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File " + Quote(dispatcher) +
                    " -SelectionToken " + token + " -PayloadHash " + payloadHash;
                start.CreateNoWindow = false;
                start.WindowStyle = ProcessWindowStyle.Normal;
            }
            else
            {
                start.FileName = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "wscript.exe");
                start.Arguments = Quote(hiddenLauncher) + " -SelectionToken " + token +
                    " -PayloadHash " + payloadHash;
                start.CreateNoWindow = true;
                start.WindowStyle = ProcessWindowStyle.Hidden;
            }
            Process process = Process.Start(start);
            if (process == null) throw new InvalidOperationException("The installed action dispatcher did not start.");
            process.Dispose();
        }

        private bool ReadDeveloperMode(string settingsPath)
        {
            try
            {
                using (FileStream stream = new FileStream(settingsPath, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(InstalledSettings));
                    InstalledSettings settings = serializer.ReadObject(stream) as InstalledSettings;
                    return settings != null && settings.schemaVersion == 1 && settings.developerMode;
                }
            }
            catch { return false; }
        }

        private void CleanupStalePayloads(string installRoot)
        {
            string requests = Path.Combine(installRoot, "state", "requests");
            if (!Directory.Exists(requests)) return;
            DateTime cutoff = DateTime.UtcNow.AddDays(-1);
            foreach (string path in Directory.GetFiles(requests))
            {
                string name = Path.GetFileName(path);
                if (!Regex.IsMatch(name, @"^(?:request-[a-f0-9]{32}\.json|\.request-[a-f0-9]{32}\.tmp)$", RegexOptions.CultureInvariant))
                    continue;
                FileInfo item = new FileInfo(path);
                if ((item.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                if (item.LastWriteTimeUtc < cutoff)
                {
                    try { item.Delete(); }
                    catch { }
                }
            }
        }

        private static string ReadPropertyString(IPropertyBag propertyBag, string name)
        {
            Variant value = new Variant();
            try
            {
                int hr = propertyBag.Read(name, ref value, IntPtr.Zero);
                if (hr < 0) return null;
                if (value.Type == 8 || value.Type == 31)
                    return Marshal.PtrToStringUni(value.Pointer);
                return null;
            }
            finally { VariantClear(ref value); }
        }

        private static string ToHex(byte[] bytes)
        {
            StringBuilder result = new StringBuilder(bytes.Length * 2);
            foreach (byte value in bytes) result.Append(value.ToString("x2", CultureInfo.InvariantCulture));
            return result.ToString();
        }

        private static string Quote(string value)
        {
            if (value.IndexOf('"') >= 0) throw new InvalidOperationException("An installed path contains an invalid quotation mark.");
            return "\"" + value + "\"";
        }

        [DllImport("oleaut32.dll")]
        private static extern int VariantClear(ref Variant value);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int MessageBox(IntPtr window, string text, string caption, uint type);

        private static void ShowError(string message)
        {
            MessageBox(IntPtr.Zero, message, "Portable Folder Icons", 0x00000010 | 0x00010000);
        }

        public int SetKeyState(uint state) { return 0; }
        public int SetParameters(string value) { return 0; }
        public int SetPosition(Point point) { return 0; }
        public int SetShowWindow(int show) { return 0; }
        public int SetNoShowUI(bool value) { return 0; }
        public int SetDirectory(string value) { return 0; }
    }

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class SelectionClassFactory : IClassFactory
    {
        public int CreateInstance(IntPtr outer, ref Guid riid, out IntPtr instance)
        {
            instance = IntPtr.Zero;
            if (outer != IntPtr.Zero) return unchecked((int)0x80040110);
            object handler = new SelectionCommand();
            IntPtr unknown = Marshal.GetIUnknownForObject(handler);
            try { return Marshal.QueryInterface(unknown, ref riid, out instance); }
            finally { Marshal.Release(unknown); }
        }

        public int LockServer(bool locked) { return 0; }
    }

    internal static class Server
    {
        private static readonly Guid ClassId = new Guid("10DE6C30-6CD5-4B62-BCFA-18DD3687C531");
        private static uint mainThreadId;

        [StructLayout(LayoutKind.Sequential)]
        private struct Message
        {
            internal IntPtr Window;
            internal uint Id;
            internal IntPtr WParam;
            internal IntPtr LParam;
            internal uint Time;
            internal Point Position;
        }

        [DllImport("ole32.dll")]
        private static extern int CoRegisterClassObject(
            ref Guid clsid,
            [MarshalAs(UnmanagedType.Interface)] IClassFactory factory,
            uint context,
            uint flags,
            out uint cookie);
        [DllImport("ole32.dll")]
        private static extern int CoRevokeClassObject(uint cookie);
        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")]
        private static extern bool PeekMessage(out Message message, IntPtr window, uint minimum, uint maximum, uint remove);
        [DllImport("user32.dll")]
        private static extern sbyte GetMessage(out Message message, IntPtr window, uint minimum, uint maximum);
        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(ref Message message);
        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage(ref Message message);
        [DllImport("user32.dll")]
        private static extern bool PostThreadMessage(uint threadId, uint message, IntPtr wParam, IntPtr lParam);

        internal static void RequestExit()
        {
            PostThreadMessage(mainThreadId, 0x0012, IntPtr.Zero, IntPtr.Zero);
        }

        [STAThread]
        private static int Main(string[] args)
        {
            bool embedding = false;
            foreach (string argument in args)
                if (String.Equals(argument, "-Embedding", StringComparison.OrdinalIgnoreCase)) embedding = true;
            if (!embedding) return 64;
            mainThreadId = GetCurrentThreadId();
            Message initialMessage;
            PeekMessage(out initialMessage, IntPtr.Zero, 0, 0, 0);
            SelectionClassFactory factory = new SelectionClassFactory();
            uint cookie;
            Guid classId = ClassId;
            int result = CoRegisterClassObject(ref classId, factory, 4, 0, out cookie);
            if (result < 0) return result;
            try
            {
                Message message;
                sbyte messageResult;
                while ((messageResult = GetMessage(out message, IntPtr.Zero, 0, 0)) > 0)
                {
                    TranslateMessage(ref message);
                    DispatchMessage(ref message);
                }
                return messageResult == 0 ? 0 : 65;
            }
            finally { CoRevokeClassObject(cookie); }
        }
    }
}
