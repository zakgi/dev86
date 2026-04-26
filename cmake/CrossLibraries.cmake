# CrossLibraries.cmake -- drive the legacy GNU-make build of libc and
# libbsd from CMake, using the just-built host toolchain as the cross
# compiler.
#
# These libraries are *target* (8086) artefacts. They're produced by
# running ncc (the no-install variant of the bcc driver) and ar86 over
# the libc/ and libbsd/ subtrees. Each subtree is a tangle of nested
# Makefiles using GNU-make-isms (ifeq, archive `lib(member)` rules,
# `$(MAKE) -C subdir`, generated syscall.mak, etc.). Translating all of
# that to CMake is high-effort and high-drift; instead we orchestrate
# the existing build from CMake.
#
# Two-stage flow per platform:
#   1. Stage the host toolchain into a single sibling tree under the
#      build dir, in the layout that ncc (with empty LOCALPREFIX) walks
#      using BCC_PREFIX as the root.
#   2. Invoke `gmake -C libc PLATFORM=<X> CC=ncc AR=ar86 ...` with that
#      stage on PATH and BCC_PREFIX. Copy the produced .a/.o into the
#      install staging area.

# -- Find a usable GNU make ------------------------------------------------

find_program(GNU_MAKE_EXECUTABLE NAMES gmake make DOC "GNU make (>= 3.81, != 3.82)")
if(NOT GNU_MAKE_EXECUTABLE)
    message(FATAL_ERROR
        "Cross-libraries (libc/libbsd) need GNU make on PATH. "
        "Install with `brew install make` (provides `gmake`) or "
        "rely on macOS's bundled /usr/bin/make.")
endif()

execute_process(
    COMMAND "${GNU_MAKE_EXECUTABLE}" --version
    OUTPUT_VARIABLE _make_ver_out
    ERROR_QUIET
    RESULT_VARIABLE _make_ver_rc)
if(NOT _make_ver_rc EQUAL 0 OR NOT _make_ver_out MATCHES "GNU Make")
    message(FATAL_ERROR
        "Found ${GNU_MAKE_EXECUTABLE} but it doesn't look like GNU make. "
        "Install GNU make (brew install make) and retry.")
endif()
string(REGEX MATCH "GNU Make ([0-9]+\\.[0-9]+(\\.[0-9]+)?)" _ "${_make_ver_out}")
set(_make_version "${CMAKE_MATCH_1}")
if(_make_version VERSION_EQUAL "3.82")
    # The dev86 README explicitly calls out GNU make 3.82 bug #30612 as
    # broken for the libc subtree.
    message(WARNING
        "GNU make 3.82 (${GNU_MAKE_EXECUTABLE}) has a bug (No. 30612) that "
        "breaks the libc build. Install a different version (3.81 or >= 4.0).")
endif()
message(STATUS "  Cross-libs make: ${GNU_MAKE_EXECUTABLE} (${_make_version})")

# -- Per-platform libc build ----------------------------------------------
#
# Defining what the original top-level Makefile expressed as:
#   library  -> PLATFORM=i86-ELKS  -> libc.a + crt0.o + libbcc.a
#   lib-fast -> PLATFORM=i86-FAST  -> libc_f.a
#   lib-stand-> PLATFORM=i86-BIOS  -> libc_s.a
#   lib-dos  -> PLATFORM=i86-DOS   -> libdos.a
#   lib-386  -> PLATFORM=i386-BCC  -> libc3.a + crt3.o
#
# Each libc make pass writes its outputs into the libc/ source dir.
# That's the legacy contract -- we live with the in-source artefacts and
# move them into the install tree.

