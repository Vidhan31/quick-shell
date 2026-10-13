cmake_minimum_required(VERSION 3.28...4.4)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(qs_unixsocket VERSION 1.0.0 LANGUAGES CXX)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Network)

if(PROJECT_IS_TOP_LEVEL)
    get_filename_component(QS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
else()
    set(QS_ROOT_DIR "${CMAKE_SOURCE_DIR}")
endif()

include("${QS_ROOT_DIR}/cmake/CompilerFlags.cmake")

add_library(qs_unixsocket STATIC
    src/UnixHttpClient.hpp
    src/UnixHttpClient.cpp
)
add_library(qs::unixsocket ALIAS qs_unixsocket)

target_include_directories(qs_unixsocket
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(qs_unixsocket
    PUBLIC
        qs::compiler_flags
        Qt6::Core
        Qt6::Network
)
