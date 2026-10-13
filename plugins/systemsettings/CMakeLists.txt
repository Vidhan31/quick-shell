cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(systemsettings_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml)
find_package(KF6CoreAddons REQUIRED)
find_package(KF6Config REQUIRED)

qt_standard_project_setup(REQUIRES 6.11)

if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

qt_add_library(systemsettings SHARED)

qt_add_qml_module(systemsettings
    URI "Quickshell.Plugins.SystemSettings"
    VERSION 1.0
    SOURCES
        src/SystemSettings.hpp
        src/SystemSettings.cpp
)

target_include_directories(systemsettings
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(systemsettings
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        KF6::CoreAddons
        KF6::ConfigCore
)

add_executable(systemsettings-probe
    src/ProbeMain.cpp
    src/SystemSettings.cpp
    src/SystemSettings.hpp
)

target_include_directories(systemsettings-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(systemsettings-probe
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        KF6::CoreAddons
        KF6::ConfigCore
)
