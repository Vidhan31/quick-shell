cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(notifications_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml Gui)

qt_standard_project_setup(REQUIRES 6.11)

include(cmake/CompilerFlags.cmake)

set(QML_PLUGIN_IMPORT_DIR "${CMAKE_CURRENT_BINARY_DIR}/imports")

qt_add_library(notifications SHARED)

qt_add_qml_module(notifications
    URI "Quickshell.Plugins.Notifications"
    VERSION 1.0
    OUTPUT_DIRECTORY "${QML_PLUGIN_IMPORT_DIR}/Quickshell/Plugins/Notifications"
    SOURCES
        src/NotificationEntry.hpp
        src/NotificationModel.hpp
        src/NotificationModel.cpp
        src/NotificationStore.hpp
        src/NotificationStore.cpp
)

target_include_directories(notifications
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(notifications
    PUBLIC
        notifications::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::Gui
)

# Standalone CLI probe tool for testing/diagnostics (no Quickshell dep).
# Links the shared module lib (not the sources directly) so the probe and
# the QML plugin share one class definition for qobject_cast to work.
add_executable(notifications-probe
    src/ProbeMain.cpp
)

target_include_directories(notifications-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(notifications-probe
    PUBLIC
        notifications::compiler_flags
    PRIVATE
        notifications
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
)
