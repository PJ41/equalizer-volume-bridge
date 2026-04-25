param(
    [string]$FriendlyMatch = "Zgmicro AUDIO"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-StringProp {
    param(
        [Parameter(Mandatory = $true)] [string]$InstanceId,
        [Parameter(Mandatory = $true)] [string]$KeyName
    )
    try {
        $v = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop
        if ($null -ne $v.Data) { return [string]$v.Data }
    } catch { }
    return ""
}

function Get-HardwareIds {
    param([Parameter(Mandatory = $true)] [string]$InstanceId)
    try {
        $v = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName "DEVPKEY_Device_HardwareIds" -ErrorAction Stop
        if ($v.Data -is [System.Array]) {
            return @($v.Data | ForEach-Object { [string]$_ })
        }
        if ($null -ne $v.Data) {
            return @([string]$v.Data)
        }
    } catch { }
    return @()
}

function Get-ParentInstanceId {
    param([Parameter(Mandatory = $true)] [string]$InstanceId)
    try {
        $v = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName "DEVPKEY_Device_Parent" -ErrorAction Stop
        if ($null -ne $v.Data) { return [string]$v.Data }
    } catch { }
    return ""
}

function Extract-VidPidFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    if ($Text -match "(VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4})") {
        return $Matches[1].ToUpperInvariant()
    }
    return ""
}

function Resolve-VidPidByWalkingParents {
    param([Parameter(Mandatory = $true)] [string]$StartInstanceId)

    $current = $StartInstanceId
    $visited = New-Object System.Collections.Generic.HashSet[string]
    $chain = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt 12; $i++) {
        if ([string]::IsNullOrWhiteSpace($current)) { break }
        if ($visited.Contains($current)) { break }
        [void]$visited.Add($current)
        [void]$chain.Add($current)

        $fromInstance = Extract-VidPidFromText -Text $current
        if (-not [string]::IsNullOrWhiteSpace($fromInstance)) {
            return @{
                VidPid = $fromInstance
                Chain = $chain
            }
        }

        $hwids = Get-HardwareIds -InstanceId $current
        foreach ($hwid in $hwids) {
            $fromHwid = Extract-VidPidFromText -Text $hwid
            if (-not [string]::IsNullOrWhiteSpace($fromHwid)) {
                return @{
                    VidPid = $fromHwid
                    Chain = $chain
                }
            }
        }

        $current = Get-ParentInstanceId -InstanceId $current
    }

    return @{
        VidPid = ""
        Chain = $chain
    }
}

$audioDevices = Get-PnpDevice -Class AudioEndpoint -Status OK -ErrorAction SilentlyContinue
if ($null -eq $audioDevices) {
    Write-Host "No audio endpoints found via Get-PnpDevice."
    exit 1
}

$matches = @()
foreach ($d in $audioDevices) {
    $friendly = Get-StringProp -InstanceId $d.InstanceId -KeyName "DEVPKEY_Device_FriendlyName"
    if ($friendly -like "*$FriendlyMatch*") {
        $hwids = Get-HardwareIds -InstanceId $d.InstanceId
        $vidPid = ($hwids | ForEach-Object { Extract-VidPidFromText -Text $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)

        $walk = Resolve-VidPidByWalkingParents -StartInstanceId $d.InstanceId
        if ([string]::IsNullOrWhiteSpace($vidPid) -and -not [string]::IsNullOrWhiteSpace($walk.VidPid)) {
            $vidPid = $walk.VidPid
        }

        if ([string]::IsNullOrWhiteSpace($vidPid)) {
            $vidPid = "not found"
        }

        $matches += [PSCustomObject]@{
            FriendlyName = $friendly
            InstanceId = $d.InstanceId
            VidPid = $vidPid
            HardwareIds = ($hwids -join "; ")
            ParentChain = ($walk.Chain -join " -> ")
        }
    }
}

if ($matches.Count -eq 0) {
    Write-Host "No endpoints matched friendly name: $FriendlyMatch"
    exit 0
}

Write-Host "Matched endpoints:"
$matches | Format-Table FriendlyName, InstanceId, VidPid -AutoSize
Write-Host ""
Write-Host "Detailed hardware IDs:"
$matches | ForEach-Object {
    Write-Host "----"
    Write-Host "FriendlyName: $($_.FriendlyName)"
    Write-Host "InstanceId:   $($_.InstanceId)"
    Write-Host "VidPid:       $($_.VidPid)"
    Write-Host "HardwareIds:  $($_.HardwareIds)"
    Write-Host "ParentChain:  $($_.ParentChain)"
}
