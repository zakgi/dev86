# dev86 -- CMake build for the host toolchain.
#
# Scope: builds the *host* tools (bcc, bcc-cc1, bcc-cpp, unproto, copt,
# as86, ld86, ar86, objdump86) as native binaries on the host platform.
#
# Targets supported & exercised: macOS arm64 (Apple Silicon).
# Targets that should still work: Linux x86_64, Linux arm64.
#
# Out of scope (still uses the legacy GNU-make build): the cross-target
# libraries (libc, libbsd, lib-stand, lib-dos, lib-fast, lib-386), the
# bootblocks, elksemu, doselks, dis88, and the tests/ directory. Those
# require ncc (the just-built bcc) as the cross-compiler and have their
# own Makefiles tightly bound to GNU make features. The CMake build
# stops at producing a working host toolchain -- which is what's needed
# to then run the legacy `make` on the libc subtree if desired.

cmake_minimum_required(VERSION 3.19)  # need file(CHMOD)

# Read VERSION from the top-level Makefile so we don't have to keep two
# copies in sync. The Makefile line looks like: VERSION=0.16.21
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/Makefile" _topmk)
string(REGEX MATCH "VERSION=([0-9]+)\\.([0-9]+)\\.([0-9]+)" _ "${_topmk}")
set(DEV86_VERSION_MAJOR "${CMAKE_MATCH_1}")
set(DEV86_VERSION_MINOR "${CMAKE_MATCH_2}")
set(DEV86_VERSION_PATCH "${CMAKE_MATCH_3}")
set(DEV86_VERSION "${DEV86_VERSION_MAJOR}.${DEV86_VERSION_MINOR}.${DEV86_VERSION_PATCH}")

project(dev86
    VERSION "${DEV86_VERSION}"
    LANGUAGES C
    DESCRIPTION "dev86 -- 8086 development tools (host toolchain)")

# Pin dev86's own source dir into a clearly-named variable so the
# helper modules can reference it without confusion. Under
# FetchContent_MakeAvailable() from a downstream project,
# CMAKE_SOURCE_DIR points at the *consumer's* top, not dev86's.
# CMAKE_CURRENT_SOURCE_DIR works here in the top-level CMakeLists but
# changes inside add_subdirectory() and isn't well-defined in include()d
# .cmake files. PROJECT_SOURCE_DIR (set by project()) is the right
# variable in modern CMake; we save it under a project-specific name to
# stay readable even when downstream defines their own project().
set(Dev86_SOURCE_DIR "${PROJECT_SOURCE_DIR}" CACHE INTERNAL
    "Top of the dev86 source tree.")

# -- Options ----------------------------------------------------------------

option(DEV86_BUILD_BCC      "Build bcc/bcc-cc1 (the C compiler)"   ON)
option(DEV86_BUILD_AS       "Build as86 (the assembler)"           ON)
option(DEV86_BUILD_LD       "Build ld86/objdump86 (the linker)"    ON)
option(DEV86_BUILD_AR       "Build ar86 (the archiver)"            ON)
option(DEV86_BUILD_CPP      "Build bcc-cpp (the C preprocessor)"   ON)
option(DEV86_BUILD_COPT     "Build copt (the peephole optimiser)"  ON)
option(DEV86_BUILD_UNPROTO  "Build unproto (the K&R deprototyper)" ON)

# Cross-target libraries. These are 8086 artefacts produced by running
# the just-built toolchain on the libc/ and libbsd/ source. They drive
# the legacy GNU-make build for those subtrees rather than reimplement
# it in CMake. Default OFF for the alternative libc PLATFORM variants --
# most users only need the standard ELKS one.
option(DEV86_BUILD_LIBC        "Cross-build libc (PLATFORM=i86-ELKS)"   ON)
option(DEV86_BUILD_LIBC_FAST   "Cross-build libc_f (PLATFORM=i86-FAST)" OFF)
option(DEV86_BUILD_LIBC_STAND  "Cross-build libc_s (PLATFORM=i86-BIOS)" OFF)
option(DEV86_BUILD_LIBC_DOS    "Cross-build libdos (PLATFORM=i86-DOS)"  OFF)
option(DEV86_BUILD_LIBC_386    "Cross-build libc3 (PLATFORM=i386-BCC)"  OFF)
option(DEV86_BUILD_LIBBSD      "Cross-build libbsd"                     ON)

# Where the bcc driver looks for its sub-tools and rules at runtime.
# Defaults to CMAKE_INSTALL_PREFIX so that `make install` produces a
# self-consistent toolchain. Override with -DDEV86_LOCALPREFIX=... if
# you want the binaries to look elsewhere at runtime (e.g. for a
# DESTDIR-style staged install).
set(DEV86_LOCALPREFIX "${CMAKE_INSTALL_PREFIX}" CACHE STRING
    "Runtime prefix that bcc embeds for locating bcc-cc1, copt, rules, etc.")

