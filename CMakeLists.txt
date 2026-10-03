cmake_minimum_required(VERSION 3.28...4.4)

project(quick_shell LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# One compilation database for the whole repo instead of 11 per-plugin copies.
# clangd and qmlls both read this from the root.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(PROJECT_IS_TOP_LEVEL)
    find_program(CCACHE_PROGRAM ccache)
    if(CCACHE_PROGRAM AND NOT DEFINED CMAKE_CXX_COMPILER_LAUNCHER)
        set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}" CACHE STRING "CXX compiler launcher")
        message(STATUS "Using ccache compiler launcher: ${CCACHE_PROGRAM}")
    endif()
endif()

include(cmake/CompilerFlags.cmake)

# Single import tree for every plugin module. Quickshell reads this one path
# from the QML2_IMPORT_PATH pragma in shell.qml, so the pragma never has to be
# regenerated when plugins are added or removed. Must be absolute; Qt errors
# out otherwise (Qt6QmlMacros.cmake).
set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml")

file(GLOB plugin_dirs RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}/plugins" "${CMAKE_CURRENT_SOURCE_DIR}/plugins/*")
set(available_plugins)
foreach(plugin_dir IN LISTS plugin_dirs)
    if(NOT IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/plugins/${plugin_dir}")
        continue()
    endif()
    if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/plugins/${plugin_dir}/CMakeLists.txt")
        continue()
    endif()
    list(APPEND available_plugins "${plugin_dir}")
endforeach()
list(SORT available_plugins)

if(QS_PLUGINS)
    set(requested_plugins ${QS_PLUGINS})
else()
    set(requested_plugins ${available_plugins})
endif()

set(unknown_plugins)
foreach(plugin IN LISTS requested_plugins)
    if(NOT plugin IN_LIST available_plugins)
        list(APPEND unknown_plugins "${plugin}")
    endif()
endforeach()
if(unknown_plugins)
    message(FATAL_ERROR
        "QS_PLUGINS names plugins that do not exist: ${unknown_plugins}\n"
        "Available: ${available_plugins}"
    )
endif()

set(configured_plugins)
foreach(plugin IN LISTS requested_plugins)
    message(STATUS "Configuring plugin: ${plugin}")
    add_subdirectory("plugins/${plugin}" "plugins/${plugin}")
    list(APPEND configured_plugins "${plugin}")
endforeach()

message(STATUS "Configured plugins: ${configured_plugins}")
message(STATUS "QML import root: ${QT_QML_OUTPUT_DIRECTORY}")

# qmllint over the shell's own QML. These files are not part of any
# qt_add_qml_module, so nothing lints them by default. Opt-in target:
#   cmake --build build --target qmllint
if(PROJECT_IS_TOP_LEVEL)
    find_program(QMLLINT_EXECUTABLE NAMES qmllint-qt6 qmllint qt6-qmllint)
    if(QMLLINT_EXECUTABLE)
        file(GLOB_RECURSE shell_qml_files
            RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
            "${CMAKE_CURRENT_SOURCE_DIR}/*.qml")
        # plugins/*/build holds no QML, but be explicit so a future plugin that
        # ships .qml files does not get linted twice.
        list(FILTER shell_qml_files EXCLUDE REGEX "^build/")

        add_custom_target(qmllint
            COMMAND "${QMLLINT_EXECUTABLE}"
                    -I "${QT_QML_OUTPUT_DIRECTORY}"
                    ${shell_qml_files}
            WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
            COMMENT "qmllint ${CMAKE_CURRENT_SOURCE_DIR}"
            VERBATIM
        )
    else()
        message(STATUS "qmllint not found, skipping the qmllint target")
    endif()
endif()
