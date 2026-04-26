# ld86, objdump86 -- the 8086 linker and a multi-tool dumper that also
# masquerades as nm86/size86 via filename dispatch.

dev86_write_version_h("${CMAKE_CURRENT_BINARY_DIR}/version.h")

# ld and objdump86 need ar.h. The legacy build symlinks libc/include/ar.h
# next to the source. We can't just add libc/include/ to the include path
# because that directory holds the 8086 *target* libc headers (stdlib.h,
# string.h, ...) which would shadow the host's. Stage a copy of only the
# headers we need into a private dir under the build tree.
set(_ld_staged_inc "${CMAKE_CURRENT_BINARY_DIR}/staged-includes")
file(COPY "${Dev86_SOURCE_DIR}/libc/include/ar.h"
     DESTINATION "${_ld_staged_inc}")

set(LD86_SOURCES
    dumps.c io.c ld.c readobj.c table.c typeconv.c linksyms.c mkar.c
    writex86.c writebin.c writeemu.c)

add_executable(ld86 ${LD86_SOURCES})
target_include_directories(ld86 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${_ld_staged_inc}")
target_compile_definitions(ld86 PRIVATE REL_OUTPUT)
target_link_libraries(ld86 PRIVATE dev86_compat)

# objdump86 is a single-file program. The driver shell-game (one binary
# answering to nm86/size86 too) is implemented inside the program itself:
# it inspects argv[0]. We replicate the legacy install behaviour by
# install-symlinking the same binary under the alternate names.
add_executable(objdump86 objdump86.c)
target_include_directories(objdump86 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${_ld_staged_inc}")
target_link_libraries(objdump86 PRIVATE dev86_compat)

install(TARGETS ld86 objdump86 RUNTIME DESTINATION bin)

# Install nm86 and size86 as symlinks/copies of objdump86 -- the program
# reads argv[0] to decide which mode to run in.
install(CODE "
    set(_dst \"\${CMAKE_INSTALL_PREFIX}/bin\")
    file(CREATE_LINK objdump86 \"\${_dst}/nm86\" SYMBOLIC)
    file(CREATE_LINK objdump86 \"\${_dst}/size86\" SYMBOLIC)
")
