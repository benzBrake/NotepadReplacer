$ErrorActionPreference = 'Stop'

function Assert-FileAssociationRegistration {
    $installerSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'NotepadReplacer.iss') -Raw
    $registrySection = [regex]::Match($installerSource, '(?ms)^\[Registry\]\s*\r?\n(?<entries>.*?)(?=^\[|\z)')
    if (-not $registrySection.Success) {
        throw 'The installer must register Launcher file associations in [Registry].'
    }
    $entries = @($registrySection.Groups['entries'].Value -split '\r?\n' |
        Where-Object { $_ -match '^\s*Root:' })
    $requirements = @(
        @{ Key = 'SOFTWARE\Classes\NotepadReplacer.TextFile'; Value = ''; Data = 'Notepad Replacer Launcher'; Flag = 'uninsdeletekey' },
        @{ Key = 'SOFTWARE\Classes\NotepadReplacer.TextFile\shell\open\command'; Value = ''; Data = '""{code:AssociationLauncherPath}"" ""%1""'; Flag = '' },
        @{ Key = 'SOFTWARE\Classes\Applications\{code:AssociationLauncherName}'; Value = 'FriendlyAppName'; Data = 'Notepad Replacer Launcher'; Flag = 'uninsdeletekey' },
        @{ Key = 'SOFTWARE\Classes\Applications\{code:AssociationLauncherName}\shell\open\command'; Value = ''; Data = '""{code:AssociationLauncherPath}"" ""%1""'; Flag = '' }
    )
    foreach ($requirement in $requirements) {
        $matching = @($entries | Where-Object {
            $_.Contains('Subkey: "' + $requirement.Key + '";') -and
            $_.Contains('ValueName: "' + $requirement.Value + '";') -and
            $_.Contains('ValueData: "' + $requirement.Data + '"') -and
            (-not $requirement.Flag -or $_ -match ('Flags:\s*[^;\r\n]*\b' + $requirement.Flag + '\b'))
        })
        if ($matching.Count -ne 1) {
            throw "Missing or ambiguous file association registration: $($requirement.Key)"
        }
    }
    $extensions = @('.txt', '.log', '.csv', '.md', '.rst', '.json', '.xml', '.yaml', '.yml',
                    '.ini', '.cfg', '.conf', '.ps1', '.bat', '.cmd', '.html', '.css', '.js')
    foreach ($extension in $extensions) {
        $key = 'SOFTWARE\Classes\' + $extension + '\OpenWithProgids'
        $matching = @($entries | Where-Object {
            $_.Contains('Subkey: "' + $key + '";') -and
            $_.Contains('ValueType: none;') -and
            $_.Contains('ValueName: "NotepadReplacer.TextFile";') -and
            $_ -match 'Flags:\s*[^;\r\n]*\buninsdeletevalue\b'
        })
        if ($matching.Count -ne 1) {
            throw "Missing or ambiguous Open With registration/uninstall cleanup: $extension"
        }
    }
    if ($installerSource -notmatch '(?m)^ChangesAssociations=yes\s*$') {
        throw 'The installer must refresh file associations with ChangesAssociations=yes.'
    }
    Write-Host 'Verified Launcher Open With registration, document commands, and uninstall cleanup.'
}

# Shared by the Windows and WSLC packaging entry points.
Assert-FileAssociationRegistration
