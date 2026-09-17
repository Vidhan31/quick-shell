cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(media_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml DBus Gui)

qt_standard_project_setup(REQUIRES 6.11)

include(cmake/CompilerFlags.cmake)

set(QML_PLUGIN_IMPORT_DIR "${CMAKE_CURRENT_BINARY_DIR}/imports")

qt_add_library(media SHARED)

qt_add_qml_module(media
    URI "Quickshell.Plugins.Media"
    VERSION 1.0
    OUTPUT_DIRECTORY "${QML_PLUGIN_IMPORT_DIR}/Quickshell/Plugins/Media"
    SOURCES
        src/MediaTypes.hpp
        src/MediaPlayer.hpp
        src/MediaPlayer.cpp
        src/MediaManager.hpp
        src/MediaManager.cpp
)

target_include_directories(media
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(media
    PUBLIC
        media::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::DBus
        Qt6::Gui
)

# Standalone CLI probe tool for testing/diagnostics
add_executable(media-probe
    src/ProbeMain.cpp
    src/MediaPlayer.cpp
    src/MediaPlayer.hpp
    src/MediaManager.cpp
    src/MediaManager.hpp
    src/MediaTypes.hpp
)

target_include_directories(media-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(media-probe
    PUBLIC
        media::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::DBus
        Qt6::Gui
)

# Standalone micro-benchmark tool
add_executable(media-bench
    src/BenchMain.cpp
    src/MediaPlayer.cpp
    src/MediaPlayer.hpp
    src/MediaTypes.hpp
)

target_include_directories(media-bench
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(media-bench
    PUBLIC
        media::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::DBus
        Qt6::Gui
)
