param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'Release',
    [switch]$DynamicRuntime,
    [string]$CMakeGenerator = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = $PSScriptRoot
$staticRuntime = if ($DynamicRuntime) { 'OFF' } else { 'ON' }

function Find-VsWhere {
    $command = Get-Command vswhere.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }

    throw 'vswhere was not found. Install Visual Studio with the Desktop development with C++ workload.'
}

function Find-CMake {
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $vswhere = Find-VsWhere
    $installations = & $vswhere -products * -property installationPath
    foreach ($installation in $installations) {
        $candidate = Join-Path $installation 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    throw 'CMake was not found. Install CMake 3.21+ or the CMake component included with Visual Studio.'
}

function Find-CMakeGenerator([string]$CMakePath) {
    $vswhere = Find-VsWhere
    $json = & $vswhere `
        -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -format json `
        -utf8
    if ($LASTEXITCODE -ne 0) {
        throw "vswhere failed with exit code $LASTEXITCODE."
    }

    $installations = @($json | ConvertFrom-Json) |
        Sort-Object { [version]$_.installationVersion } -Descending
    if (-not $installations) {
        throw 'Visual Studio with the Desktop development with C++ workload was not found.'
    }

    $cmakeHelp = (& $CMakePath --help) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "CMake failed with exit code $LASTEXITCODE while listing generators."
    }

    $generatorPattern = '(?m)^\s*\*?\s*(?<generator>Visual Studio (?<major>\d+) \d{4})\s+='
    $generatorsByMajorVersion = @{}
    foreach ($match in [regex]::Matches($cmakeHelp, $generatorPattern)) {
        $generatorsByMajorVersion[[int]$match.Groups['major'].Value] = $match.Groups['generator'].Value
    }

    foreach ($installation in $installations) {
        $majorVersion = ([version]$installation.installationVersion).Major
        if ($generatorsByMajorVersion.ContainsKey($majorVersion)) {
            return $generatorsByMajorVersion[$majorVersion]
        }
    }

    $installedVersions = $installations |
        ForEach-Object { $_.catalog.productDisplayVersion } |
        Where-Object { $_ }
    throw "CMake does not support an installed Visual Studio version: $($installedVersions -join ', ')."
}

function Invoke-CMake([string[]]$Arguments) {
    & $script:cmake @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "CMake failed with exit code $LASTEXITCODE."
    }
}

$cmake = Find-CMake
if (-not $CMakeGenerator) {
    $CMakeGenerator = Find-CMakeGenerator $cmake
}
Write-Host "Using CMake generator: $CMakeGenerator"

$distDirectory = Join-Path $root 'dist'
$x64BuildDirectory = Join-Path $distDirectory 'x64'
$x86BuildDirectory = Join-Path $distDirectory 'x86'

Invoke-CMake @(
    '-S', $root,
    '-B', $x64BuildDirectory,
    '-G', $CMakeGenerator,
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
    '-G', $CMakeGenerator,
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
