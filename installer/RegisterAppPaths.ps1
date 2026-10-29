[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Commit', 'Rollback', 'Uninstall')][string]$Action,
    [Parameter(Mandatory = $true)][string]$LauncherPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$logPath = Join-Path $env:ProgramData 'NotepadReplacer\app-paths.log'
$baseKey = $null

try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null
    function Write-Log([string]$Message) {
        ('{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f (Get-Date), $Message) |
            Out-File -LiteralPath $logPath -Append -Encoding utf8
    }
    Write-Log "$Action started."
    . (Join-Path $PSScriptRoot 'AppPathsRegistry.ps1')
    if (-not [System.IO.Path]::IsPathRooted($LauncherPath) -or
        [System.IO.Path]::GetExtension($LauncherPath) -ne '.exe') {
        throw 'LauncherPath must be an absolute executable path.'
    }
    if ($Action -eq 'Install' -and -not (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) {
        throw 'The Launcher executable is missing.'
    }
    $view = if ([Environment]::Is64BitOperatingSystem) {
        [Microsoft.Win32.RegistryView]::Registry64
    } else { [Microsoft.Win32.RegistryView]::Registry32 }
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
    Invoke-AppPathsAction -Action $Action -BaseKey $baseKey -LauncherPath $LauncherPath `
        -AppPathsSubKey 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\notepad.exe' `
        -ConfigSubKey 'SOFTWARE\NotepadReplacer' -WriteLog ${function:Write-Log}
} catch {
    $failure = $_
    try { Write-Log ($failure.Exception.ToString()) } catch { Write-Warning 'Could not write the App Paths error log.' }
    Write-Error -ErrorRecord $failure -ErrorAction Continue
    exit 1
} finally {
    if ($baseKey) { $baseKey.Dispose() }
}
