if(TARGET updatemanager_compiler_flags)
    return()
endif()

include(CheckCompilerFlag)
include(CheckLinkerFlag)

add_library(updatemanager_compiler_flags INTERFACE)
add_library(updatemanager::compiler_flags ALIAS updatemanager_compiler_flags)

target_compile_features(updatemanager_compiler_flags INTERFACE cxx_std_20)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    target_compile_options(updatemanager_compiler_flags INTERFACE
        -Wall
        -Wextra
        -Wpedantic
        $<$<COMPILE_LANGUAGE:CXX>:-Wnon-virtual-dtor>
        $<$<COMPILE_LANGUAGE:CXX>:-Woverloaded-virtual>
        -Wformat=2
        $<$<CONFIG:Release>:-O3>
        $<$<CONFIG:Release>:-ffunction-sections>
        $<$<CONFIG:Release>:-fdata-sections>
        $<$<CONFIG:Release>:-fno-semantic-interposition>
        $<$<CONFIG:Release>:-U_FORTIFY_SOURCE>
        $<$<CONFIG:Release>:-D_FORTIFY_SOURCE=3>
    )

    check_compiler_flag(CXX "-Wformat-security" UPDATEMANAGER_HAS_WFORMAT_SECURITY)
    if(UPDATEMANAGER_HAS_WFORMAT_SECURITY)
        target_compile_options(updatemanager_compiler_flags INTERFACE -Wformat-security)
    endif()

    check_compiler_flag(CXX "-fstack-protector-strong" UPDATEMANAGER_HAS_STACK_PROTECTOR_STRONG)
    if(UPDATEMANAGER_HAS_STACK_PROTECTOR_STRONG)
        target_compile_options(updatemanager_compiler_flags INTERFACE -fstack-protector-strong)
    endif()

    target_compile_options(updatemanager_compiler_flags INTERFACE -fPIC)

    check_linker_flag(CXX "LINKER:-z,relro" UPDATEMANAGER_HAS_RELRO)
    if(UPDATEMANAGER_HAS_RELRO)
        target_link_options(updatemanager_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:-z,relro>
        )
    endif()

    check_linker_flag(CXX "LINKER:-z,now" UPDATEMANAGER_HAS_BIND_NOW)
    if(UPDATEMANAGER_HAS_BIND_NOW)
        target_link_options(updatemanager_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:-z,now>
        )
    endif()

    check_linker_flag(CXX "LINKER:-z,noexecstack" UPDATEMANAGER_HAS_NOEXECSTACK)
    if(UPDATEMANAGER_HAS_NOEXECSTACK)
        target_link_options(updatemanager_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:-z,noexecstack>
        )
    endif()

    check_linker_flag(CXX "LINKER:--gc-sections" UPDATEMANAGER_HAS_GC_SECTIONS)
    if(UPDATEMANAGER_HAS_GC_SECTIONS)
        target_link_options(updatemanager_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:--gc-sections>
        )
    endif()

    check_linker_flag(CXX "LINKER:--as-needed" UPDATEMANAGER_HAS_AS_NEEDED)
    if(UPDATEMANAGER_HAS_AS_NEEDED)
        target_link_options(updatemanager_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:--as-needed>
        )
    endif()

    target_compile_definitions(updatemanager_compiler_flags INTERFACE
        $<$<CONFIG:Release>:QT_NO_DEBUG_OUTPUT>
        $<$<CONFIG:Release>:QT_NO_INFO_OUTPUT>
        $<$<CONFIG:Release>:QT_USE_QSTRINGBUILDER>
    )
endif()

find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}" CACHE STRING "C compiler launcher" FORCE)
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}" CACHE STRING "CXX compiler launcher" FORCE)
endif()
