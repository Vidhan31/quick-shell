cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(kwin_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml DBus Gui)

qt_standard_project_setup(REQUIRES 6.11)

if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

qt_add_library(kwin SHARED)

qt_add_qml_module(kwin
    URI "Quickshell.Plugins.KWin"
    VERSION 1.0
    SOURCES
        src/KWinManager.hpp
        src/KWinManager.cpp
        src/WindowModel.hpp
        src/WindowModel.cpp
)

target_include_directories(kwin
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(kwin
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::Qml
        Qt6::DBus
)

add_executable(kwin-probe
    src/ProbeMain.cpp
    src/KWinManager.cpp
    src/KWinManager.hpp
    src/WindowModel.cpp
    src/WindowModel.hpp
)

target_include_directories(kwin-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(kwin-probe
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::DBus
)
