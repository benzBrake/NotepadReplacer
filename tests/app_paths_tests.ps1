$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\installer\AppPathsRegistry.ps1')

$testRoot = 'Software\NotepadReplacerTests\' + [guid]::NewGuid().ToString('N')
$baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
$entry = "$testRoot\AppPaths\notepad.exe"
$config = "$testRoot\Config"
$launcher = 'C:\Program Files\NotepadReplacer\Launcher.exe'
$messages = [System.Collections.Generic.List[string]]::new()

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Act([string]$Action, [string]$Path = $launcher) {
    Invoke-AppPathsAction -Action $Action -BaseKey $baseKey -AppPathsSubKey $entry `
        -ConfigSubKey $config -LauncherPath $Path -WriteLog { param($Message) $messages.Add($Message) }
}
function Expect-Failure([scriptblock]$Operation) {
    $failed = $false
    try { & $Operation } catch { $failed = $true }
    Assert $failed 'Expected an explicit failure.'
}
function Reset-Fixture {
    $baseKey.DeleteSubKeyTree($testRoot, $false)
    $messages.Clear()
}
function Set-Default([string]$Data, [Microsoft.Win32.RegistryValueKind]$Kind = 'String') {
    $key = $baseKey.CreateSubKey($entry)
    try { $key.SetValue('', $Data, $Kind) } finally { $key.Dispose() }
}
function Assert-NoRecovery {
    foreach ($name in @('AppPathsBackup', 'AppPathsTransaction')) {
        $key = $baseKey.OpenSubKey("$config\$name")
        try { Assert ($null -eq $key) "Recovery key remains: $name" } finally { if ($key) { $key.Dispose() } }
    }
}

try {
    foreach ($original in @(
        @{ Exists = 0; Kind = 'String'; Data = '' },
        @{ Exists = 1; Kind = 'String'; Data = '' },
        @{ Exists = 1; Kind = 'String'; Data = 'C:\Original Editor\editor.exe' },
        @{ Exists = 1; Kind = 'ExpandString'; Data = '%ProgramFiles%\Editor\editor.exe' }
    )) {
        Reset-Fixture
        if ($original.Exists) { Set-Default $original.Data $original.Kind }
        $key = $baseKey.CreateSubKey($entry)
        $key.SetValue('Path', 'C:\Preserve', [Microsoft.Win32.RegistryValueKind]::String)
        $child = $key.CreateSubKey('PreserveChild')
        $child.Dispose()
        $key.Dispose()
        Act Install
        Assert (Test-AppPathsOwner (Read-AppPathsValue $baseKey $entry) $launcher) 'Registration did not point to Launcher.'
        Act Commit
        Act Install
        Act Commit
        Act Install 'C:\New Install\Launcher.exe'
        Act Rollback
        Assert (Test-AppPathsOwner (Read-AppPathsValue $baseKey $entry) $launcher) 'Upgrade rollback did not restore prior Launcher.'
        Act Install 'C:\New Install\Launcher.exe'
        Act Commit
        Act Uninstall
        $actual = Read-AppPathsValue $baseKey $entry
        Assert ($actual.Exists -eq $original.Exists -and $actual.Kind -eq $original.Kind -and
            $actual.Data -ceq $original.Data) 'Original value or type was not restored.'
        $key = $baseKey.OpenSubKey($entry)
        try {
            Assert ($key.GetValue('Path') -eq 'C:\Preserve' -and $key.SubKeyCount -eq 1) 'Other registry content changed.'
        } finally { $key.Dispose() }
        Assert-NoRecovery
    }

    Reset-Fixture
    Act Install
    Act Rollback
    Assert ($null -eq $baseKey.OpenSubKey($entry)) 'Empty App Paths key was not removed.'
    Assert-NoRecovery

    Reset-Fixture
    Set-Default 'original'
    Act Install
    Set-Default 'external'
    Expect-Failure { Act Commit }
    Act Rollback
    Assert ((Read-AppPathsValue $baseKey $entry).Data -eq 'external') 'Rollback overwrote an external edit.'
    Assert-NoRecovery

    Reset-Fixture
    Act Install
    Act Commit
    Set-Default 'external'
    Act Uninstall
    Assert ((Read-AppPathsValue $baseKey $entry).Data -eq 'external') 'Uninstall overwrote an external edit.'
    Assert ($messages -match 'externally') 'External edit was not logged.'

    Reset-Fixture
    Act Install
    Act Commit
    $key = $baseKey.OpenSubKey($entry, $true)
    $key.SetValue('', 7, [Microsoft.Win32.RegistryValueKind]::DWord)
    $key.Dispose()
    Act Uninstall
    $key = $baseKey.OpenSubKey($entry)
    try { Assert ($key.GetValueKind('') -eq 'DWord' -and $key.GetValue('') -eq 7) 'External value type was overwritten.' }
    finally { $key.Dispose() }

    Reset-Fixture
    $key = $baseKey.CreateSubKey($entry)
    $key.SetValue('', 7, [Microsoft.Win32.RegistryValueKind]::DWord)
    $key.Dispose()
    Expect-Failure { Act Install }
    Assert-NoRecovery

    Reset-Fixture
    Act Install
    Act Commit
    $key = $baseKey.OpenSubKey("$config\AppPathsBackup", $true)
    $key.DeleteValue('Data')
    $key.Dispose()
    Expect-Failure { Act Uninstall }
    Expect-Failure { Act Install }
    Assert (Test-AppPathsOwner (Read-AppPathsValue $baseKey $entry) $launcher) 'Corrupt backup changed App Paths.'

    # Inject storage failures at the restoration boundary while retaining real registry state.
    Reset-Fixture
    Set-Default 'original'
    Act Install
    $restoreFunction = ${function:Restore-AppPathsValue}
    try {
        function Restore-AppPathsValue { throw [UnauthorizedAccessException]::new('Injected registry write failure.') }
        Expect-Failure { Act Rollback }
    } finally { ${function:Restore-AppPathsValue} = $restoreFunction }
    $key = $baseKey.OpenSubKey("$config\AppPathsTransaction")
    Assert ($null -ne $key) 'Recovery data was lost after restore failure.'
    $key.Dispose()
    Act Rollback
    Assert ((Read-AppPathsValue $baseKey $entry).Data -eq 'original') 'Recovery retry failed.'
    Assert-NoRecovery

    Reset-Fixture
    Set-Default 'original'
    try {
        function Restore-AppPathsValue { throw [UnauthorizedAccessException]::new('Injected registry write failure.') }
        Expect-Failure { Act Install }
    } finally { ${function:Restore-AppPathsValue} = $restoreFunction }
    Act Rollback
    Assert ((Read-AppPathsValue $baseKey $entry).Data -eq 'original') 'Failed registration changed original value.'
    Assert-NoRecovery

    Reset-Fixture
    Act Install
    Act Commit
    try {
        function Restore-AppPathsValue { throw [UnauthorizedAccessException]::new('Injected registry write failure.') }
        Expect-Failure { Act Uninstall }
    } finally { ${function:Restore-AppPathsValue} = $restoreFunction }
    $key = $baseKey.OpenSubKey("$config\AppPathsBackup")
    Assert ($null -ne $key) 'Original backup was lost after uninstall restore failure.'
    $key.Dispose()
    Act Uninstall
    Assert-NoRecovery

    Reset-Fixture
    Set-Default $launcher
    Expect-Failure { Act Install }
    Expect-Failure { Act Uninstall }
    Write-Host 'App Paths registry tests passed.'
} finally {
    $baseKey.DeleteSubKeyTree($testRoot, $false)
    $baseKey.Dispose()
}
