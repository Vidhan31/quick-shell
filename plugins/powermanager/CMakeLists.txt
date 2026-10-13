cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(powermanager_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Qml DBus)

qt_standard_project_setup(REQUIRES 6.11)

if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

qt_add_library(powermanager SHARED)

qt_add_qml_module(powermanager
    URI "Quickshell.Plugins.PowerManager"
    VERSION 1.0
    SOURCES
        src/PowerManager.hpp
        src/PowerManager.cpp
)

target_include_directories(powermanager
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(powermanager
    PRIVATE
        qs::compiler_flags
        Qt6::Core
        Qt6::Qml
        Qt6::DBus
)
