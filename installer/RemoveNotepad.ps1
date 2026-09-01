$ErrorActionPreference = 'Stop'

function Remove-NotepadPackage {
    $appName = 'Microsoft.WindowsNotepad'
    $removed = $false

    $package = Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue
    foreach ($item in @($package)) {
        if ($item -and $item.PackageFullName) {
            Remove-AppxPackage -Package $item.PackageFullName -ErrorAction Stop
            $removed = $true
        }
    }

    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $appName }
    foreach ($item in @($provisioned)) {
        if ($item -and $item.PackageName) {
            Remove-AppxProvisionedPackage -Online -PackageName $item.PackageName -ErrorAction Stop | Out-Null
            $removed = $true
        }
    }

    if ($removed) {
        Write-Output 'Microsoft Store Notepad package(s) removed.'
    } else {
        Write-Output 'Microsoft Store Notepad package not found; continuing.'
    }
}

try {
    Remove-NotepadPackage
    exit 0
} catch {
    Write-Error $_
    exit 1
}
