param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'Release',
    [switch]$DynamicRuntime
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = $PSScriptRoot
$generator = 'Visual Studio 17 2022'
$staticRuntime = if ($DynamicRuntime) { 'OFF' } else { 'ON' }

function Find-CMake {
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $installations = & $vswhere -products * -version '[17.0,18.0)' -property installationPath
        foreach ($installation in $installations) {
            $candidate = Join-Path $installation 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }

    throw 'CMake was not found. Install CMake 3.21+ or the CMake component included with Visual Studio 2022.'
}

function Invoke-CMake([string[]]$Arguments) {
    & $script:cmake @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "CMake failed with exit code $LASTEXITCODE."
    }
}

$cmake = Find-CMake
$distDirectory = Join-Path $root 'dist'
$x64BuildDirectory = Join-Path $distDirectory 'x64'
$x86BuildDirectory = Join-Path $distDirectory 'x86'

Invoke-CMake @(
    '-S', $root,
    '-B', $x64BuildDirectory,
    '-G', $generator,
    '-A', 'x64',
    "-DNOTEPADREPLACER_STATIC_CRT=$staticRuntime",
    '-DNOTEPADREPLACER_BUILD_CONTEXT_MENU=ON'
)
Invoke-CMake @(
    '--build', $x64BuildDirectory,
    '--config', $Configuration,
    '--target', 'NotepadReplacerLauncher', 'NotepadReplacerContextMenu'
)

Invoke-CMake @(
    '-S', $root,
    '-B', $x86BuildDirectory,
    '-G', $generator,
    '-A', 'Win32',
    "-DNOTEPADREPLACER_STATIC_CRT=$staticRuntime",
    '-DNOTEPADREPLACER_BUILD_CONTEXT_MENU=OFF'
)
Invoke-CMake @(
    '--build', $x86BuildDirectory,
    '--config', $Configuration,
    '--target', 'NotepadReplacerLauncher'
)

$outputs = @(
    (Join-Path $x64BuildDirectory "$Configuration\NotepadReplacerLauncher.exe"),
    (Join-Path $x64BuildDirectory "$Configuration\NotepadReplacerContextMenu.dll"),
    (Join-Path $x86BuildDirectory "$Configuration\NotepadReplacerLauncher.exe")
)
foreach ($output in $outputs) {
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw "Expected build output was not created: $output"
    }
    Write-Host "Built: $output"
}
