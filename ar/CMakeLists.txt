# ar86 -- the 8086 archive tool.

# ar.c needs ar.h (from libc/include/) and rel_aout.h (from ld/).
# Don't add libc/include/ to the include path: it holds the 8086 target
# libc headers which would shadow the host's <stdlib.h>, <string.h>, ...
# Stage only the headers we actually need into a private dir.
set(_ar_staged_inc "${CMAKE_CURRENT_BINARY_DIR}/staged-includes")
file(COPY "${Dev86_SOURCE_DIR}/libc/include/ar.h" DESTINATION "${_ar_staged_inc}")
file(COPY "${Dev86_SOURCE_DIR}/ld/rel_aout.h"     DESTINATION "${_ar_staged_inc}")

add_executable(ar86 ar.c alloca.c)
target_include_directories(ar86 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${_ar_staged_inc}")
target_link_libraries(ar86 PRIVATE dev86_compat)

install(TARGETS ar86 RUNTIME DESTINATION bin)