# -- Common compile flags ---------------------------------------------------

# dev86 sources are old-school K&R-flavoured C with implicit ints, K&R-style
# function definitions, and pre-prototype extern declarations. Modern Clang
# (Xcode 15+) and modern GCC turn several of these into errors by default;
# downgrade them to warnings so the source builds unchanged.
include(CheckCCompilerFlag)

set(_dev86_compat_flags)
foreach(_flag
        -Wno-error=implicit-function-declaration
        -Wno-error=implicit-int
        -Wno-implicit-function-declaration
        -Wno-implicit-int
        -Wno-deprecated-non-prototype
        -Wno-strict-prototypes
        -Wno-pointer-sign
        -Wno-parentheses
        -Wno-return-type
        -Wno-format
        -Wno-unused-result
        -fno-strict-aliasing)
    string(MAKE_C_IDENTIFIER "HAVE_FLAG_${_flag}" _have)
    check_c_compiler_flag("${_flag}" ${_have})
    if(${_have})
        list(APPEND _dev86_compat_flags "${_flag}")
    endif()
endforeach()

add_library(dev86_compat INTERFACE)
target_compile_options(dev86_compat INTERFACE ${_dev86_compat_flags})

# Helper: emit a per-tool version.h matching the format the legacy
# Makefile generates. Used by bcc, as, ld.
function(dev86_write_version_h _path)
    file(WRITE "${_path}"
        "#define VERSION \"${DEV86_VERSION}\"\n"
        "#define VER_MAJ ${DEV86_VERSION_MAJOR}\n"
        "#define VER_MIN ${DEV86_VERSION_MINOR}\n"
        "#define VER_PAT ${DEV86_VERSION_PATCH}\n")
endfunction()

# -- Subdirectories ---------------------------------------------------------

if(DEV86_BUILD_BCC)
    add_subdirectory(bcc)
endif()
if(DEV86_BUILD_AS)
    add_subdirectory(as)
endif()
if(DEV86_BUILD_LD)
    add_subdirectory(ld)
endif()
if(DEV86_BUILD_AR)
    add_subdirectory(ar)
endif()
if(DEV86_BUILD_CPP)
    add_subdirectory(cpp)
endif()
if(DEV86_BUILD_COPT)
    add_subdirectory(copt)
endif()
if(DEV86_BUILD_UNPROTO)
    add_subdirectory(unproto)
endif()

# NB: use CMAKE_CURRENT_SOURCE_DIR -- under FetchContent_MakeAvailable
# from a downstream project, CMAKE_SOURCE_DIR points at the downstream
# project's top, not at dev86's. CMAKE_CURRENT_SOURCE_DIR always refers
# to the directory of the currently-processing CMakeLists.txt (this
# file).
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Stage the host toolchain into a single sibling tree (build/stage/)
# in the layout `ncc` walks via BCC_PREFIX. Always on: needed both by
# the cross-library build below *and* by FetchContent consumers who
# want to invoke ncc from their own custom commands.
include(StageToolchain)

# Cross-target libraries -- driven by the legacy GNU-make build, but
# orchestrated from CMake so they slot into the same configure/build/
# install flow. Requires the full host toolchain; gates itself off if
# no library variant is enabled.
if(DEV86_BUILD_LIBC OR DEV86_BUILD_LIBC_FAST OR DEV86_BUILD_LIBC_STAND
   OR DEV86_BUILD_LIBC_DOS OR DEV86_BUILD_LIBC_386 OR DEV86_BUILD_LIBBSD)
    if(NOT (DEV86_BUILD_BCC AND DEV86_BUILD_AS AND DEV86_BUILD_LD
            AND DEV86_BUILD_AR AND DEV86_BUILD_CPP AND DEV86_BUILD_COPT
            AND DEV86_BUILD_UNPROTO))
        message(FATAL_ERROR
            "Cross-libraries (libc/libbsd) need the full host toolchain. "
            "Re-enable all DEV86_BUILD_{BCC,AS,LD,AR,CPP,COPT,UNPROTO}.")
    endif()
    include(CrossLibraries)
endif()

# -- Public surface for FetchContent consumers ----------------------------
# Aliases in the Dev86:: namespace let downstream projects reference these
# from add_custom_command via $<TARGET_FILE:Dev86::ncc>, etc., without
# caring about our internal target names. Plus a few cached path variables
# so consumers can locate the staged toolchain and the cross-libs.
include(Dev86Exports)

message(STATUS "dev86 ${DEV86_VERSION}")
message(STATUS "  Host:           ${CMAKE_SYSTEM_NAME} / ${CMAKE_SYSTEM_PROCESSOR}")
message(STATUS "  Compiler:       ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}")
message(STATUS "  Install prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "  bcc localprefix:${DEV86_LOCALPREFIX}")
