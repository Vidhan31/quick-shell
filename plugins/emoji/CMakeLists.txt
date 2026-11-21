cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(emoji_plugin VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Quick Qml DBus Gui)

find_library(LIBEI_LIBRARY NAMES ei libei.so.1 libei)
if(NOT LIBEI_LIBRARY)
    message(FATAL_ERROR "libei is required for emoji paste injection")
endif()

qt_standard_project_setup(REQUIRES 6.11)

if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

qt_add_library(emoji SHARED)

qt_add_qml_module(emoji
    URI "Quickshell.Plugins.Emoji"
    VERSION 1.0
    SOURCES
        src/EmojiProvider.hpp
        src/EmojiProvider.cpp
)

target_include_directories(emoji
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(emoji
    PUBLIC
        qs::compiler_flags
    PRIVATE
        Qt6::Core
        Qt6::Quick
        Qt6::Qml
        Qt6::DBus
        Qt6::Gui
        ${LIBEI_LIBRARY}
)
