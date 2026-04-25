param(
    [string]$ServiceName = "EqualizerVolumeBridgeSvc",
    [string]$FriendlyMatch = "Zgmicro AUDIO",
    [string]$HardwareIdMatch = "",
    [string[]]$SupportedHardwareIds = @(),
    [int]$MinGainMilli = 0,
    [int]$MaxGainMilli = 1000,
    [string]$BinaryPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BinaryPath)) {
    $candidates = @(
        (Join-Path $PSScriptRoot "..\build-vs\Release\EqualizerVolumeBridgeSvc.exe"),
        (Join-Path $PSScriptRoot "..\build\Release\EqualizerVolumeBridgeSvc.exe"),
        (Join-Path $PSScriptRoot "..\build\EqualizerVolumeBridgeSvc.exe")
    )
    $BinaryPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $BinaryPath -or -not (Test-Path $BinaryPath)) {
    throw "Binary not found. Build Release first and pass -BinaryPath if needed."
}

$escapedBinary = "`"$BinaryPath`" --friendly `"$FriendlyMatch`""
if (-not [string]::IsNullOrWhiteSpace($HardwareIdMatch)) {
    $escapedBinary += " --hwid-match `"$HardwareIdMatch`""
}

$regPath = "HKLM:\SOFTWARE\EqualizerVolumeBridge\Device"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

if ($SupportedHardwareIds.Count -gt 0) {
    $supported = ($SupportedHardwareIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ";"
    if (-not [string]::IsNullOrWhiteSpace($supported)) {
        New-ItemProperty -Path $regPath -Name "SupportedHardwareIds" -PropertyType String -Value $supported -Force | Out-Null
        if ([string]::IsNullOrWhiteSpace($HardwareIdMatch)) {
            $escapedBinary += " --hwid-match `"$supported`""
        }
    }
}

if ($MinGainMilli -lt 0) { $MinGainMilli = 0 }
if ($MaxGainMilli -lt 0) { $MaxGainMilli = 0 }
if ($MinGainMilli -gt 3000) { $MinGainMilli = 3000 }
if ($MaxGainMilli -gt 3000) { $MaxGainMilli = 3000 }
if ($MinGainMilli -gt $MaxGainMilli) {
    $tmp = $MinGainMilli
    $MinGainMilli = $MaxGainMilli
    $MaxGainMilli = $tmp
}

New-ItemProperty -Path $regPath -Name "MinGainMilli" -PropertyType DWord -Value $MinGainMilli -Force | Out-Null
New-ItemProperty -Path $regPath -Name "MaxGainMilli" -PropertyType DWord -Value $MaxGainMilli -Force | Out-Null

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 1
}

New-Service -Name $ServiceName -BinaryPathName $escapedBinary -DisplayName "Equalizer Volume Bridge Service" -Description "Mirrors endpoint master volume into registry and Equalizer APO preamp state." -StartupType Automatic | Out-Null
Start-Service -Name $ServiceName -ErrorAction Stop

$s = Get-Service -Name $ServiceName
if ($s.Status -ne "Running") {
    throw "Service did not reach Running state (Status=$($s.Status)). Check Application event log for EqualizerVolumeBridgeSvc."
}

Write-Host "Service installed and started: $ServiceName (Status=$($s.Status))"
Write-Host "Configured gain range: MinGainMilli=$MinGainMilli MaxGainMilli=$MaxGainMilli"
