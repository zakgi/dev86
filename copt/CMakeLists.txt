# copt -- peephole optimiser, plus the rule files it operates on.

add_executable(copt copt.c)
target_link_libraries(copt PRIVATE dev86_compat)

install(TARGETS copt RUNTIME DESTINATION lib/bcc)

# Optimiser rule files. For each opt_arch, bcc invokes copt with
# `rules.start <archrules> rules.end` from a single -d dir. So all the
# bracket and arch rules (start/end/86/186/i/net/386) need to live in
# lib/bcc/ for 8086 / native modes, and the start/386/end trio is also
# duplicated under lib/bcc/i386/ for the -Ml (Linux-i386) mode where
# the driver appends "/i386" to the lib path.
install(FILES
        rules.86 rules.186 rules.i rules.net
        rules.start rules.386 rules.end
    DESTINATION lib/bcc)
install(FILES
        rules.start rules.386 rules.end
    DESTINATION lib/bcc/i386)
