cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(antigravityusage_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml Sql)

qt_standard_project_setup(REQUIRES 6.11)

include(cmake/CompilerFlags.cmake)

set(QML_PLUGIN_IMPORT_DIR "${CMAKE_CURRENT_BINARY_DIR}/imports")

qt_add_library(antigravityusage SHARED)

qt_add_qml_module(antigravityusage
    URI "Quickshell.Plugins.AntigravityUsage"
    VERSION 1.0
    OUTPUT_DIRECTORY "${QML_PLUGIN_IMPORT_DIR}/Quickshell/Plugins/AntigravityUsage"
    SOURCES
        src/AntigravityUsage.hpp
        src/AntigravityUsage.cpp
)

target_include_directories(antigravityusage
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(antigravityusage
    PUBLIC
        antigravityusage::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::Sql
)

# Standalone CLI probe for testing/diagnostics.
# Prints one JSON object with today/week/month totals to stdout.
add_executable(antigravity-probe
    src/ProbeMain.cpp
    src/AntigravityUsage.cpp
    src/AntigravityUsage.hpp
)

target_include_directories(antigravity-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(antigravity-probe
    PUBLIC
        antigravityusage::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Sql
)
