cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(privacy_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml)

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

qt_add_library(privacy SHARED)

qt_add_qml_module(privacy
    URI "Quickshell.Plugins.Privacy"
    VERSION 1.0
    SOURCES
        src/PrivacyProbe.hpp
        src/PrivacyProbe.cpp
        src/PrivacyMonitor.hpp
        src/PrivacyMonitor.cpp
)

target_include_directories(privacy
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(privacy
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
)

# Standalone CLI probe tool for testing/verification
add_executable(privacy-probe
    src/ProbeMain.cpp
    src/PrivacyProbe.cpp
    src/PrivacyProbe.hpp
)

target_include_directories(privacy-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(privacy-probe
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
)

# Standalone benchmark tool
add_executable(privacy-bench
    src/BenchMain.cpp
    src/PrivacyProbe.cpp
    src/PrivacyProbe.hpp
)

target_include_directories(privacy-bench
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(privacy-bench
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
)
