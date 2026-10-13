cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(kuiserver_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml DBus Gui)

qt_standard_project_setup(REQUIRES 6.11)

if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

qt_add_library(kuiserver SHARED)

qt_add_qml_module(kuiserver
    URI "Quickshell.Plugins.KuiServer"
    VERSION 1.0
    SOURCES
        src/JobEntry.hpp
        src/JobItem.hpp
        src/JobItem.cpp
        src/JobAdaptors.hpp
        src/JobAdaptors.cpp
        src/ServerAdaptors.hpp
        src/ServerAdaptors.cpp
        src/JobServer.hpp
        src/JobServer.cpp
)

target_include_directories(kuiserver
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(kuiserver
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::DBus
        Qt6::Gui
)
