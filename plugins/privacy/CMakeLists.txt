cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(privacy_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml)

qt_standard_project_setup(REQUIRES 6.11)

include(cmake/CompilerFlags.cmake)

set(QML_PLUGIN_IMPORT_DIR "${CMAKE_CURRENT_BINARY_DIR}/imports")

qt_add_library(privacy SHARED)

qt_add_qml_module(privacy
    URI "Quickshell.Plugins.Privacy"
    VERSION 1.0
    OUTPUT_DIRECTORY "${QML_PLUGIN_IMPORT_DIR}/Quickshell/Plugins/Privacy"
    SOURCES
        src/PrivacyProbe.hpp
        src/PrivacyProbe.cpp
        src/PrivacyMonitor.hpp
        src/PrivacyMonitor.cpp
)

target_include_directories(privacy
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(privacy
    PUBLIC
        privacy::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
)

# Standalone CLI probe tool for testing/verification
add_executable(privacy-probe
    src/ProbeMain.cpp
    src/PrivacyProbe.cpp
    src/PrivacyProbe.hpp
)

target_include_directories(privacy-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(privacy-probe
    PUBLIC
        privacy::compiler_flags
    PRIVATE
        Qt6::Core
)

# Standalone benchmark tool
add_executable(privacy-bench
    src/BenchMain.cpp
    src/PrivacyProbe.cpp
    src/PrivacyProbe.hpp
)

target_include_directories(privacy-bench
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(privacy-bench
    PUBLIC
        privacy::compiler_flags
    PRIVATE
        Qt6::Core
)
