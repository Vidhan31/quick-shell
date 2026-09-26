cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(updatemanager_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml DBus Gui)

qt_standard_project_setup(REQUIRES 6.11)

include(cmake/CompilerFlags.cmake)

set(QML_PLUGIN_IMPORT_DIR "${CMAKE_CURRENT_BINARY_DIR}/imports")

qt_add_library(updatemanager SHARED)

qt_add_qml_module(updatemanager
    URI "Quickshell.Plugins.UpdateManager"
    VERSION 1.0
    OUTPUT_DIRECTORY "${QML_PLUGIN_IMPORT_DIR}/Quickshell/Plugins/UpdateManager"
    SOURCES
        src/DbusTypes.hpp
        src/DbusTypes.cpp
        src/UpdateItem.hpp
        src/UpdateItem.cpp
        src/UpdateModel.hpp
        src/UpdateModel.cpp
        src/UpdateWorker.hpp
        src/UpdateWorker.cpp
        src/UpdateManager.hpp
        src/UpdateManager.cpp
)

target_include_directories(updatemanager
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(updatemanager
    PUBLIC
        updatemanager::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::DBus
        Qt6::Gui
)

# Standalone CLI probe tool for testing/diagnostics
add_executable(updatemanager-probe
    src/ProbeMain.cpp
)

target_include_directories(updatemanager-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(updatemanager-probe
    PUBLIC
        updatemanager::compiler_flags
    PRIVATE
        updatemanager
        Qt6::Core
        Qt6::DBus
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
)
