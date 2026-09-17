cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(notifications_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml DBus Gui)
find_package(PkgConfig REQUIRED)
pkg_check_modules(DBUS REQUIRED IMPORTED_TARGET dbus-1)

qt_standard_project_setup(REQUIRES 6.11)

include(cmake/CompilerFlags.cmake)

set(QML_PLUGIN_IMPORT_DIR "${CMAKE_CURRENT_BINARY_DIR}/imports")

qt_add_library(notifications SHARED)

qt_add_qml_module(notifications
    URI "Quickshell.Plugins.Notifications"
    VERSION 1.0
    OUTPUT_DIRECTORY "${QML_PLUGIN_IMPORT_DIR}/Quickshell/Plugins/Notifications"
    SOURCES
        src/NotificationTypes.hpp
        src/NotificationMonitor.hpp
        src/NotificationMonitor.cpp
        src/NotificationModel.hpp
        src/NotificationModel.cpp
        src/NotificationManager.hpp
        src/NotificationManager.cpp
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
        Qt6::DBus
        Qt6::Gui
        PkgConfig::DBUS
)

# Standalone CLI probe tool for testing/diagnostics
add_executable(notifications-probe
    src/ProbeMain.cpp
    src/NotificationTypes.hpp
    src/NotificationMonitor.hpp
    src/NotificationMonitor.cpp
)

target_include_directories(notifications-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(notifications-probe
    PUBLIC
        notifications::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::DBus
        Qt6::Gui
        PkgConfig::DBUS
)

# Standalone micro-benchmark tool
add_executable(notifications-bench
    src/BenchMain.cpp
    src/NotificationTypes.hpp
    src/NotificationModel.hpp
    src/NotificationModel.cpp
)

target_include_directories(notifications-bench
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(notifications-bench
    PUBLIC
        notifications::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::DBus
        Qt6::Gui
)
