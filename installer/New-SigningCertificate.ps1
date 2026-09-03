param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) '.certificates')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$pfxPath = Join-Path $OutputDirectory 'NotepadReplacer.pfx'
$passwordPath = Join-Path $OutputDirectory 'NotepadReplacer.password'
$base64Path = Join-Path $OutputDirectory 'NotepadReplacer.pfx.base64'
$outputs = @($pfxPath, $passwordPath, $base64Path)

$existing = $outputs | Where-Object { Test-Path -LiteralPath $_ }
if ($existing) {
    throw "Refusing to overwrite existing signing material: $($existing -join ', ')"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$passwordBytes = New-Object byte[] 32
$random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $random.GetBytes($passwordBytes)
} finally {
    $random.Dispose()
}
$password = [Convert]::ToBase64String($passwordBytes)
$securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force

$certificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject 'CN=Notepad Replacer' `
    -FriendlyName 'Notepad Replacer Package Signing' `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -KeyExportPolicy Exportable `
    -HashAlgorithm SHA256 `
    -KeyUsage DigitalSignature `
    -TextExtension @('2.5.29.19={text}false', '2.5.29.37={text}1.3.6.1.5.5.7.3.3') `
    -NotAfter (Get-Date).AddYears(5)

try {
    Export-PfxCertificate `
        -Cert $certificate `
        -FilePath $pfxPath `
        -Password $securePassword `
        -ChainOption EndEntityCertOnly | Out-Null

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($passwordPath, $password, $utf8WithoutBom)
    $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($pfxPath))
    [System.IO.File]::WriteAllText($base64Path, $base64, $utf8WithoutBom)
} catch {
    foreach ($output in $outputs) {
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
    }
    throw
} finally {
    $storePath = "Cert:\CurrentUser\My\$($certificate.Thumbprint)"
    if (Test-Path -LiteralPath $storePath) { Remove-Item -LiteralPath $storePath -Force }
}

Write-Host "Created PFX: $pfxPath"
Write-Host "Created local password: $passwordPath"
Write-Host "Created GitHub Secret value: $base64Path"
Write-Host "Certificate thumbprint: $($certificate.Thumbprint)"
Write-Host "Certificate expires: $($certificate.NotAfter.ToString('u'))"
