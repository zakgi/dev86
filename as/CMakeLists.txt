# as86 -- the assembler.

dev86_write_version_h("${CMAKE_CURRENT_BINARY_DIR}/version.h")

set(AS86_SOURCES
    as.c assemble.c errors.c express.c
    genbin.c genlist.c genobj.c gensym.c
    keywords.c macro.c mops.c pops.c readsrc.c
    scan.c table.c typeconv.c alloc.c)

add_executable(as86 ${AS86_SOURCES})
target_include_directories(as86 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(as86 PRIVATE dev86_compat)

# as86_encap is a shell wrapper script with %%LIBDIR%% / %%BINDIR%% sed-substituted.
# Generate it at configure time using CMake's own configure_file mechanism so we
# don't need to invoke sed at all. The original sh script's sentinel tokens
# (%%LIBDIR%%, %%BINDIR%%) aren't @VAR@ syntax, so we do plain string replace.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/as86_encap.sh" _encap_in)
string(REPLACE "%%LIBDIR%%" "${DEV86_LOCALPREFIX}/lib/bcc" _encap_out "${_encap_in}")
string(REPLACE "%%BINDIR%%" "${DEV86_LOCALPREFIX}/bin"     _encap_out "${_encap_out}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/as86_encap" "${_encap_out}")
file(CHMOD "${CMAKE_CURRENT_BINARY_DIR}/as86_encap"
     PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                 GROUP_READ GROUP_EXECUTE
                 WORLD_READ WORLD_EXECUTE)

install(TARGETS as86 RUNTIME DESTINATION bin)
install(PROGRAMS "${CMAKE_CURRENT_BINARY_DIR}/as86_encap" DESTINATION bin)