# Helper: define a libc variant target.
#   _name       -- CMake target name, e.g. dev86_libc
#   _platform   -- PLATFORM=... value passed to libc Make
#   _outputs    -- list of files (relative to libc/) the make produces
#   _install_to -- install destination for the outputs (relative)
#   _install_as -- list of names to install the outputs as (parallel to _outputs)
function(_dev86_add_libc_variant _name _platform _outputs _install_to _install_as)
    set(_stamp "${CMAKE_BINARY_DIR}/stamps/${_name}.stamp")
    set(_abs_outputs)
    foreach(_o IN LISTS _outputs)
        list(APPEND _abs_outputs "${Dev86_SOURCE_DIR}/libc/${_o}")
    endforeach()

    # Compute commands to also stage the produced artefacts under the
    # toolchain stage tree, named as the install layout expects them.
    # That way `ld86 -L${stage}/lib/bcc -lc` can find libc.a and crt0.o
    # for end-to-end smoke tests *without* needing `cmake --install`.
    set(_stage_cmds)
    list(LENGTH _outputs _n)
    math(EXPR _last "${_n} - 1")
    foreach(_i RANGE ${_last})
        list(GET _outputs    ${_i} _src)
        list(GET _install_as ${_i} _dst)
        if(_install_to STREQUAL "lib/bcc")
            set(_stage_dst "${Dev86_STAGE_DIR}/lib/bcc/${_dst}")
        else()
            set(_stage_dst "${Dev86_STAGE_DIR}/${_install_to}/${_dst}")
        endif()
        list(APPEND _stage_cmds COMMAND
            "${CMAKE_COMMAND}" -E copy
            "${Dev86_SOURCE_DIR}/libc/${_src}"
            "${_stage_dst}")
    endforeach()

    add_custom_command(
        OUTPUT ${_abs_outputs} "${_stamp}"
        # The libc subtree is built in-source. Wipe any prior .o/.a from
        # a previous PLATFORM pass -- different ARCH flags produce
        # incompatible objects that will linger in the archive. Wrap
        # in `sh -c` so the redirection / `|| true` work; CMake's COMMAND
        # is exec-style and does not shell-interpret args.
        COMMAND sh -c "'${GNU_MAKE_EXECUTABLE}' -C '${Dev86_SOURCE_DIR}/libc' clean >/dev/null 2>&1 || true"
        COMMAND "${CMAKE_COMMAND}" -E env
                "BCC_PREFIX=${Dev86_STAGE_DIR}"
                "PATH=${Dev86_STAGE_DIR}/bin:$ENV{PATH}"
                "ELKSSRC=/dev/null"
                "${GNU_MAKE_EXECUTABLE}" -C "${Dev86_SOURCE_DIR}/libc"
                "TOPDIR=${Dev86_SOURCE_DIR}"
                "VERSION=${DEV86_VERSION}"
                "CC=ncc" "AR=ar86" "ARFLAGS=r"
                "PLATFORM=${_platform}"
        # Stage outputs into the toolchain tree under install-layout names.
        ${_stage_cmds}
        COMMAND "${CMAKE_COMMAND}" -E make_directory
                "${CMAKE_BINARY_DIR}/stamps"
        COMMAND "${CMAKE_COMMAND}" -E touch "${_stamp}"
        DEPENDS dev86_stage_toolchain
        WORKING_DIRECTORY "${Dev86_SOURCE_DIR}"
        COMMENT "Cross-building libc for PLATFORM=${_platform}"
        VERBATIM)

    add_custom_target(${_name} ALL DEPENDS "${_stamp}")

    # Stage outputs into the host toolchain stage so subsequent variants
    # and (down the road) consumers can use them, then install them
    # under the standard lib/bcc/ layout with the canonical names.
    list(LENGTH _outputs _n)
    math(EXPR _last "${_n} - 1")
    foreach(_i RANGE ${_last})
        list(GET _outputs    ${_i} _src)
        list(GET _install_as ${_i} _dst)
        install(
            FILES "${Dev86_SOURCE_DIR}/libc/${_src}"
            DESTINATION "${_install_to}"
            RENAME "${_dst}")
    endforeach()
endfunction()

# i86-ELKS -- the default ELKS variant.
_dev86_add_libc_variant(
    dev86_libc            i86-ELKS
    "libc.a;crt0.o;libbcc.a"
    "lib/bcc"
    "libc.a;crt0.o;libbcc.a")

if(DEV86_BUILD_LIBC_FAST)
    _dev86_add_libc_variant(
        dev86_libc_fast   i86-FAST
        "libc_f.a"        "lib/bcc"   "libc_f.a")
    add_dependencies(dev86_libc_fast dev86_libc)
