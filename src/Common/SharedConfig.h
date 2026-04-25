#pragma once

#include <string_view>

namespace equalizer_bridge::shared_config
{
inline constexpr std::wstring_view kRegistryPath = LR"(SOFTWARE\EqualizerVolumeBridge\Device)";
inline constexpr std::wstring_view kRegistryValueVolumeScalar = L"VolumeScalar";
inline constexpr std::wstring_view kRegistryValueMute = L"Mute";
inline constexpr std::wstring_view kRegistryValueDeviceId = L"TargetDeviceId";
inline constexpr std::wstring_view kRegistryValueFriendlyMatch = L"FriendlyNameMatch";
inline constexpr std::wstring_view kRegistryValueHardwareIdMatch = L"HardwareIdMatch";
inline constexpr std::wstring_view kRegistryValueSupportedHardwareIds = L"SupportedHardwareIds";
inline constexpr std::wstring_view kRegistryValueMinGainMilli = L"MinGainMilli";
inline constexpr std::wstring_view kRegistryValueMaxGainMilli = L"MaxGainMilli";
} // namespace equalizer_bridge::shared_config
