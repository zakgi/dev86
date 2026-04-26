# dev86 -- CMake build

This fork adds a CMake-based build system for dev86 that builds the
host toolchain plus the cross-target C libraries in one configure /
build / install flow. The legacy GNU-make build (`Makefile`,
`makefile.in`, `ifdef.c`) is left untouched and still works where it
worked before; the CMake build is the recommended path.

> Tested on macOS Tahoe 26.3 with the Xcode Command Line Tools (Apple
> Clang + bundled CMake). Should also work on Linux (x86_64 / arm64)
> with GCC or Clang.

## What gets built

**Host toolchain** -- native binaries for the cross-development tools:

| Binary       | What it is                                          | Installed to    |
|--------------|-----------------------------------------------------|-----------------|
| `bcc`        | Driver -- orchestrates cpp -> unproto -> cc1 -> as -> ld | `bin/`          |
| `bcc-cc1`    | The C compiler proper                               | `lib/bcc/`      |
| `bcc-cpp`    | C preprocessor                                      | `lib/bcc/`      |
| `unproto`    | Strips ANSI prototypes for K&R back-ends            | `lib/bcc/`      |
| `copt`       | Peephole optimiser + rule files                     | `lib/bcc/`      |
| `as86`       | Assembler                                           | `bin/`          |
| `as86_encap` | Shell wrapper for embedding asm output in C         | `bin/`          |
| `ld86`       | Linker                                              | `bin/`          |
| `ar86`       | Archiver                                            | `bin/`          |
| `objdump86`  | Object/exe dumper (also installed as `nm86`/`size86`) | `bin/`        |

`ncc` is also built -- same source as `bcc` but with empty `LOCALPREFIX`,
so it locates its sub-tools from the build tree using `BCC_PREFIX`.
Used internally by the cross-library build.

**Cross-target libraries** -- 8086 artefacts produced by running the
just-built toolchain against `libc/` and `libbsd/`. By default:

  - `libc.a` + `crt0.o`  (PLATFORM=`i86-ELKS`, the standard ELKS variant)
  - `libbcc.a`           (BCC compiler runtime: long arith, integer divmod)
  - `libbsd.a`

Plus the target headers from `libc/include/` (and the bundled kernel
headers from `libc/kinclude/`) installed under `lib/bcc/include/`.

Other libc PLATFORM variants are off by default -- see "Options" below.

## Prerequisites

  - On macOS: the Xcode Command Line Tools (`xcode-select --install`)
    cover everything you need -- Apple Clang, CMake, and GNU make.
  - On Linux: GCC or Clang, CMake >= 3.19, and GNU make.
  - **Avoid GNU make 3.82** -- it has bug #30612 that breaks the libc
    subtree. The configure step warns if it finds 3.82. macOS's
    bundled `/usr/bin/make` is 3.81 and works; recent Linuxes ship
    GNU make >= 4.0.
  - Optional: `gperf` -- only needed if you change `cpp/token1.tok` or
    `cpp/token2.tok`. The generated headers are checked in.

## Build

    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build --parallel

Install (defaults to `/usr/local`; pass `-DCMAKE_INSTALL_PREFIX=...` to
override):

    cmake --install build --prefix /opt/dev86

The driver `bcc` embeds the install prefix at build time so it knows
where to find `bcc-cc1`, `bcc-cpp`, `copt`, the rules files, and the
target headers at runtime. If you install to a non-default location,
configure with that prefix:

    cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/dev86

If you want the binaries to look up their helpers under a *different*
runtime path than the install prefix (DESTDIR-style staged installs,
package builds), pass `-DDEV86_LOCALPREFIX=/runtime/path` separately.

`BCC_PREFIX` env var also overrides the embedded prefix at runtime --
handy for testing an installed tree at a different mount point.

## Verifying

After install, with `/opt/dev86/bin` on `PATH`:

    cat > hi.c <<EOF
    int main(void) { write(1, "hi from 8086\n", 13); return 0; }
    EOF
    bcc -ansi -Mn hi.c -o hi.elks      # full link
    file hi.elks                        # -> "Linux-8086 executable not stripped"
    objdump86 hi.elks                   # full disassembly + symbol table

For a quick sanity check straight out of the build tree (no install):

    BCC_PREFIX=$PWD/build/stage build/stage/bin/ncc -ansi -Mn hi.c -o hi.elks

## Options

### Per-tool toggles

All host toolchain components are `ON` by default:

  - `DEV86_BUILD_BCC`, `DEV86_BUILD_AS`, `DEV86_BUILD_LD`, `DEV86_BUILD_AR`,
    `DEV86_BUILD_CPP`, `DEV86_BUILD_COPT`, `DEV86_BUILD_UNPROTO`

Disable any from the configure line:

    cmake -S . -B build -DDEV86_BUILD_UNPROTO=OFF

### Cross-library variants