endif()
if(DEV86_BUILD_LIBC_STAND)
    _dev86_add_libc_variant(
        dev86_libc_stand  i86-BIOS
        "libc_s.a"        "lib/bcc"   "libc_s.a")
    add_dependencies(dev86_libc_stand dev86_libc)
endif()
if(DEV86_BUILD_LIBC_DOS)
    _dev86_add_libc_variant(
        dev86_libc_dos    i86-DOS
        "libdos.a"        "lib/bcc"   "libdos.a")
    add_dependencies(dev86_libc_dos dev86_libc)
endif()
if(DEV86_BUILD_LIBC_386)
    _dev86_add_libc_variant(
        dev86_libc_386    i386-BCC
        "libc3.a;crt3.o"  "lib/bcc/i386"  "libc.a;crt0.o")
    add_dependencies(dev86_libc_386 dev86_libc)
endif()

# -- libbsd ---------------------------------------------------------------
# Single-platform, single output. Same orchestration pattern.

if(DEV86_BUILD_LIBBSD)
    set(_bsd_stamp "${CMAKE_BINARY_DIR}/stamps/dev86_libbsd.stamp")
    set(_bsd_out   "${Dev86_SOURCE_DIR}/libbsd/libbsd.a")
    add_custom_command(
        OUTPUT "${_bsd_out}" "${_bsd_stamp}"
        COMMAND sh -c "'${GNU_MAKE_EXECUTABLE}' -C '${Dev86_SOURCE_DIR}/libbsd' clean >/dev/null 2>&1 || true"
        COMMAND "${CMAKE_COMMAND}" -E env
                "BCC_PREFIX=${Dev86_STAGE_DIR}"
                "PATH=${Dev86_STAGE_DIR}/bin:$ENV{PATH}"
                "ELKSSRC=/dev/null"
                "${GNU_MAKE_EXECUTABLE}" -C "${Dev86_SOURCE_DIR}/libbsd"
                "TOPDIR=${Dev86_SOURCE_DIR}"
                "VERSION=${DEV86_VERSION}"
                "CC=ncc" "AR=ar86" "ARFLAGS=r"
                "PLATFORM=i86-ELKS"
        COMMAND "${CMAKE_COMMAND}" -E copy
                "${_bsd_out}" "${Dev86_STAGE_DIR}/lib/bcc/libbsd.a"
        COMMAND "${CMAKE_COMMAND}" -E make_directory
                "${CMAKE_BINARY_DIR}/stamps"
        COMMAND "${CMAKE_COMMAND}" -E touch "${_bsd_stamp}"
        DEPENDS dev86_libc dev86_stage_toolchain
        WORKING_DIRECTORY "${Dev86_SOURCE_DIR}"
        COMMENT "Cross-building libbsd for PLATFORM=i86-ELKS"
        VERBATIM)
    add_custom_target(dev86_libbsd ALL DEPENDS "${_bsd_stamp}")
    install(FILES "${_bsd_out}" DESTINATION lib/bcc)
endif()

# -- Install target headers ------------------------------------------------
# Headers are part of any libc-using install. Mirror the legacy
# install-lib's `install_incl` (cp -LpR include/* $(DISTINCL)/include).
# We dereference symlinks so linuxmt/ and arch/ become real dirs.
install(DIRECTORY "${Dev86_SOURCE_DIR}/libc/include/"
        DESTINATION lib/bcc/include
        FILES_MATCHING
            PATTERN "*.h"
            PATTERN "*"
            PATTERN "linuxmt" EXCLUDE  # handled below w/ FOLLOW_SYMLINK
            PATTERN "arch" EXCLUDE)

# linuxmt/ and arch/ are symlinks into libc/kinclude/ -- install the
# pointed-at dirs.
install(DIRECTORY "${Dev86_SOURCE_DIR}/libc/kinclude/linuxmt"
        DESTINATION lib/bcc/include FILES_MATCHING PATTERN "*.h")
install(DIRECTORY "${Dev86_SOURCE_DIR}/libc/kinclude/arch"
        DESTINATION lib/bcc/include FILES_MATCHING PATTERN "*.h")
