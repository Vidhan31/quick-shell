cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(tailscale_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml Network Gui)

qt_standard_project_setup(REQUIRES 6.11)

include(cmake/CompilerFlags.cmake)

set(QML_PLUGIN_IMPORT_DIR "${CMAKE_CURRENT_BINARY_DIR}/imports")

qt_add_library(tailscale SHARED)

qt_add_qml_module(tailscale
    URI "Quickshell.Plugins.Tailscale"
    VERSION 1.0
    OUTPUT_DIRECTORY "${QML_PLUGIN_IMPORT_DIR}/Quickshell/Plugins/Tailscale"
    SOURCES
        src/TailscaleState.hpp
        src/TailscaleSocketClient.hpp
        src/TailscaleSocketClient.cpp
        src/TailscaleMonitor.hpp
        src/TailscaleMonitor.cpp
)

target_include_directories(tailscale
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(tailscale
    PUBLIC
        tailscale::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::Network
        Qt6::Gui
)

# Standalone CLI probe tool for testing/diagnostics
add_executable(tailscale-probe
    src/ProbeMain.cpp
    src/TailscaleSocketClient.cpp
    src/TailscaleSocketClient.hpp
    src/TailscaleState.hpp
)

target_include_directories(tailscale-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(tailscale-probe
    PUBLIC
        tailscale::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::Gui
)

# Standalone micro-benchmark tool
add_executable(tailscale-bench
    src/BenchMain.cpp
    src/TailscaleSocketClient.cpp
    src/TailscaleSocketClient.hpp
    src/TailscaleState.hpp
)

target_include_directories(tailscale-bench
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(tailscale-bench
    PUBLIC
        tailscale::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::Gui
)
