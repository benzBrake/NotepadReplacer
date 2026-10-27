Set-StrictMode -Version 2.0

function Read-AppPathsValue([Microsoft.Win32.RegistryKey]$BaseKey, [string]$SubKey,
                            [bool]$AllowUnsupported = $false) {
    $key = $BaseKey.OpenSubKey($SubKey)
    try {
        if (-not $key -or $key.GetValueNames() -notcontains '') {
            return @{ Exists = 0; Kind = 'String'; Data = '' }
        }
        $kind = $key.GetValueKind('')
        if (-not $AllowUnsupported -and $kind -notin @([Microsoft.Win32.RegistryValueKind]::String,
                          [Microsoft.Win32.RegistryValueKind]::ExpandString)) {
            throw "Unsupported App Paths default value type: $kind"
        }
        return @{ Exists = 1; Kind = $kind.ToString();
            Data = $key.GetValue('', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    } finally {
        if ($key) { $key.Dispose() }
    }
}

function Read-AppPathsField([Microsoft.Win32.RegistryKey]$Key, [string]$Name,
                            [Microsoft.Win32.RegistryValueKind]$Kind) {
    if ($Key.GetValueNames() -notcontains $Name -or $Key.GetValueKind($Name) -ne $Kind) {
        throw "Missing or invalid recovery field: $($Key.Name)\$Name"
    }
    return $Key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}

function Read-AppPathsSnapshot([Microsoft.Win32.RegistryKey]$Key) {
    $version = Read-AppPathsField $Key 'Version' DWord
    $exists = Read-AppPathsField $Key 'Exists' DWord
    $kind = Read-AppPathsField $Key 'Kind' String
    $data = Read-AppPathsField $Key 'Data' String
    if ($version -ne 1 -or $exists -notin @(0, 1) -or $kind -notin @('String', 'ExpandString')) {
        throw "Invalid recovery snapshot: $($Key.Name)"
    }
    return @{ Exists = $exists; Kind = $kind; Data = $data }
}

function Write-AppPathsSnapshot([Microsoft.Win32.RegistryKey]$Key, [hashtable]$Snapshot) {
    $Key.SetValue('Exists', $Snapshot.Exists, [Microsoft.Win32.RegistryValueKind]::DWord)
    $Key.SetValue('Kind', $Snapshot.Kind, [Microsoft.Win32.RegistryValueKind]::String)
    $Key.SetValue('Data', $Snapshot.Data, [Microsoft.Win32.RegistryValueKind]::String)
}

function Restore-AppPathsValue([Microsoft.Win32.RegistryKey]$BaseKey, [string]$SubKey,
                               [hashtable]$Snapshot) {
    if ($Snapshot.Exists) {
        $key = $BaseKey.CreateSubKey($SubKey)
        try {
            $key.SetValue('', $Snapshot.Data, [Microsoft.Win32.RegistryValueKind]$Snapshot.Kind)
            $key.Flush()
        } finally { $key.Dispose() }
    } else {
        $key = $BaseKey.OpenSubKey($SubKey, $true)
        if (-not $key) { return }
        try {
            $key.DeleteValue('', $false)
            $key.Flush()
            $empty = $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
        } finally { $key.Dispose() }
        if ($empty) { $BaseKey.DeleteSubKey($SubKey, $false) }
    }
}

function Test-AppPathsOwner([hashtable]$Value, [string]$LauncherPath) {
    return $Value.Exists -eq 1 -and $Value.Kind -eq 'String' -and
        [string]::Equals($Value.Data, $LauncherPath, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-AppPathsAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Install', 'Commit', 'Rollback', 'Uninstall')][string]$Action,
        [Parameter(Mandatory = $true)][Microsoft.Win32.RegistryKey]$BaseKey,
        [Parameter(Mandatory = $true)][string]$AppPathsSubKey,
        [Parameter(Mandatory = $true)][string]$ConfigSubKey,
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [scriptblock]$WriteLog = { param($Message) }
    )

    $backupPath = "$ConfigSubKey\AppPathsBackup"
    $transactionPath = "$ConfigSubKey\AppPathsTransaction"
    $backup = $BaseKey.OpenSubKey($backupPath, $true)
    $transaction = $BaseKey.OpenSubKey($transactionPath, $true)
    try {
        if ($Action -eq 'Install') {
            if ($transaction) { throw 'An unfinished App Paths transaction exists. Run Rollback before retrying.' }
            $before = Read-AppPathsValue $BaseKey $AppPathsSubKey
            $previousPath = ''
            if ($backup) {
                $null = Read-AppPathsSnapshot $backup
                $previousPath = Read-AppPathsField $backup 'InstalledPath' String
                if (-not $previousPath) { throw 'The saved Launcher path is empty.' }
            } elseif (Test-AppPathsOwner $before $LauncherPath) {
                throw 'App Paths already points to this Launcher, but its original-value backup is missing.'
            }

            # Persist the rollback state before changing the shared Shell entry.
            $transaction = $BaseKey.CreateSubKey($transactionPath)
            Write-AppPathsSnapshot $transaction $before
            $transaction.SetValue('HadBackup', [int][bool]$backup, [Microsoft.Win32.RegistryValueKind]::DWord)
            $transaction.SetValue('PreviousInstalledPath', $previousPath, [Microsoft.Win32.RegistryValueKind]::String)
            $transaction.SetValue('NewInstalledPath', $LauncherPath, [Microsoft.Win32.RegistryValueKind]::String)
            $transaction.SetValue('Version', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            $transaction.Flush()

            if (-not $backup) {
                $backup = $BaseKey.CreateSubKey($backupPath)
                Write-AppPathsSnapshot $backup $before
                $backup.SetValue('InstalledPath', $LauncherPath, [Microsoft.Win32.RegistryValueKind]::String)
                $backup.SetValue('Version', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
                $backup.Flush()
            }
            Restore-AppPathsValue $BaseKey $AppPathsSubKey @{ Exists = 1; Kind = 'String'; Data = $LauncherPath }
            & $WriteLog 'App Paths registered; rollback state retained until Commit.'
        } elseif ($Action -eq 'Commit') {
            if (-not $transaction -or -not $backup) { throw 'No complete App Paths transaction to commit.' }
            $null = Read-AppPathsSnapshot $transaction
            $null = Read-AppPathsSnapshot $backup
            $newPath = Read-AppPathsField $transaction 'NewInstalledPath' String
            if (-not (Test-AppPathsOwner (Read-AppPathsValue $BaseKey $AppPathsSubKey $true) $newPath)) {
                throw 'App Paths changed before Commit; the recovery state has been retained.'
            }
            $backup.SetValue('InstalledPath', $newPath, [Microsoft.Win32.RegistryValueKind]::String)
            $backup.Flush()
            $transaction.Dispose()
            $transaction = $null
            & $WriteLog 'App Paths transaction committed.'
            $BaseKey.DeleteSubKeyTree($transactionPath)
        } elseif ($Action -eq 'Rollback') {
            if (-not $transaction) { return }
            $before = Read-AppPathsSnapshot $transaction
            $hadBackup = Read-AppPathsField $transaction 'HadBackup' DWord
            $previousPath = Read-AppPathsField $transaction 'PreviousInstalledPath' String
            $newPath = Read-AppPathsField $transaction 'NewInstalledPath' String
            if ($hadBackup -notin @(0, 1) -or -not $newPath -or ($hadBackup -and -not $previousPath)) {
                throw 'Invalid App Paths transaction metadata.'
            }
            if ($hadBackup -and -not $backup) { throw 'The original App Paths backup is missing.' }
            if ($hadBackup) { $null = Read-AppPathsSnapshot $backup }
            if (Test-AppPathsOwner (Read-AppPathsValue $BaseKey $AppPathsSubKey $true) $newPath) {
                Restore-AppPathsValue $BaseKey $AppPathsSubKey $before
                & $WriteLog 'App Paths restored to its state before this installation.'
            } else {
                & $WriteLog 'App Paths does not point to this transaction; its current value was preserved.'
            }
            if ($backup) {
                if ($hadBackup) {
                    $backup.SetValue('InstalledPath', $previousPath, [Microsoft.Win32.RegistryValueKind]::String)
                    $backup.Flush()
                }
                $backup.Dispose()
                $backup = $null
            }
            if (-not $hadBackup) { $BaseKey.DeleteSubKeyTree($backupPath, $false) }
            $transaction.Dispose()
            $transaction = $null
            $BaseKey.DeleteSubKeyTree($transactionPath)
        } else {
            if ($transaction) { throw 'An unfinished App Paths transaction exists. Run Rollback before uninstalling.' }
            if (-not $backup) {
                if (Test-AppPathsOwner (Read-AppPathsValue $BaseKey $AppPathsSubKey $true) $LauncherPath) {
                    throw 'App Paths still points to this Launcher, but its original-value backup is missing.'
                }
                return
            }
            $original = Read-AppPathsSnapshot $backup
            $installedPath = Read-AppPathsField $backup 'InstalledPath' String
            if (-not $installedPath) { throw 'The saved Launcher path is empty.' }
            if (Test-AppPathsOwner (Read-AppPathsValue $BaseKey $AppPathsSubKey $true) $installedPath) {
                Restore-AppPathsValue $BaseKey $AppPathsSubKey $original
                & $WriteLog 'Original App Paths default value restored.'
            } else {
                & $WriteLog 'App Paths was changed externally; its current value was preserved.'
            }
            $backup.Dispose()
            $backup = $null
            $BaseKey.DeleteSubKeyTree($backupPath)
        }
    } finally {
        if ($transaction) { $transaction.Dispose() }
        if ($backup) { $backup.Dispose() }
    }
}
