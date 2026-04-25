# Equalizer Volume Bridge

Reliable Windows master-volume bridging for Zgmicro render devices using Equalizer APO.

## Production Architecture

- `EqualizerVolumeBridgeSvc` subscribes to `IAudioEndpointVolume` on the target render endpoint.
- It mirrors `VolumeScalar` and `Mute` into `HKLM\SOFTWARE\EqualizerVolumeBridge\Device`.
- It updates the Equalizer APO config block in real time so Windows master volume controls loudness.
- Equalizer APO is the required runtime DSP engine.

## Build

```powershell
cmake -S . -B build
cmake --build build --config Release
```

## Run Manually (Validation)

Run from an elevated PowerShell (writes to HKLM):

```powershell
.\build\Release\EqualizerVolumeBridgeSvc.exe --validate --friendly "Zgmicro AUDIO"
```

While running, adjust Windows master volume and verify `[notify]` / `[poll]` updates.

## Registry Contract

Path:

- `HKLM\SOFTWARE\EqualizerVolumeBridge\Device`

Values:

- `TargetDeviceId` (`REG_SZ`)
- `FriendlyNameMatch` (`REG_SZ`)
- `SupportedHardwareIds` (`REG_SZ`, semicolon-delimited, optional)
- `VolumeScalar` (`REG_DWORD`, scalar * 1000)
- `Mute` (`REG_DWORD`, 0 or 1)
- `MinGainMilli` (`REG_DWORD`, 0..3000)
- `MaxGainMilli` (`REG_DWORD`, 0..3000)

## One-Time Install

Use elevated PowerShell:

```powershell
.\installer\install-volume-mirror-service.ps1 -FriendlyMatch "Zgmicro AUDIO"
```

One-stop setup (installs Equalizer APO if missing, builds service if needed, installs/starts service):

```powershell
.\installer\setup-one-stop.ps1 -InstallEqualizerApoIfMissing -BuildService -AutoSelectEqualizerApoDevice -RestartAudioAfterSetup -FriendlyMatch "Zgmicro AUDIO"
```

Optional hardware-scoped targeting:

```powershell
.\installer\install-volume-mirror-service.ps1 `
  -FriendlyMatch "Zgmicro AUDIO" `
  -SupportedHardwareIds @("VID_0AC8&PID_9628") `
  -MinGainMilli 0 `
  -MaxGainMilli 1000
```

This installs and starts `EqualizerVolumeBridgeSvc` as `Automatic`, so it persists across reboot and replug without repeated manual steps.

The setup script attempts to auto-select the bound endpoint for Equalizer APO. If endpoint loudness still does not follow Windows volume, run Equalizer APO Configurator once and ensure the target playback device is selected.