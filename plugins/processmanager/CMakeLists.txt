cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(processmanager_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml DBus)

qt_standard_project_setup(REQUIRES 6.11)

if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

qt_add_library(processmanager SHARED)

qt_add_qml_module(processmanager
    URI "Quickshell.Plugins.ProcessManager"
    VERSION 1.0
    SOURCES
        src/ProcessManager.hpp
        src/ProcessManager.cpp
)

target_include_directories(processmanager
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(processmanager
    PUBLIC
        qs::compiler_flags
        qs::processcore
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::DBus
)

add_executable(processmanager-probe
    src/ProbeMain.cpp
    src/ProcessManager.cpp
    src/ProcessManager.hpp
)

target_include_directories(processmanager-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(processmanager-probe
    PUBLIC
        qs::compiler_flags
        qs::processcore
    PRIVATE
        Qt6::Core
        Qt6::DBus
)



