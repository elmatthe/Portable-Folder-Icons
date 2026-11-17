Option Explicit

Dim arguments, action, iconHash, targetPath, selectionToken, payloadHash
Dim fileSystem, shell, runtimeDirectory, dispatcher, powerShell, command, exitCode
Dim maintenance, runError

Const SetupGuidance = "To restore Portable Folder Icons, double-click Setup_and_Run-Portable-Folder-Icons.bat in your Portable Folder Icons folder. It needs no administrator rights."

Set arguments = WScript.Arguments
If arguments.Count < 2 Then WScript.Quit 64

If arguments.Count = 4 And CStr(arguments(0)) = "-SelectionToken" Then
    If CStr(arguments(2)) <> "-PayloadHash" Then WScript.Quit 64
    selectionToken = CStr(arguments(1))
    payloadHash = CStr(arguments(3))
    action = "Selection"
Else
    If CStr(arguments(0)) <> "-Action" Then WScript.Quit 64

    action = CStr(arguments(1))
    If action = "Apply" Then
        If arguments.Count <> 6 Then WScript.Quit 64
        If CStr(arguments(2)) <> "-IconHash" Then WScript.Quit 64
        If CStr(arguments(4)) <> "-TargetPath" Then WScript.Quit 64
        iconHash = CStr(arguments(3))
        targetPath = CStr(arguments(5))
    ElseIf action = "Reset" Then
        If arguments.Count <> 4 Then WScript.Quit 64
        If CStr(arguments(2)) <> "-TargetPath" Then WScript.Quit 64
        iconHash = ""
        targetPath = CStr(arguments(3))
    ElseIf action = "Repair" Or action = "Uninstall" Then
        If arguments.Count <> 2 Then WScript.Quit 64
    Else
        WScript.Quit 64
    End If
End If
maintenance = (action = "Repair" Or action = "Uninstall")

Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
runtimeDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
dispatcher = fileSystem.BuildPath(runtimeDirectory, "Invoke-PortableFolderIcons.ps1")
powerShell = shell.ExpandEnvironmentStrings("%SystemRoot%") & _
    "\System32\WindowsPowerShell\v1.0\powershell.exe"

' Repair and Uninstall run no product code before the dispatcher, so the launcher reports a missing dispatcher itself.
If maintenance And Not fileSystem.FileExists(dispatcher) Then
    ShowMaintenanceError "Portable Folder Icons could not start because its installed runtime file " & _
        "Invoke-PortableFolderIcons.ps1 is missing." & vbLf & vbLf & action & " did not run. Nothing was changed."
    WScript.Quit 1
End If

command = QuoteArgument(powerShell) & _
    " -NoLogo -NoProfile -ExecutionPolicy Bypass -File " & _
    QuoteArgument(dispatcher)
If action = "Selection" Then
    command = command & " -SelectionToken " & selectionToken & _
        " -PayloadHash " & payloadHash
Else
    command = command & " -Action " & action
    If action = "Apply" Then command = command & " -IconHash " & iconHash
    If Not maintenance Then command = command & " -TargetPathHex " & EncodeUtf16Hex(targetPath)
End If

If Not maintenance Then
    ' Window style 0 creates no console window. Waiting keeps this lightweight
    ' launcher alive until Apply/Reset and any error dialog have completed.
    exitCode = shell.Run(command, 0, True)
    WScript.Quit exitCode
End If

' Repair and Uninstall (Phase 0A.1). Window style 0 starts PowerShell hidden from creation, so Windows never hands its
' console to Windows Terminal; the '-WindowStyle Hidden' argument the verb used before could not prevent that. The
' dispatcher shows its own result, prompt and error dialogs and returns 0 completed, 1 failed, 2 cancelled or
' 3 partially repaired. Any other result means it never reported, so the launcher says so instead of ending silently.
On Error Resume Next
exitCode = shell.Run(command, 0, True)
If Err.Number <> 0 Then
    runError = Err.Description
    On Error GoTo 0
    ShowMaintenanceError "Portable Folder Icons could not start Windows PowerShell (" & runError & ")." & _
        vbLf & vbLf & action & " did not run. Nothing was changed."
    WScript.Quit 1
End If
On Error GoTo 0
If exitCode < 0 Or exitCode > 3 Then
    ShowMaintenanceError action & " ended before Portable Folder Icons could report a result (Windows PowerShell " & _
        "exit code " & exitCode & "). Its result is unknown."
    WScript.Quit 1
End If
WScript.Quit exitCode

Sub ShowMaintenanceError(ByVal message)
    Dim testDirectory, record
    message = message & vbLf & vbLf & SetupGuidance
    testDirectory = TestDialogDirectory()
    If testDirectory <> "" Then
        Set record = fileSystem.CreateTextFile(fileSystem.BuildPath(testDirectory, _
            "launcher-dialog-" & fileSystem.GetBaseName(fileSystem.GetTempName()) & ".txt"), True, True)
        record.Write "Error" & vbLf & message
        record.Close
        Exit Sub
    End If
    ' 65536 is MB_SETFOREGROUND, so the box is not left behind the Explorer window.
    MsgBox message, vbOKOnly + vbCritical + 65536, "Portable Folder Icons"
End Sub

Function TestDialogDirectory()
    ' Verification seam mirroring the dispatcher's (ADR 021): the dialog is recorded instead of shown only when
    ' PFI_TEST_DIALOG_DIR names an existing folder AND this runtime is not the production install root.
    Dim configured, localAppData, installRoot, productionRoot
    TestDialogDirectory = ""
    configured = shell.ExpandEnvironmentStrings("%PFI_TEST_DIALOG_DIR%")
    localAppData = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
    If configured = "%PFI_TEST_DIALOG_DIR%" Or Trim(configured) = "" Then Exit Function
    If localAppData = "%LOCALAPPDATA%" Or Trim(localAppData) = "" Then Exit Function
    installRoot = fileSystem.GetAbsolutePathName(fileSystem.GetParentFolderName(runtimeDirectory))
    productionRoot = fileSystem.GetAbsolutePathName(fileSystem.BuildPath(localAppData, "Portable-Folder-Icons"))
    If LCase(installRoot) = LCase(productionRoot) Then Exit Function
    If Not fileSystem.FolderExists(configured) Then Exit Function
    TestDialogDirectory = configured
End Function

Function QuoteArgument(ByVal value)
    QuoteArgument = Chr(34) & value & Chr(34)
End Function

Function EncodeUtf16Hex(ByVal value)
    Dim index, codeUnit, encoded
    encoded = ""
    For index = 1 To Len(value)
        codeUnit = AscW(Mid(value, index, 1))
        If codeUnit < 0 Then codeUnit = codeUnit + 65536
        encoded = encoded & Right("0000" & Hex(codeUnit), 4)
    Next
    EncodeUtf16Hex = encoded
End Function
