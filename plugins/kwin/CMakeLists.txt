cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(kwin_plugin VERSION 1.0.0 LANGUAGES CXX C)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml DBus Gui WaylandClient)

# Workaround for Fedora packaging: avoid requirement for qt6waylandclient_metatypes.json in QML dependency scanning
set_property(TARGET Qt6::WaylandClient PROPERTY INTERFACE_SOURCES "")

qt_standard_project_setup(REQUIRES 6.11)

if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

add_library(kwin_protocol STATIC)
qt6_generate_wayland_protocol_client_sources(kwin_protocol
    FILES "${CMAKE_CURRENT_SOURCE_DIR}/protocols/plasma-window-management.xml"
)
target_include_directories(kwin_protocol
    PUBLIC
        ${CMAKE_CURRENT_BINARY_DIR}
)
target_link_libraries(kwin_protocol
    PUBLIC
        Qt6::Core
        Qt6::Gui
        Qt6::WaylandClient
)

qt_add_library(kwin SHARED)

qt_add_qml_module(kwin
    URI "Quickshell.Plugins.KWin"
    VERSION 1.0
    SOURCES
        src/KWinManager.hpp
        src/KWinManager.cpp
        src/WindowModel.hpp
        src/WindowModel.cpp
        src/WaylandPlasmaBackend.hpp
        src/WaylandPlasmaBackend.cpp
)

target_include_directories(kwin
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_BINARY_DIR}
)

target_link_libraries(kwin
    PUBLIC
        qs::compiler_flags
    PRIVATE
        kwin_protocol
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::Qml
        Qt6::DBus
        Qt6::WaylandClient
)

add_executable(kwin-probe
    src/ProbeMain.cpp
    src/KWinManager.cpp
    src/KWinManager.hpp
    src/WindowModel.cpp
    src/WindowModel.hpp
    src/WaylandPlasmaBackend.hpp
    src/WaylandPlasmaBackend.cpp
)

target_include_directories(kwin-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_BINARY_DIR}
)

target_link_libraries(kwin-probe
    PUBLIC
        qs::compiler_flags
    PRIVATE
        kwin_protocol
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::DBus
        Qt6::WaylandClient
)
