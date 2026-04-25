param(
    [string]$FriendlyMatch = "Zgmicro AUDIO",
    [string[]]$SupportedHardwareIds = @(),
    [int]$MinGainMilli = 0,
    [int]$MaxGainMilli = 1000,
    [switch]$InstallEqualizerApoIfMissing,
    [switch]$BuildService,
    [switch]$AutoSelectEqualizerApoDevice = $true,
    [switch]$RestartAudioAfterSetup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run from elevated PowerShell."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$serviceExe = Join-Path $repoRoot "build\Release\EqualizerVolumeBridgeSvc.exe"
$installSvcScript = Join-Path $PSScriptRoot "install-volume-mirror-service.ps1"
$eapoConfigDir = "C:\Program Files\EqualizerAPO\config"
$eapoConfigPath = Join-Path $eapoConfigDir "config.txt"

function Test-EqualizerApoInstalled {
    return (Test-Path $eapoConfigPath)
}

function Install-EqualizerApoWithWinget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw "Equalizer APO missing and winget is not available. Install Equalizer APO manually, then rerun this script."
    }

    Write-Host "Equalizer APO not found. Installing with winget..."
    & winget install --id EqualizerAPO.EqualizerAPO --accept-source-agreements --accept-package-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed (exit code $LASTEXITCODE). Install Equalizer APO manually, then rerun."
    }
}

function Get-EndpointGuidFromTargetDeviceId {
    param([string]$TargetDeviceId)
    if ($TargetDeviceId -match "\{([0-9a-fA-F\-]{36})\}$") {
        return $Matches[1].ToLowerInvariant()
    }
    return ""
}

function Enable-EqualizerApoForEndpoint {
    param([Parameter(Mandatory = $true)] [string]$EndpointGuid)

    $targetFxPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{$EndpointGuid}\FxProperties"
    if (-not (Test-Path $targetFxPath)) {
        throw "Target endpoint FxProperties path not found: $targetFxPath"
    }

    $targetFx = Get-ItemProperty -Path $targetFxPath -ErrorAction SilentlyContinue
    $sfxName = "{d04e05a6-594b-4fb6-a80d-01af5eed7d1d},5"
    $mfxName = "{d04e05a6-594b-4fb6-a80d-01af5eed7d1d},6"
    $efxName = "{d04e05a6-594b-4fb6-a80d-01af5eed7d1d},7"

    if ($null -ne $targetFx -and (
            -not [string]::IsNullOrWhiteSpace($targetFx.$sfxName) -or
            -not [string]::IsNullOrWhiteSpace($targetFx.$mfxName) -or
            -not [string]::IsNullOrWhiteSpace($targetFx.$efxName))) {
        Write-Host "Equalizer APO effects already present on target endpoint."
        return
    }

    $childAposRoot = "HKLM:\SOFTWARE\EqualizerAPO\Child APOs"
    $sourceGuid = ""
    if (Test-Path $childAposRoot) {
        $sourceGuid = Get-ChildItem $childAposRoot `
            | ForEach-Object { $_.PSChildName.Trim("{}").ToLowerInvariant() } `
            | Where-Object { $_ -ne $EndpointGuid } `
            | Select-Object -First 1
    }

    if ([string]::IsNullOrWhiteSpace($sourceGuid)) {
        Write-Warning "Could not find a source Equalizer APO endpoint to clone. You may need to open Equalizer APO Configurator once."
        return
    }

    $sourceFxPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{$sourceGuid}\FxProperties"
    $sourceFx = Get-ItemProperty -Path $sourceFxPath -ErrorAction SilentlyContinue
    if ($null -eq $sourceFx) {
        Write-Warning "Could not read source endpoint FxProperties for Equalizer APO cloning."
        return
    }

    foreach ($name in @($sfxName, $mfxName, $efxName)) {
        $value = $sourceFx.$name
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            New-ItemProperty -Path $targetFxPath -Name $name -PropertyType String -Value $value -Force | Out-Null
        }
    }

    $sourceChild = "HKLM\SOFTWARE\EqualizerAPO\Child APOs\{$sourceGuid}"
    $targetChild = "HKLM\SOFTWARE\EqualizerAPO\Child APOs\{$EndpointGuid}"
    & reg.exe copy $sourceChild $targetChild /s /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not clone Equalizer APO Child APO settings to target endpoint."
    }
}

if (-not (Test-EqualizerApoInstalled)) {
    if (-not $InstallEqualizerApoIfMissing) {
        throw "Equalizer APO is not installed. Re-run with -InstallEqualizerApoIfMissing or install Equalizer APO manually first."
    }
    Install-EqualizerApoWithWinget
}

if (-not (Test-EqualizerApoInstalled)) {
    throw "Equalizer APO still not detected after install attempt (missing $eapoConfigPath)."
}

if ($BuildService -or -not (Test-Path $serviceExe)) {
    Write-Host "Building EqualizerVolumeBridgeSvc..."
    Push-Location $repoRoot
    try {
        & cmake -S . -B build
        if ($LASTEXITCODE -ne 0) { throw "cmake configure failed." }
        & cmake --build build --config Release
        if ($LASTEXITCODE -ne 0) { throw "cmake build failed." }
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path $serviceExe)) {
    throw "Service binary not found at $serviceExe"
}

Write-Host "Installing service..."
& $installSvcScript `
    -BinaryPath $serviceExe `
    -FriendlyMatch $FriendlyMatch `
    -SupportedHardwareIds $SupportedHardwareIds `
    -MinGainMilli $MinGainMilli `
    -MaxGainMilli $MaxGainMilli

if ($AutoSelectEqualizerApoDevice) {
    $targetDeviceId = (Get-ItemProperty "HKLM:\SOFTWARE\EqualizerVolumeBridge\Device" -ErrorAction SilentlyContinue).TargetDeviceId
    $targetGuid = Get-EndpointGuidFromTargetDeviceId -TargetDeviceId $targetDeviceId
    if ([string]::IsNullOrWhiteSpace($targetGuid)) {
        Write-Warning "Could not parse endpoint GUID from TargetDeviceId. Skipping Equalizer APO auto-select."
    }
    else {
        Write-Host "Applying Equalizer APO endpoint selection for {$targetGuid}..."
        Enable-EqualizerApoForEndpoint -EndpointGuid $targetGuid
    }
}

if ($RestartAudioAfterSetup) {
    try {
        Write-Host "Restarting Windows audio service..."
        Restart-Service Audiosrv -Force
    }
    catch {
        Write-Warning ("Could not restart Audiosrv: {0}" -f $_.Exception.Message)
    }
}

Write-Host "Final verification:"
Get-Service EqualizerVolumeBridgeSvc | Format-List Name, Status, StartType
Get-ItemProperty "HKLM:\SOFTWARE\EqualizerVolumeBridge\Device" -ErrorAction SilentlyContinue `
    | Select-Object TargetDeviceId, VolumeScalar, Mute, FriendlyNameMatch `
    | Format-List

Write-Host ""
Write-Host "If this is a first-time Equalizer APO install, use -RestartAudioAfterSetup for immediate effect."
