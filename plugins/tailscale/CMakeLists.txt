cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(tailscale_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml Network Gui)

qt_standard_project_setup(REQUIRES 6.11)

# When added via add_subdirectory, CMAKE_SOURCE_DIR is the repo root. When this
# directory is configured directly, it is the plugin dir, so the root is two
# levels up instead of one.
if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

qt_add_library(tailscale SHARED)

qt_add_qml_module(tailscale
    URI "Quickshell.Plugins.Tailscale"
    VERSION 1.0
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
        qs::compiler_flags
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
        qs::compiler_flags
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
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::Gui
)
