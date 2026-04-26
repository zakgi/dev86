# bcc -- Bruce's C Compiler.
#
# Builds two executables:
#   bcc-cc1   -- the compiler proper (cc1) consisting of the OBJS list below.
#   bcc       -- the small driver program that orchestrates cpp/cc1/as/ld.
#
# We also build `ncc`, a variant of the driver compiled with an empty
# LOCALPREFIX so it locates its sub-tools relative to the build tree --
# useful for running the just-built compiler in-place without installing.

dev86_write_version_h("${CMAKE_CURRENT_BINARY_DIR}/version.h")

set(BCC_CC1_SOURCES
    bcc-cc1.c codefrag.c dbnode.c declare.c express.c exptree.c floatop.c
    function.c gencode.c genloads.c glogcode.c hardop.c input.c label.c
    loadexp.c longop.c output.c preproc.c preserve.c scan.c softop.c
    state.c table.c type.c assign.c hashcmd.c debug.c dbprintf.c)

add_executable(bcc-cc1 ${BCC_CC1_SOURCES})
target_include_directories(bcc-cc1 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}")  # for version.h
target_link_libraries(bcc-cc1 PRIVATE dev86_compat)

# The driver. It needs LOCALPREFIX/BINDIR/DEFARCH set at compile time so it
# can locate cpp, cc1, as86, ld86, and the optimiser rules at runtime.
add_executable(bcc bcc.c)
target_include_directories(bcc PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}")
target_compile_definitions(bcc PRIVATE
    LOCALPREFIX=${DEV86_LOCALPREFIX}
    BINDIR=${DEV86_LOCALPREFIX}/bin
    LIBDIR=${DEV86_LOCALPREFIX}/lib/bcc
    DEFARCH=0)
target_link_libraries(bcc PRIVATE dev86_compat)

# ncc -- same source, but with an empty LOCALPREFIX so the driver uses
# build-tree-relative paths. The bcc driver branches on whether
# QUOT(LOCALPREFIX) is one of: empty, "/", or anything else. We need
# *literally empty* on the command line -- not -DLOCALPREFIX="" which
# CMake's target_compile_definitions(name=) emits and which makes
# QUOT(...) expand to a 2-byte string of two quote characters and trips
# the wrong branch. Pass via target_compile_options to keep verbatim.
add_executable(ncc bcc.c)
target_include_directories(ncc PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}")
target_compile_options(ncc PRIVATE -DLOCALPREFIX= -DDEFARCH=0)
target_link_libraries(ncc PRIVATE dev86_compat)

# Install the driver in $prefix/bin and the compiler proper in
# $prefix/lib/bcc -- bcc.c hard-codes those subpaths relative to LOCALPREFIX.
install(TARGETS bcc     RUNTIME DESTINATION bin)
install(TARGETS bcc-cc1 RUNTIME DESTINATION lib/bcc)
