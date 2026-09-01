param(
    [string]$Configuration = 'Release',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'output'),
    [string]$SigningThumbprint = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$x86 = Join-Path $root "build-win32\$Configuration\NotepadReplacerLauncher.exe"
$x64 = Join-Path $root "build\$Configuration\NotepadReplacerLauncher.exe"
$contextMenu = Join-Path $root "build\$Configuration\NotepadReplacerContextMenu.dll"
$manifest = Join-Path $PSScriptRoot 'AppxManifest.xml'
$logo = Join-Path $PSScriptRoot 'logo.png'
$packageBuildDirectory = Join-Path $root 'build\context-menu-package'
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

$makeAppx = Find-WindowsSdkTool 'MakeAppx.exe'
$signTool = Find-WindowsSdkTool 'SignTool.exe'

if ($SigningThumbprint) {
    $certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$SigningThumbprint" -ErrorAction SilentlyContinue
    $certificateStoreArguments = @('/s', 'My')
    if (-not $certificate) {
        $certificate = Get-Item -LiteralPath "Cert:\LocalMachine\My\$SigningThumbprint" -ErrorAction SilentlyContinue
        $certificateStoreArguments = @('/sm', '/s', 'My')
    }
    if (-not $certificate) { throw "Signing certificate not found: $SigningThumbprint" }
} else {
    $certificate = Get-ChildItem 'Cert:\CurrentUser\My' |
        Where-Object {
            $_.Subject -eq 'CN=Notepad Replacer' -and
            $_.FriendlyName -eq 'Notepad Replacer Package Signing' -and
            $_.HasPrivateKey -and
            $_.NotAfter -gt (Get-Date).AddDays(30)
        } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
    if (-not $certificate) {
        $certificate = New-SelfSignedCertificate `
            -Type Custom `
            -Subject 'CN=Notepad Replacer' `
            -FriendlyName 'Notepad Replacer Package Signing' `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -KeyAlgorithm RSA `
            -KeyLength 2048 `
            -HashAlgorithm SHA256 `
            -KeyUsage DigitalSignature `
            -TextExtension @('2.5.29.19={text}false', '2.5.29.37={text}1.3.6.1.5.5.7.3.3') `
            -NotAfter (Get-Date).AddYears(5)
    }
    $certificateStoreArguments = @('/s', 'My')
}

if ($certificate.Subject -ne 'CN=Notepad Replacer') {
    throw "The signing certificate subject must match the manifest publisher 'CN=Notepad Replacer'; got '$($certificate.Subject)'."
}
if (-not $certificate.HasPrivateKey) { throw 'The signing certificate has no private key.' }

if (Test-Path -LiteralPath $packageBuildDirectory) {
    Remove-Item -LiteralPath $packageBuildDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $packageContentDirectory | Out-Null
Copy-Item -LiteralPath $manifest, $logo, $contextMenu -Destination $packageContentDirectory
Copy-Item -LiteralPath $x64 -Destination (Join-Path $packageContentDirectory 'NotepadReplacerLauncher-x64.exe')

& $makeAppx pack /d $packageContentDirectory /p $packagePath /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed with exit code $LASTEXITCODE" }

$signArguments = @('sign', '/fd', 'SHA256') + $certificateStoreArguments + @('/sha1', $certificate.Thumbprint, $packagePath)
& $signTool @signArguments
if ($LASTEXITCODE -ne 0) { throw "SignTool failed with exit code $LASTEXITCODE" }

$signature = Get-AuthenticodeSignature -LiteralPath $packagePath
if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
    throw 'The generated MSIX does not contain the expected signing certificate.'
}

Export-Certificate -Cert $certificate -FilePath $certificatePath -Force | Out-Null

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
    & $isccPath "/O$OutputDirectory" 'NotepadReplacer.iss'
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
