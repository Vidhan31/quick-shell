if(TARGET qs_compiler_flags)
    return()
endif()

include(CheckCompilerFlag)
include(CheckLinkerFlag)

add_library(qs_compiler_flags INTERFACE)
add_library(qs::compiler_flags ALIAS qs_compiler_flags)

target_compile_features(qs_compiler_flags INTERFACE cxx_std_20)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    target_compile_options(qs_compiler_flags INTERFACE
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

    check_compiler_flag(CXX "-Wformat-security" QS_HAS_WFORMAT_SECURITY)
    if(QS_HAS_WFORMAT_SECURITY)
        target_compile_options(qs_compiler_flags INTERFACE -Wformat-security)
    endif()

    check_compiler_flag(CXX "-fstack-protector-strong" QS_HAS_STACK_PROTECTOR_STRONG)
    if(QS_HAS_STACK_PROTECTOR_STRONG)
        target_compile_options(qs_compiler_flags INTERFACE -fstack-protector-strong)
    endif()

    target_compile_options(qs_compiler_flags INTERFACE -fPIC)

    check_linker_flag(CXX "LINKER:-z,relro" QS_HAS_RELRO)
    if(QS_HAS_RELRO)
        target_link_options(qs_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:-z,relro>
        )
    endif()

    check_linker_flag(CXX "LINKER:-z,now" QS_HAS_BIND_NOW)
    if(QS_HAS_BIND_NOW)
        target_link_options(qs_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:-z,now>
        )
    endif()

    check_linker_flag(CXX "LINKER:-z,noexecstack" QS_HAS_NOEXECSTACK)
    if(QS_HAS_NOEXECSTACK)
        target_link_options(qs_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:-z,noexecstack>
        )
    endif()

    check_linker_flag(CXX "LINKER:--gc-sections" QS_HAS_GC_SECTIONS)
    if(QS_HAS_GC_SECTIONS)
        target_link_options(qs_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:--gc-sections>
        )
    endif()

    check_linker_flag(CXX "LINKER:--as-needed" QS_HAS_AS_NEEDED)
    if(QS_HAS_AS_NEEDED)
        target_link_options(qs_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:--as-needed>
        )
    endif()

    # QT_USE_QSTRINGBUILDER is deliberately not set. It redefines operator+ to
    # return a QStringBuilder proxy instead of a QString, so any code calling
    # QString methods on a concatenation result fails to compile.
    target_compile_definitions(qs_compiler_flags INTERFACE
        $<$<CONFIG:Release>:QT_NO_DEBUG_OUTPUT>
        $<$<CONFIG:Release>:QT_NO_INFO_OUTPUT>
    )
endif()
