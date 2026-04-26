# Dev86Exports.cmake -- public surface for downstream consumers.
#
# Intended audience: projects that pull dev86 in via FetchContent and want
# to drive the toolchain from their own build. Run as part of dev86's own
# configure (top-level CMakeLists includes this last).
#
# After include, downstream sees:
#
#   ALIAS targets in the Dev86:: namespace:
#     Dev86::bcc, Dev86::ncc, Dev86::bcc-cc1, Dev86::bcc-cpp,
#     Dev86::unproto, Dev86::copt, Dev86::as86, Dev86::ld86,
#     Dev86::ar86, Dev86::objdump86
#   (any tool with DEV86_BUILD_<X>=OFF won't get its alias)
#
#   Cached path variables:
#     Dev86_STAGE_DIR        -- pass as BCC_PREFIX env when invoking ncc
#     Dev86_INCLUDE_DIR      -- target (8086) header dir, -I this
#     Dev86_LIBC_FILE        -- full path to libc.a       (if DEV86_BUILD_LIBC)
#     Dev86_CRT0_FILE        --                   crt0.o   ( "  )
#     Dev86_LIBBCC_FILE      --                   libbcc.a ( "  )
#     Dev86_LIBC_FAST_FILE   -- libc_f.a   (DEV86_BUILD_LIBC_FAST)
#     Dev86_LIBC_STAND_FILE  -- libc_s.a   (DEV86_BUILD_LIBC_STAND)
#     Dev86_LIBDOS_FILE      -- libdos.a   (DEV86_BUILD_LIBC_DOS)
#     Dev86_LIBC_386_FILE    -- libc.a (i386)  (DEV86_BUILD_LIBC_386)
#     Dev86_CRT0_386_FILE    -- crt0.o (i386)  (DEV86_BUILD_LIBC_386)
#     Dev86_LIBBSD_FILE      -- libbsd.a   (DEV86_BUILD_LIBBSD)
#
#   Custom target:
#     dev86_stage_toolchain  -- depend on this from your custom commands to
#                              ensure the staged toolchain tree exists
#                              before they run.
#
# Quick usage from a downstream project:
#
#   include(FetchContent)
#   FetchContent_Declare(dev86 GIT_REPOSITORY ... GIT_TAG apple-silicon)
#   FetchContent_MakeAvailable(dev86)
#
#   add_custom_command(
#     OUTPUT bios.o
#     COMMAND $<TARGET_FILE:Dev86::as86> -0 -b -o bios.o
#                                         ${CMAKE_CURRENT_SOURCE_DIR}/bios.s
#     DEPENDS Dev86::as86 ${CMAKE_CURRENT_SOURCE_DIR}/bios.s)
#
# For invocations of ncc (which need the staged tree to find sub-tools)
# wrap with `cmake -E env BCC_PREFIX=${Dev86_STAGE_DIR}` and depend on
# the dev86_stage_toolchain custom target.

# Map (alias name without namespace) -> (option that gates the target).
set(_dev86_aliases
    bcc      DEV86_BUILD_BCC
    ncc      DEV86_BUILD_BCC      # ncc is built alongside bcc
    bcc-cc1  DEV86_BUILD_BCC
    bcc-cpp  DEV86_BUILD_CPP
    unproto  DEV86_BUILD_UNPROTO
    copt     DEV86_BUILD_COPT
    as86     DEV86_BUILD_AS
    ld86     DEV86_BUILD_LD
    objdump86 DEV86_BUILD_LD
    ar86     DEV86_BUILD_AR)

set(_i 0)
list(LENGTH _dev86_aliases _n)
while(_i LESS _n)
    list(GET _dev86_aliases ${_i}                 _t)
    math(EXPR _i "${_i} + 1")
    list(GET _dev86_aliases ${_i}                 _opt)
    math(EXPR _i "${_i} + 1")
    if(${${_opt}} AND TARGET ${_t})
        # ALIAS for executables is supported since CMake 3.18; we need
        # 3.19 anyway for file(CHMOD) elsewhere.
        add_executable(Dev86::${_t} ALIAS ${_t})
    endif()
endwhile()

# -- Cross-library file paths ---------------------------------------------
# These point into the libc/ source dir where the legacy Makefile leaves
# its outputs. They're set unconditionally based on the option being on,
# regardless of whether the file exists yet at configure time -- the file
# materialises during the build, and downstream custom commands declare
# dev86_libc / dev86_libbsd as DEPENDS so the order is correct.

if(DEV86_BUILD_LIBC)
    set(Dev86_LIBC_FILE   "${Dev86_SOURCE_DIR}/libc/libc.a"   CACHE FILEPATH "")
    set(Dev86_CRT0_FILE   "${Dev86_SOURCE_DIR}/libc/crt0.o"   CACHE FILEPATH "")
    set(Dev86_LIBBCC_FILE "${Dev86_SOURCE_DIR}/libc/libbcc.a" CACHE FILEPATH "")
endif()
if(DEV86_BUILD_LIBC_FAST)
    set(Dev86_LIBC_FAST_FILE  "${Dev86_SOURCE_DIR}/libc/libc_f.a" CACHE FILEPATH "")
endif()
if(DEV86_BUILD_LIBC_STAND)
    set(Dev86_LIBC_STAND_FILE "${Dev86_SOURCE_DIR}/libc/libc_s.a" CACHE FILEPATH "")
endif()
if(DEV86_BUILD_LIBC_DOS)
    set(Dev86_LIBDOS_FILE     "${Dev86_SOURCE_DIR}/libc/libdos.a" CACHE FILEPATH "")
endif()
if(DEV86_BUILD_LIBC_386)
    set(Dev86_LIBC_386_FILE   "${Dev86_SOURCE_DIR}/libc/libc3.a"  CACHE FILEPATH "")
    set(Dev86_CRT0_386_FILE   "${Dev86_SOURCE_DIR}/libc/crt3.o"   CACHE FILEPATH "")
endif()
if(DEV86_BUILD_LIBBSD)
    set(Dev86_LIBBSD_FILE     "${Dev86_SOURCE_DIR}/libbsd/libbsd.a" CACHE FILEPATH "")
endif()

# Mark dev86 as initialised -- downstream can sanity-check with
# `if(NOT Dev86_FOUND)` inside a fallback path.
set(Dev86_FOUND TRUE CACHE INTERNAL "dev86 toolchain is available")
set(Dev86_VERSION "${DEV86_VERSION}" CACHE INTERNAL "")
