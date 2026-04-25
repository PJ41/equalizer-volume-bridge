cmake_minimum_required(VERSION 3.20)
project(equalizer_volume_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(EqualizerVolumeBridgeSvc
    src/VolumeMirror/main.cpp
)

target_include_directories(EqualizerVolumeBridgeSvc PRIVATE
    src/Common
)

target_compile_definitions(EqualizerVolumeBridgeSvc PRIVATE
    UNICODE
    _UNICODE
    NOMINMAX
)

target_link_libraries(EqualizerVolumeBridgeSvc PRIVATE
    ole32
    uuid
    cfgmgr32
    advapi32
    shell32
)
