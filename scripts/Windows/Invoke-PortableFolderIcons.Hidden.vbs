Option Explicit

Dim arguments, action, iconHash, targetPath
Dim fileSystem, shell, runtimeDirectory, dispatcher, powerShell, command, exitCode

Set arguments = WScript.Arguments
If arguments.Count < 4 Then WScript.Quit 64
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
Else
    WScript.Quit 64
End If

Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
runtimeDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
dispatcher = fileSystem.BuildPath(runtimeDirectory, "Invoke-PortableFolderIcons.ps1")
powerShell = shell.ExpandEnvironmentStrings("%SystemRoot%") & _
    "\System32\WindowsPowerShell\v1.0\powershell.exe"

command = QuoteArgument(powerShell) & _
    " -NoLogo -NoProfile -ExecutionPolicy Bypass -File " & _
    QuoteArgument(dispatcher) & " -Action " & action
If action = "Apply" Then command = command & " -IconHash " & iconHash
command = command & " -TargetPathHex " & EncodeUtf16Hex(targetPath)

' Window style 0 creates no console window. Waiting keeps this lightweight
' launcher alive until Apply/Reset and any error dialog have completed.
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode

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
