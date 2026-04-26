# unproto -- strips ANSI prototypes for old-style K&R compilers.

set(UNPROTO_SOURCES
    unproto.c tok_io.c tok_class.c tok_pool.c vstring.c symbol.c
    error.c hash.c strsave.c)

add_executable(unproto ${UNPROTO_SOURCES})
target_compile_options(unproto PRIVATE -w)
target_compile_definitions(unproto PRIVATE REOPEN)
# Important: do NOT add the source dir to the -I path. unproto/ contains
# a local stdarg.h (a fallback for pre-ANSI compilers) that would shadow
# the host's <stdarg.h> if put on -I. Local headers are still found via
# the implicit source-dir search done for quote-style #include "..."
target_link_libraries(unproto PRIVATE dev86_compat)

install(TARGETS unproto RUNTIME DESTINATION lib/bcc)
