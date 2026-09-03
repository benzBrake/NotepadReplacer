param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'Release',
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$SigningCertificatePath = '',
    [string]$SigningCertificatePasswordPath = ''
)

$ErrorActionPreference = 'Stop'
$certificateSubject = 'CN=Notepad Replacer'

$root = Split-Path -Parent $PSScriptRoot
$certificateDirectory = Join-Path $root '.certificates'
if (-not $SigningCertificatePath) {
    $SigningCertificatePath = Join-Path $certificateDirectory 'NotepadReplacer.pfx'
}
if (-not $SigningCertificatePasswordPath) {
    $SigningCertificatePasswordPath = Join-Path $certificateDirectory 'NotepadReplacer.password'
}
$distDirectory = Join-Path $root 'dist'
$x86 = Join-Path $distDirectory "x86\$Configuration\NotepadReplacerLauncher.exe"
$x64 = Join-Path $distDirectory "x64\$Configuration\NotepadReplacerLauncher.exe"
$contextMenu = Join-Path $distDirectory "x64\$Configuration\NotepadReplacerContextMenu.dll"
$manifest = Join-Path $PSScriptRoot 'AppxManifest.xml'
$logo = Join-Path $PSScriptRoot 'logo.png'
$packageBuildDirectory = Join-Path $distDirectory 'context-menu-package'
$packageContentDirectory = Join-Path $packageBuildDirectory 'content'
$packagePath = Join-Path $packageBuildDirectory 'NotepadReplacer.msix'
$certificatePath = Join-Path $packageBuildDirectory 'NotepadReplacer.cer'

if (-not (Test-Path -LiteralPath $x86)) { throw "Missing x86 launcher: $x86" }
if (-not (Test-Path -LiteralPath $x64)) { throw "Missing x64 launcher: $x64" }
if (-not (Test-Path -LiteralPath $contextMenu)) { throw "Missing x64 context-menu DLL: $contextMenu" }

function Find-WindowsSdkTool([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $kitsBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $versions = Get-ChildItem -LiteralPath $kitsBin -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending
    foreach ($version in $versions) {
        $candidate = Join-Path $version.FullName "x64\$Name"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw "$Name not found. Install the Windows 10/11 SDK before building the installer."
}

function Get-SigningCertificate {
    $temporaryPath = $null
    $certificate = $null
    try {
        if (Test-Path -LiteralPath $SigningCertificatePath -PathType Leaf) {
            if (-not (Test-Path -LiteralPath $SigningCertificatePasswordPath -PathType Leaf)) {
                throw "The local signing certificate password file is missing: $SigningCertificatePasswordPath"
            }
            $pfxPath = (Resolve-Path -LiteralPath $SigningCertificatePath).Path
            $password = (Get-Content -LiteralPath $SigningCertificatePasswordPath -Raw).TrimEnd("`r", "`n")
            if (-not $password) { throw 'The local signing certificate password is empty.' }
            Write-Host "Using local signing certificate: $pfxPath"
        } elseif (-not [string]::IsNullOrWhiteSpace($env:WINDOWS_CERTIFICATE)) {
            if ([string]::IsNullOrEmpty($env:WINDOWS_CERTIFICATE_PASSWORD)) {
                throw 'WINDOWS_CERTIFICATE_PASSWORD must be set when WINDOWS_CERTIFICATE is used.'
            }
            $temporaryPath = Join-Path ([System.IO.Path]::GetTempPath()) "NotepadReplacer-$([guid]::NewGuid().ToString('N')).pfx"
            try {
                $pfxBytes = [Convert]::FromBase64String($env:WINDOWS_CERTIFICATE)
            } catch {
                throw 'WINDOWS_CERTIFICATE is not valid Base64.'
            }
            [System.IO.File]::WriteAllBytes($temporaryPath, $pfxBytes)
            $pfxPath = $temporaryPath
            $password = $env:WINDOWS_CERTIFICATE_PASSWORD
            Write-Host 'Using signing certificate from environment variables.'
        } else {
            throw "No signing certificate was found. Create $SigningCertificatePath or set WINDOWS_CERTIFICATE and WINDOWS_CERTIFICATE_PASSWORD."
        }

        $keyStorageFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $pfxPath,
            $password,
            $keyStorageFlags
        )
        if ($certificate.Subject -ne $certificateSubject) {
            throw "The signing certificate subject must be '$certificateSubject'; got '$($certificate.Subject)'."
        }
        if (-not $certificate.HasPrivateKey) { throw 'The signing certificate has no private key.' }
        if ($certificate.NotAfter -le (Get-Date).AddDays(30)) {
            throw "The signing certificate expires too soon: $($certificate.NotAfter.ToString('u'))"
        }

        return [pscustomobject]@{
            Certificate = $certificate
            Password = $password
            PfxPath = $pfxPath
            TemporaryPath = $temporaryPath
        }
    } catch {
        if ($certificate) { $certificate.Dispose() }
        if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        throw
    }
}

$makeAppx = Find-WindowsSdkTool 'MakeAppx.exe'
$signTool = Find-WindowsSdkTool 'SignTool.exe'
$signing = Get-SigningCertificate

try {
    if (Test-Path -LiteralPath $packageBuildDirectory) {
        Remove-Item -LiteralPath $packageBuildDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $packageContentDirectory | Out-Null
    Copy-Item -LiteralPath $manifest, $logo, $contextMenu -Destination $packageContentDirectory
    Copy-Item -LiteralPath $x64 -Destination (Join-Path $packageContentDirectory 'NotepadReplacerLauncher-x64.exe')

    & $makeAppx pack /d $packageContentDirectory /p $packagePath /o
    if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed with exit code $LASTEXITCODE" }

    & $signTool sign /fd SHA256 /f $signing.PfxPath /p $signing.Password $packagePath
    if ($LASTEXITCODE -ne 0) { throw "SignTool failed with exit code $LASTEXITCODE" }

    $signature = Get-AuthenticodeSignature -LiteralPath $packagePath
    if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $signing.Certificate.Thumbprint) {
        throw 'The generated MSIX does not contain the expected signing certificate.'
    }

    $publicCertificate = $signing.Certificate.Export(
        [System.Security.Cryptography.X509Certificates.X509ContentType]::Cert
    )
    [System.IO.File]::WriteAllBytes($certificatePath, $publicCertificate)

    $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if (-not $iscc) {
        $candidates = @(
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
        )
        $isccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $isccPath) { throw 'ISCC.exe not found. Install Inno Setup 6 before building the installer.' }
    } else {
        $isccPath = $iscc.Source
    }

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    Push-Location $PSScriptRoot
    try {
        & $isccPath "/DBuildConfiguration=$Configuration" "/O$OutputDirectory" 'NotepadReplacer.iss'
        if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
} finally {
    $signing.Certificate.Dispose()
    if ($signing.TemporaryPath -and (Test-Path -LiteralPath $signing.TemporaryPath)) {
        Remove-Item -LiteralPath $signing.TemporaryPath -Force
    }
}
