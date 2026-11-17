param([Parameter(Mandatory = $true)][string]$Launcher,
      [Parameter(Mandatory = $true)][string]$Editor)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$testRoot = 'Software\NotepadReplacerTests\' + [guid]::NewGuid().ToString('N')
$directory = Join-Path ([IO.Path]::GetTempPath()) ('NotepadReplacerTests-' + [guid]::NewGuid().ToString('N'))
$baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
$oldKey = [Environment]::GetEnvironmentVariable('NOTEPAD_REPLACER_TEST_KEY')
$oldOutput = [Environment]::GetEnvironmentVariable('NOTEPAD_REPLACER_TEST_OUTPUT')
$key = $null
$shellName = 'NotepadReplacerTest-' + [guid]::NewGuid().ToString('N') + '.exe'
$shellKeyPath = 'Software\Microsoft\Windows\CurrentVersion\App Paths\' + $shellName

function Quote-Argument([string]$Value) {
    '"' + ([regex]::Replace($Value, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}
function Run-Case([string[]]$Arguments, [string[]]$Expected, [bool]$Success = $true,
                  [bool]$Shell = $false) {
    Write-Host "Checking Launcher arguments: $($Arguments -join ' | '); success expected: $Success"
    $output = Join-Path $directory ([guid]::NewGuid().ToString('N') + '.bin')
    $env:NOTEPAD_REPLACER_TEST_OUTPUT = $output
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = if ($Shell) { $shellName } else { $Launcher }
    $info.Arguments = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
    $info.UseShellExecute = $Shell
    $process = [Diagnostics.Process]::Start($info)
    try {
        if (-not $process.WaitForExit(5000)) { $process.Kill(); throw 'Launcher timed out.' }
        if (($process.ExitCode -eq 0) -ne $Success) { throw "Unexpected Launcher exit code: $($process.ExitCode)" }
    } finally { $process.Dispose() }
    if (-not $Success) {
        if (Test-Path -LiteralPath $output) { throw 'Editor ran despite expected failure.' }
        return
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $reader = $null
    do {
        try {
            $stream = [IO.File]::Open($output, 'Open', 'Read', 'None')
            $reader = [IO.BinaryReader]::new($stream)
        } catch [IO.IOException] { Start-Sleep -Milliseconds 25 }
    } until ($reader -or [DateTime]::UtcNow -gt $deadline)
    if (-not $reader) { throw 'Editor process did not produce an argument record.' }
    try {
        $count = $reader.ReadInt32() - 1
        if ($count -ne $Expected.Count) { throw "Argument count mismatch: $count" }
        for ($i = 0; $i -lt $count; $i++) {
            $length = $reader.ReadUInt32()
            $actual = [Text.Encoding]::Unicode.GetString($reader.ReadBytes($length * 2))
            if ($actual -cne $Expected[$i]) { throw "Forwarded argument mismatch at index $i" }
        }
    } finally { $reader.Dispose() }
}

try {
    New-Item -ItemType Directory -Path $directory | Out-Null
    $key = $baseKey.CreateSubKey("$testRoot\Software\NotepadReplacer")
    $env:NOTEPAD_REPLACER_TEST_KEY = $testRoot
    $key.SetValue('TargetPath', $Editor, [Microsoft.Win32.RegistryValueKind]::String)
    $shellKey = $baseKey.CreateSubKey($shellKeyPath)
    try { $shellKey.SetValue('', $Launcher.Replace('/', '\'), [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $shellKey.Dispose() }
    Run-Case @() @()
    Run-Case @('file with spaces.txt') @('file with spaces.txt')
    $documents = @('C:\folder with spaces\one.txt', 'quote"and\slash.txt', 'C:\trailing space\')
    Run-Case $documents $documents
    Run-Case @($Editor, 'C:\Windows\System32\notepad.exe', 'file with spaces.txt') @('file with spaces.txt')
    Run-Case @($Editor) @()
    Run-Case @() @() $true $true
    Run-Case @('C:\folder with spaces\file.txt') @('C:\folder with spaces\file.txt') $true $true
    $key.DeleteValue('TargetPath')
    Run-Case @() @() $false
    $key.SetValue('TargetPath', (Join-Path $directory 'deleted.exe'))
    Run-Case @('file.txt') @() $false
    $invalid = Join-Path $directory 'invalid.exe'
    [IO.File]::WriteAllText($invalid, 'not an executable')
    $key.SetValue('TargetPath', $invalid)
    Run-Case @() @() $false
    Write-Host 'Launcher process tests passed.'
} finally {
    if ($key) { $key.Dispose() }
    $baseKey.DeleteSubKeyTree($testRoot, $false)
    $baseKey.DeleteSubKeyTree($shellKeyPath, $false)
    $baseKey.Dispose()
    [Environment]::SetEnvironmentVariable('NOTEPAD_REPLACER_TEST_KEY', $oldKey)
    [Environment]::SetEnvironmentVariable('NOTEPAD_REPLACER_TEST_OUTPUT', $oldOutput)
    if (Test-Path -LiteralPath $directory) {
        $resolved = [IO.Path]::GetFullPath($directory)
        $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolved.StartsWith($temporaryRoot + 'NotepadReplacerTests-', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to delete a directory outside the test temporary directory.'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
