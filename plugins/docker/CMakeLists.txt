cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(docker_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml Network Gui)

qt_standard_project_setup(REQUIRES 6.11)

# When added via add_subdirectory, CMAKE_SOURCE_DIR is the repo root. When this
# directory is configured directly, it is the plugin dir, so the root is two
# levels up instead of one.
if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

qt_add_library(docker SHARED)

qt_add_qml_module(docker
    URI "Quickshell.Plugins.Docker"
    VERSION 1.0
    SOURCES
        src/DockerState.hpp
        src/DockerSocketClient.hpp
        src/DockerSocketClient.cpp
        src/DockerMonitor.hpp
        src/DockerMonitor.cpp
)

target_include_directories(docker
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(docker
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::Network
        Qt6::Gui
)

# Standalone CLI probe tool for testing/diagnostics (read-only by default)
add_executable(docker-probe
    src/ProbeMain.cpp
    src/DockerSocketClient.cpp
    src/DockerSocketClient.hpp
    src/DockerState.hpp
)

target_include_directories(docker-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(docker-probe
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::Gui
)
