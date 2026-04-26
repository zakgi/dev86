# bcc-cpp -- the C preprocessor.
#
# token1.h and token2.h are gperf-generated from token1.tok / token2.tok.
# They're already checked in to the repo, so the build doesn't depend on
# gperf being present. Only re-run gperf if those files are missing or
# the .tok files are newer (and gperf is found).

find_program(GPERF_EXECUTABLE gperf)

function(_dev86_cpp_gperf _name _opts_var)
    set(_tok "${CMAKE_CURRENT_SOURCE_DIR}/${_name}.tok")
    set(_h   "${CMAKE_CURRENT_SOURCE_DIR}/${_name}.h")
    if(NOT EXISTS "${_h}" AND GPERF_EXECUTABLE)
        execute_process(
            COMMAND ${GPERF_EXECUTABLE} ${${_opts_var}} "${_tok}"
            OUTPUT_FILE "${_h}")
    elseif(NOT EXISTS "${_h}")
        message(FATAL_ERROR
            "${_h} is missing and gperf was not found on PATH. "
            "Install gperf (brew install gperf) or restore the file from upstream.")
    endif()
endfunction()

set(_t1_opts -aptTc -N is_ctok -H hash1)
set(_t2_opts -aptTc -k1,3 -N is_ckey -H hash2)
_dev86_cpp_gperf(token1 _t1_opts)
_dev86_cpp_gperf(token2 _t2_opts)

add_executable(bcc-cpp main.c cpp.c hash.c token1.c token2.c)
target_include_directories(bcc-cpp PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(bcc-cpp PRIVATE dev86_compat)

install(TARGETS bcc-cpp RUNTIME DESTINATION lib/bcc)