`DEV86_BUILD_LIBC` (`i86-ELKS`) and `DEV86_BUILD_LIBBSD` are `ON`.
Alternative libc PLATFORM variants are `OFF` -- flip on as needed:

| Option                       | PLATFORM    | Output         |
|------------------------------|-------------|----------------|
| `-DDEV86_BUILD_LIBC_FAST=ON` | i86-FAST    | `libc_f.a`     |
| `-DDEV86_BUILD_LIBC_STAND=ON`| i86-BIOS    | `libc_s.a`     |
| `-DDEV86_BUILD_LIBC_DOS=ON`  | i86-DOS     | `libdos.a`     |
| `-DDEV86_BUILD_LIBC_386=ON`  | i386-BCC    | `libc3.a` + `crt3.o` |

Library variants share the libc source tree and clean each other's
`.o` files between PLATFORM passes (different `ARCH` produces
incompatible objects). They serialise via `add_dependencies` so a
`--parallel` build won't race them.

## How the cross-library build is wired

CMake doesn't translate libc's nested Makefiles -- there are 17+ subdirs
each with its own GNU-make-isms (archive `lib(member)` rules,
generated `syscall.mak`, etc.). Instead it stages the just-built host
toolchain into a build-tree layout that `ncc` recognises:

    build/stage/bin/{ncc, as86, ld86, ar86, ...}
    build/stage/lib/bcc/{bcc-cc1, bcc-cpp, unproto, copt, rules.*}
    build/stage/lib/bcc/i386/rules.*
    build/stage/lib/bcc/include/   -> libc/include (with linuxmt/, arch/)

...then runs the existing `make -C libc PLATFORM=... CC=ncc AR=ar86 ...`
with that stage on `BCC_PREFIX` and `PATH`. Outputs are also copied
into the stage so subsequent `ld86 -L...` invocations in the same
build can find them without an install.

## Using dev86 from another CMake project (FetchContent)

dev86 is wired up so a downstream project can pull it in via
`FetchContent` and reference its tools as imported targets in custom
commands. Useful for, e.g., building a Bochs BIOS, an ELKS module, or
any 8086 artefact as part of a larger CMake build.

```cmake
include(FetchContent)
FetchContent_Declare(dev86
    GIT_REPOSITORY https://github.com/<you>/dev86.git
    GIT_TAG        apple-silicon)
FetchContent_MakeAvailable(dev86)
```

After `MakeAvailable`, downstream sees:

**Imported targets** (in the `Dev86::` namespace, gated by their
`DEV86_BUILD_<X>` option):

| Target              | Tool        |
|---------------------|-------------|
| `Dev86::bcc`        | driver      |
| `Dev86::ncc`        | driver, build-tree-relative path lookup |
| `Dev86::bcc-cc1`    | C compiler  |
| `Dev86::bcc-cpp`    | preprocessor|
| `Dev86::unproto`    | deprototyper|
| `Dev86::copt`       | optimiser   |
| `Dev86::as86`       | assembler   |
| `Dev86::ld86`       | linker      |
| `Dev86::ar86`       | archiver    |
| `Dev86::objdump86`  | dumper      |

Use them via generator expressions: `$<TARGET_FILE:Dev86::ld86>`.

**Cached path variables**:

| Variable             | What                                              |
|----------------------|---------------------------------------------------|
| `Dev86_STAGE_DIR`    | Pass as `BCC_PREFIX` when invoking ncc            |
| `Dev86_INCLUDE_DIR`  | Target (8086) header dir, `-I` this              |
| `Dev86_LIBC_FILE`    | `libc.a`         (if `DEV86_BUILD_LIBC`)         |
| `Dev86_CRT0_FILE`    | `crt0.o`         (   "  )                         |
| `Dev86_LIBBCC_FILE`  | `libbcc.a`       (   "  )                         |
| `Dev86_LIBC_FAST_FILE`  | `libc_f.a`    (`DEV86_BUILD_LIBC_FAST`)        |
| `Dev86_LIBC_STAND_FILE` | `libc_s.a`    (`DEV86_BUILD_LIBC_STAND`)       |
| `Dev86_LIBDOS_FILE`     | `libdos.a`    (`DEV86_BUILD_LIBC_DOS`)         |
| `Dev86_LIBC_386_FILE`   | `libc.a` i386 (`DEV86_BUILD_LIBC_386`)         |
| `Dev86_CRT0_386_FILE`   | `crt0.o` i386 (`DEV86_BUILD_LIBC_386`)         |
| `Dev86_LIBBSD_FILE`     | `libbsd.a`    (`DEV86_BUILD_LIBBSD`)           |
| `Dev86_VERSION`         | dev86 version string                          |

**Helper target**:

  - `dev86_stage_toolchain` -- depend on this from custom commands that
    invoke `ncc`, so the staged toolchain tree exists before they run.

### Worked example: assemble + link a tiny program

```cmake
include(FetchContent)
FetchContent_Declare(dev86 GIT_REPOSITORY ... GIT_TAG apple-silicon)
FetchContent_MakeAvailable(dev86)

# Compile a single C source via ncc.
add_custom_command(
    OUTPUT  hello.o
    COMMAND ${CMAKE_COMMAND} -E env
            "BCC_PREFIX=${Dev86_STAGE_DIR}"
            $<TARGET_FILE:Dev86::ncc>
                -ansi -Mn -c ${CMAKE_CURRENT_SOURCE_DIR}/hello.c -o hello.o
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/hello.c
            Dev86::ncc Dev86::bcc-cc1 Dev86::bcc-cpp
            Dev86::unproto Dev86::copt Dev86::as86
            dev86_stage_toolchain)

# Link against the cross-built libc. ld86 args have NO space between
# flag and value (e.g. -Llibdir, -Ccrtsuffix). -L must come before -C
# because expandlib only sees previously-declared library paths.
add_custom_command(
    OUTPUT  hello.elks
    COMMAND $<TARGET_FILE:Dev86::ld86>
                -0
                "-L${Dev86_STAGE_DIR}/lib/bcc"
                -C0           # use crt0.o from -L paths
                -o hello.elks
                hello.o -lc
    DEPENDS hello.o "${Dev86_LIBC_FILE}" "${Dev86_CRT0_FILE}"
            Dev86::ld86 dev86_libc)

add_custom_target(hello ALL DEPENDS hello.elks)
```

For pure-asm BIOS-style projects, you can drop the C bits entirely
and drive `Dev86::as86` and `Dev86::ld86` directly:

```cmake
add_custom_command(
    OUTPUT  bios.o
    COMMAND $<TARGET_FILE:Dev86::as86>
                -0 -b -o bios.o ${CMAKE_CURRENT_SOURCE_DIR}/bios.s
    DEPENDS Dev86::as86 ${CMAKE_CURRENT_SOURCE_DIR}/bios.s)
```

### Disabling parts of the dev86 build

A consumer that doesn't need a particular libc variant or even any
libc can turn it off before the FetchContent_MakeAvailable():

```cmake
set(DEV86_BUILD_LIBC   OFF CACHE BOOL "" FORCE)
set(DEV86_BUILD_LIBBSD OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(dev86)
```

The host toolchain (bcc, as86, ld86, ...) is always built.

## Out of scope

`bootblocks/`, `dis88/`, `doselks/`, `elksemu/`, `tests/` are still
left to the legacy `make`. They have additional GNU-make / Linux-host
assumptions that haven't been addressed in this fork. Once the host
toolchain is installed, `make other` from the top level should still
work where the underlying tools support the host platform.

The legacy top-level `Makefile` build is preserved and untouched on
Linux.

## Portability notes

The CMake build needs surprisingly few changes to dev86 sources:

  - All the Linux-only `<malloc.h>` includes throughout the tree are
    already gated behind `#ifndef __STDC__`, so modern compilers take
    the `<stdlib.h>` branch transparently.

  - K&R-style function declarations and definitions trip newer compilers
    (Clang >= 16 / Xcode 15 default `-Wimplicit-function-declaration`
    and `-Wimplicit-int` to errors). The CMake build downgrades these
    to warnings via an `INTERFACE` flag library (`dev86_compat`)
    probed at configure time.

  - `unproto/stdarg.h` and `libc/include/` would shadow the host's
    `<stdarg.h>` / `<stdlib.h>` if their dirs were put on `-I`. The
    CMake build keeps them off `-I` and stages only the headers
    actually needed (`ar.h`, `rel_aout.h`) into a private include
    directory under the build tree.

  - The `-no-cpp-precomp` flag the legacy `makefile.in` adds for
    `__APPLE__` was a workaround for Apple's pre-2002 `cpp-precomp`
    preprocessor. Modern Apple Clang doesn't have or accept it, so the
    CMake build simply doesn't pass it.

  - `ncc` needs `LOCALPREFIX` defined to a *literal empty token* (so
    `QUOT(LOCALPREFIX)` expands to `""` of length 0). CMake's
    `target_compile_definitions(name=)` emits `-DLOCALPREFIX=""` which
    is a 2-byte string and trips bcc.c into the wrong path-resolution
    branch; the build uses `target_compile_options(-DLOCALPREFIX=)`
    instead so the value passes through verbatim.

## Build artefacts in the source tree

The libc/libbsd cross-build runs in-source (the legacy Makefiles write
.o and .a files next to their sources). The provided `.gitignore`
covers all of them, plus the headers each libc subdir's `transfer:`
target copies into `libc/include/` (`stdio.h`, `string.h`, `malloc.h`,
`regexp.h`, `regmagic.h` -- all generated, not source). To wipe them:

    cmake --build build --target dev86_libc -- clean   # per-variant
    rm -rf build                                        # everything CMake-side
