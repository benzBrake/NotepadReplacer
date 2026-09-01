[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$InstallDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$packageName = 'NotepadReplacer.Sparse'
$payloadDirectory = Join-Path $InstallDirectory 'context-menu'
$packagePath = Join-Path $payloadDirectory 'NotepadReplacer.msix'
$certificatePath = Join-Path $payloadDirectory 'NotepadReplacer.cer'
$logDirectory = Join-Path $env:ProgramData 'NotepadReplacer'
$logPath = Join-Path $logDirectory 'context-menu.log'

New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
if ($Action -eq 'Install') {
    Set-Content -LiteralPath $logPath -Value $null -Encoding utf8
}

function Write-Log([string]$Message) {
    ('{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f (Get-Date), $Message) |
        Out-File -LiteralPath $logPath -Append -Encoding utf8
}

function Remove-Package {
    Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log "Removing package $($_.PackageFullName)"
        Remove-AppxPackage -Package $_.PackageFullName -ErrorAction Stop
    }
}

try {
    Write-Log "$Action started"

    if ($Action -eq 'Install') {
        if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
            throw "Context-menu package not found: $packagePath"
        }
        if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) {
            throw "Package certificate not found: $certificatePath"
        }

        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
        $trustedCertificate = Get-Item -LiteralPath "Cert:\LocalMachine\TrustedPeople\$($certificate.Thumbprint)" -ErrorAction SilentlyContinue
        if (-not $trustedCertificate) {
            Write-Log "Trusting package certificate $($certificate.Thumbprint)"
            Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
        }

        Remove-Package
        Write-Log "Installing signed package $packagePath"
        Add-AppxPackage -Path $packagePath -ForceApplicationShutdown -ErrorAction Stop

        $installed = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue
        if (-not $installed) {
            throw 'Add-AppxPackage returned without registering the context-menu package.'
        }
        Write-Log "Installed package $($installed.PackageFullName)"
    } else {
        Remove-Package

        if (Test-Path -LiteralPath $certificatePath -PathType Leaf) {
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
            $trustedCertificatePath = "Cert:\LocalMachine\TrustedPeople\$($certificate.Thumbprint)"
            if (Test-Path -LiteralPath $trustedCertificatePath) {
                Write-Log "Removing package certificate $($certificate.Thumbprint)"
                Remove-Item -LiteralPath $trustedCertificatePath -Force
            }
        }
    }

    Write-Log "$Action completed"
} catch {
    Write-Log ("$Action failed: " + ($_ | Out-String).Trim())
    throw
}
