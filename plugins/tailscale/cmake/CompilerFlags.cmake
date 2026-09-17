if(TARGET tailscale_compiler_flags)
    return()
endif()

include(CheckCompilerFlag)
include(CheckLinkerFlag)

add_library(tailscale_compiler_flags INTERFACE)
add_library(tailscale::compiler_flags ALIAS tailscale_compiler_flags)

target_compile_features(tailscale_compiler_flags INTERFACE cxx_std_20)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    target_compile_options(tailscale_compiler_flags INTERFACE
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

    check_compiler_flag(CXX "-Wformat-security" TAILSCALE_HAS_WFORMAT_SECURITY)
    if(TAILSCALE_HAS_WFORMAT_SECURITY)
        target_compile_options(tailscale_compiler_flags INTERFACE -Wformat-security)
    endif()

    check_compiler_flag(CXX "-fstack-protector-strong" TAILSCALE_HAS_STACK_PROTECTOR_STRONG)
    if(TAILSCALE_HAS_STACK_PROTECTOR_STRONG)
        target_compile_options(tailscale_compiler_flags INTERFACE -fstack-protector-strong)
    endif()

    target_compile_options(tailscale_compiler_flags INTERFACE -fPIC)

    check_linker_flag(CXX "LINKER:-z,relro" TAILSCALE_HAS_RELRO)
    if(TAILSCALE_HAS_RELRO)
        target_link_options(tailscale_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:-z,relro>
        )
    endif()

    check_linker_flag(CXX "LINKER:-z,now" TAILSCALE_HAS_BIND_NOW)
    if(TAILSCALE_HAS_BIND_NOW)
        target_link_options(tailscale_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:-z,now>
        )
    endif()

    check_linker_flag(CXX "LINKER:-z,noexecstack" TAILSCALE_HAS_NOEXECSTACK)
    if(TAILSCALE_HAS_NOEXECSTACK)
        target_link_options(tailscale_compiler_flags INTERFACE
            $<$<CONFIG:Release>:LINKER:-z,noexecstack>
        )
    endif()

    target_link_options(tailscale_compiler_flags INTERFACE
        $<$<CONFIG:Release>:-Wl,--gc-sections>
        $<$<CONFIG:Release>:-Wl,--as-needed>
    )
endif()
