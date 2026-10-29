<#
.SYNOPSIS
Build Windows components in WSLC, run tests, and create the signed installer.
.DESCRIPTION
C++ compilation, MSIX signing, and Inno Setup packaging run in Linux containers.
No Windows SDK or local Inno Setup installation is required. A signing certificate is
created automatically on the first run if no local or environment certificate
is configured. Use -SkipInstaller to build only the program components.
#>
param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'Release',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist\wslc'),
    [switch]$SkipTests,
    [switch]$SkipInstaller,
    [string]$InstallerOutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$wslc = Get-Command wslc.exe -ErrorAction Stop
$tar = Get-Command tar.exe -ErrorAction Stop

if (-not $SkipInstaller) {
    & (Join-Path $PSScriptRoot 'installer\Test-InstallerSource.ps1')
    $certificateDirectory = Join-Path $PSScriptRoot '.certificates'
    $pfxPath = Join-Path $certificateDirectory 'NotepadReplacer.pfx'
    $passwordPath = Join-Path $certificateDirectory 'NotepadReplacer.password'
    $hasLocalCertificate = Test-Path -LiteralPath $pfxPath -PathType Leaf
    $createCertificate = -not $hasLocalCertificate -and
        [string]::IsNullOrWhiteSpace($env:WINDOWS_CERTIFICATE)
    if ($hasLocalCertificate -and -not (Test-Path -LiteralPath $passwordPath -PathType Leaf)) {
        throw "The signing certificate password file is missing: $passwordPath. Restore it before packaging."
    }
    if (-not $hasLocalCertificate -and -not $createCertificate -and
        [string]::IsNullOrEmpty($env:WINDOWS_CERTIFICATE_PASSWORD)) {
        throw 'WINDOWS_CERTIFICATE_PASSWORD must be set when WINDOWS_CERTIFICATE is used.'
    }
    if ($createCertificate) {
        foreach ($name in @('NotepadReplacer.password', 'NotepadReplacer.pfx.base64')) {
            $existing = Join-Path $certificateDirectory $name
            if (Test-Path -LiteralPath $existing) {
                throw "Incomplete local signing material: $existing. Restore the matching PFX before packaging."
            }
        }
    }
    Write-Host 'Compilation, MSIX signing, and installer packaging will run in WSLC containers.'
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDirectory).Path
$archive = Join-Path $outputPath "artifacts-$([guid]::NewGuid().ToString('N')).tar"

try {
    # WSLC 3.0.3 cannot export type=local; export a tar archive instead.
    & $wslc.Source build -f (Join-Path $PSScriptRoot 'containers\windows-cross\Dockerfile') `
        --build-arg "CONFIGURATION=$Configuration" --progress plain `
        --output "type=tar,dest=$archive" $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw "WSLC build failed with exit code $LASTEXITCODE." }
    & $tar.Source -xf $archive -C $outputPath
    if ($LASTEXITCODE -ne 0) { throw "Extracting build output failed with exit code $LASTEXITCODE." }
} finally {
    if (Test-Path -LiteralPath $archive -PathType Leaf) {
        Remove-Item -LiteralPath $archive -Force
    }
}

foreach ($relativePath in @(
    "x64\$Configuration\NotepadReplacerLauncher.exe",
    "x64\$Configuration\NotepadReplacerContextMenu.dll",
    "x86\$Configuration\NotepadReplacerLauncher.exe"
)) {
    $path = Join-Path $outputPath $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing build output: $path" }
    Write-Host "Built: $path"
}

if (-not $SkipTests) {
    foreach ($architecture in @('x64', 'x86')) {
        $test = Join-Path $outputPath "$architecture\$Configuration\launcher_core_tests.exe"
        if (-not (Test-Path -LiteralPath $test -PathType Leaf)) { throw "Missing test executable: $test" }
        # The tests are Windows binaries; execute them on the Windows host.
        & $test
        if ($LASTEXITCODE -ne 0) { throw "$architecture tests failed with exit code $LASTEXITCODE." }
        Write-Host "Passed: $architecture launcher_core_tests"
    }
}

if (-not $SkipInstaller) {
    $packagingImage = 'notepadreplacer-packaging:local'
    Write-Host 'Preparing the WSLC packaging image (first build downloads Wine and packaging tools)...'
    & $wslc.Source build -f (Join-Path $PSScriptRoot 'containers\windows-cross\packaging.Dockerfile') `
        --progress plain -t $packagingImage $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw "Building the packaging image failed with exit code $LASTEXITCODE." }

    if ($createCertificate) {
        Write-Host 'Creating the first local signing certificate in .certificates...'
        $windowsPowerShell = Get-Command powershell.exe -ErrorAction Stop
        & $windowsPowerShell.Source -NoProfile -ExecutionPolicy Bypass -File `
            (Join-Path $PSScriptRoot 'installer\New-SigningCertificate.ps1')
        if ($LASTEXITCODE -ne 0) { throw "Creating the signing certificate failed with exit code $LASTEXITCODE." }
    }

    $installerOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallerOutputDirectory)
    New-Item -ItemType Directory -Force -Path $installerOutputPath | Out-Null
    $signingDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "NotepadReplacer-signing-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $signingDirectory | Out-Null
    $temporaryPfx = Join-Path $signingDirectory 'certificate.pfx'
    $temporaryPassword = Join-Path $signingDirectory 'password'
    try {
        if (Test-Path -LiteralPath $pfxPath -PathType Leaf) {
            Copy-Item -LiteralPath $pfxPath -Destination $temporaryPfx
            Copy-Item -LiteralPath $passwordPath -Destination $temporaryPassword
        } else {
            [System.IO.File]::WriteAllBytes($temporaryPfx, [Convert]::FromBase64String($env:WINDOWS_CERTIFICATE))
            [System.IO.File]::WriteAllText($temporaryPassword, $env:WINDOWS_CERTIFICATE_PASSWORD, [Text.UTF8Encoding]::new($false))
        }
        Write-Host 'Packaging and signing in WSLC (signing files are mounted read-only at runtime)...'
        & $wslc.Source run --rm --network none `
            --mount "type=bind,source=$PSScriptRoot,target=/source,readonly" `
            --mount "type=bind,source=$outputPath,target=/components,readonly" `
            --mount "type=bind,source=$signingDirectory,target=/signing,readonly" `
            --mount "type=bind,source=$installerOutputPath,target=/out" `
            $packagingImage $Configuration
        if ($LASTEXITCODE -ne 0) { throw "Installer packaging failed with exit code $LASTEXITCODE." }
    } finally {
        foreach ($temporaryFile in @($temporaryPfx, $temporaryPassword)) {
            if (Test-Path -LiteralPath $temporaryFile -PathType Leaf) {
                Remove-Item -LiteralPath $temporaryFile -Force
            }
        }
        Remove-Item -LiteralPath $signingDirectory -Force
    }
    $installer = Join-Path $installerOutputPath 'NotepadReplacerSetup.exe'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "Missing installer: $installer" }
    Write-Host "Built installer: $installer"
}
