cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(modelpricing_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml Network)

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

qt_add_library(modelpricing SHARED)

qt_add_qml_module(modelpricing
    URI "Quickshell.Plugins.ModelPricing"
    VERSION 1.0
    SOURCES
        src/ModelPricing.hpp
        src/ModelPricing.cpp
)

target_include_directories(modelpricing
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(modelpricing
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::Network
)

# Standalone CLI probe for testing/diagnostics.
# Resolves model names against a models.dev payload:
#   modelpricing-probe <config.json> <api.json> <model...>
add_executable(modelpricing-probe
    src/ProbeMain.cpp
    src/ModelPricing.cpp
    src/ModelPricing.hpp
)

target_include_directories(modelpricing-probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(modelpricing-probe
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Network
)
