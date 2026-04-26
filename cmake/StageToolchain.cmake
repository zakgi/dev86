# StageToolchain.cmake -- assemble the just-built host binaries plus
# their data files (copt rules, target headers) into a single sibling
# tree under the build directory.
#
# Two consumers depend on this stage:
#   1. The cross-library build (libc, libbsd) -- see CrossLibraries.cmake.
#      Those subtrees are driven by GNU make and need to invoke `ncc`
#      with BCC_PREFIX pointing here so it can locate bcc-cc1, bcc-cpp,
#      copt, and the optimiser rules.
#   2. Downstream FetchContent consumers -- same reason. A project that
#      pulls dev86 in via FetchContent_MakeAvailable() and uses
#      $<TARGET_FILE:Dev86::ncc> in a custom command needs to set
#      BCC_PREFIX=${Dev86_STAGE_DIR} to make ncc work.
#
# Because (2) doesn't need the cross-libs to be built, the stage step
# is unconditional: it runs whenever the host toolchain is configured.

# bcc.c with empty LOCALPREFIX (ncc) plus BCC_PREFIX overrides walks
# paths relative to BCC_PREFIX:
#   ${BCC_PREFIX}/bin/{ncc,as86,ld86,ar86,...}
#   ${BCC_PREFIX}/lib/bcc/{bcc-cc1,bcc-cpp,unproto,copt,rules.*}
#   ${BCC_PREFIX}/lib/bcc/i386/rules.*
#   ${BCC_PREFIX}/lib/bcc/include/{...,linuxmt/,arch/}    <- target headers
# This is the same layout as a fully-installed dev86 tree under PREFIX.

set(Dev86_STAGE_DIR "${CMAKE_BINARY_DIR}/stage" CACHE PATH
    "Staged toolchain tree (use as BCC_PREFIX for ncc invocations).")
set(Dev86_INCLUDE_DIR "${Dev86_STAGE_DIR}/lib/bcc/include" CACHE PATH
    "Target (8086) include directory.")

file(MAKE_DIRECTORY
    "${Dev86_STAGE_DIR}/bin"
    "${Dev86_STAGE_DIR}/lib/bcc"
    "${Dev86_STAGE_DIR}/lib/bcc/i386")

# Helper: emit a custom command that symlinks $<TARGET_FILE:tgt> into
# the stage at $stage_subdir/$leaf, depending on the target so it
# reruns when the binary is rebuilt.
function(_dev86_stage_target tgt stage_subdir leaf)
    set(_dst "${Dev86_STAGE_DIR}/${stage_subdir}/${leaf}")
    add_custom_command(
        OUTPUT "${_dst}"
        COMMAND "${CMAKE_COMMAND}" -E create_symlink
                "$<TARGET_FILE:${tgt}>" "${_dst}"
        DEPENDS ${tgt}
        VERBATIM)
    set(_dev86_stage_outputs ${_dev86_stage_outputs} "${_dst}" PARENT_SCOPE)
endfunction()

# Helper: copy a static file (rules.*, headers, scripts) into the stage.
function(_dev86_stage_file src stage_subdir leaf)
    set(_dst "${Dev86_STAGE_DIR}/${stage_subdir}/${leaf}")
    add_custom_command(
        OUTPUT "${_dst}"
        COMMAND "${CMAKE_COMMAND}" -E create_symlink "${src}" "${_dst}"
        DEPENDS "${src}"
        VERBATIM)
    set(_dev86_stage_outputs ${_dev86_stage_outputs} "${_dst}" PARENT_SCOPE)
endfunction()

set(_dev86_stage_outputs)
_dev86_stage_target(ncc       bin ncc)
_dev86_stage_target(bcc       bin bcc)
_dev86_stage_target(as86      bin as86)
_dev86_stage_target(ld86      bin ld86)
_dev86_stage_target(ar86      bin ar86)
_dev86_stage_target(objdump86 bin objdump86)
_dev86_stage_target(bcc-cc1   lib/bcc bcc-cc1)
_dev86_stage_target(bcc-cpp   lib/bcc bcc-cpp)
_dev86_stage_target(unproto   lib/bcc unproto)
_dev86_stage_target(copt      lib/bcc copt)

# For each opt_arch, bcc invokes copt with `rules.start <archrules>
# rules.end` from a single -d directory. Stage all rules in lib/bcc/
# for 8086 / native modes and duplicate the start/386/end trio in
# lib/bcc/i386/ for the -Ml (Linux-i386) mode where the driver
# appends "/i386" to the lib path.
foreach(_r rules.86 rules.186 rules.i rules.net
           rules.start rules.386 rules.end)
    _dev86_stage_file(
        "${Dev86_SOURCE_DIR}/copt/${_r}" lib/bcc "${_r}")
endforeach()
foreach(_r rules.start rules.386 rules.end)
    _dev86_stage_file(
        "${Dev86_SOURCE_DIR}/copt/${_r}" lib/bcc/i386 "${_r}")
endforeach()

# Target headers: symlink ${stage}/lib/bcc/include -> libc/include/.
# linuxmt/ + arch/ inside libc/include get pre-symlinked to kinclude/
# (handled below) so the libc Makefile's `transfer:` target finds them.
add_custom_command(
    OUTPUT "${Dev86_STAGE_DIR}/lib/bcc/include"
    COMMAND "${CMAKE_COMMAND}" -E create_symlink
            "${Dev86_SOURCE_DIR}/libc/include" "${Dev86_STAGE_DIR}/lib/bcc/include"
    VERBATIM)
list(APPEND _dev86_stage_outputs "${Dev86_STAGE_DIR}/lib/bcc/include")

# linuxmt/ + arch/ symlinks live inside libc/include/ alongside the
# normal headers. The libc Makefile's `transfer:` target tries to create
# them itself if missing, but it points at $(ELKSSRC)/include/... -- we
# pre-create them pointing at the bundled kinclude/ instead, so any
# ELKSSRC=... value is irrelevant.
add_custom_command(
    OUTPUT "${Dev86_SOURCE_DIR}/libc/include/linuxmt"
    COMMAND "${CMAKE_COMMAND}" -E create_symlink
            "../kinclude/linuxmt"
            "${Dev86_SOURCE_DIR}/libc/include/linuxmt"
    VERBATIM)
add_custom_command(
    OUTPUT "${Dev86_SOURCE_DIR}/libc/include/arch"
    COMMAND "${CMAKE_COMMAND}" -E create_symlink
            "../kinclude/arch"
            "${Dev86_SOURCE_DIR}/libc/include/arch"
    VERBATIM)
list(APPEND _dev86_stage_outputs
    "${Dev86_SOURCE_DIR}/libc/include/linuxmt"
    "${Dev86_SOURCE_DIR}/libc/include/arch")

add_custom_target(dev86_stage_toolchain ALL DEPENDS ${_dev86_stage_outputs})
