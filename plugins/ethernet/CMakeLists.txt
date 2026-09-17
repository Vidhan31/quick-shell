cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(ethernet_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml DBus Network)

qt_standard_project_setup(REQUIRES 6.11)

include(cmake/CompilerFlags.cmake)

set(QML_PLUGIN_IMPORT_DIR "${CMAKE_CURRENT_BINARY_DIR}/imports")

qt_add_library(ethernet SHARED)

qt_add_qml_module(ethernet
    URI "Quickshell.Plugins.Ethernet"
    VERSION 1.0
    OUTPUT_DIRECTORY "${QML_PLUGIN_IMPORT_DIR}/Quickshell/Plugins/Ethernet"
    SOURCES
        src/EthernetState.hpp
        src/EthernetProbe.hpp
        src/EthernetProbe.cpp
        src/EthernetMonitor.hpp
        src/EthernetMonitor.cpp
)

target_include_directories(ethernet
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(ethernet
    PUBLIC
        ethernet::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::DBus
        Qt6::Network
)

# Standalone CLI probe tool for testing/diagnostics
add_executable(ethernet-probe
    src/ProbeMain.cpp
    src/EthernetProbe.cpp
    src/EthernetProbe.hpp
    src/EthernetState.hpp
)

target_include_directories(ethernet-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(ethernet-probe
    PUBLIC
        ethernet::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::DBus
        Qt6::Network
)

# Standalone micro-benchmark tool
add_executable(ethernet-bench
    src/BenchMain.cpp
    src/EthernetProbe.cpp
    src/EthernetProbe.hpp
    src/EthernetState.hpp
)

target_include_directories(ethernet-bench
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(ethernet-bench
    PUBLIC
        ethernet::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::DBus
        Qt6::Network
)
