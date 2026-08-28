# Zig vs Odin vs C vs TypePHP

This page compares the four `lnd` implementations.

| | **Zig** (`main`) | **Odin** (`odin`) | **C** (`c`) | **TypePHP** (`php`) |
|---|---|---|---|---|
| Branch | `main` | `odin` | `c` | `php` |
| Build | `zig build -Doptimize=ReleaseSmall` | `make` | `make` | `make` |
| Binary | `zig-out/bin/lnd` | `dist/lnd` | `dist/lnd` | `dist/lnd` |
| Release ELF | ~223 KB | ~259 KB | ~47 KB | ~287 KB |
| Runtime libs | none | none | none | `libphp.so` + `libphpx.so` (~25 MB stripped) |
| Cache file | `~/.cache/lnd/namedays.json` | `~/.cache/lnd/namedays.csv` | `~/.cache/lnd/namedays.csv` | `~/.cache/lnd/namedays.json` |

The four versions use the same CLI, embedded fallback data, VVC `--update` fetch, and 30-day cache TTL.

## Source size

App code only (`main` + embedded data):

| | Zig | Odin | C | TypePHP |
|---|---:|---:|---:|---:|
| Lines | 680 | 736 | 891 | 644 |
| Words | 5,781 | 5,103 | 3,528 | 2,627 |
| Size | 34.8 KB | 30.3 KB | 25.5 KB | 22.4 KB |

Per file:

| File | Lines | Words | Size |
|---|---:|---:|---:|
| `src/main.zig` / `lnd.odin` / `lnd.c` / `lnd.php` | 306 / 361 / 518 / 269 | 1,071 / 1,136 / 1,743 / 846 | 9.8 KB / 8.6 KB / 11.6 KB / 7.1 KB |
| `src/data.zig` / `data.odin` / `data.c` / `data.php` | 374 / 375 / 373 / 375 | 4,710 / 3,967 / 1,785 / 1,781 | 25.0 KB / 21.7 KB / 13.9 KB / 15.4 KB |

Zig also includes `build.zig` (34 lines, 0.9 KB). Odin and C use a `Makefile`. TypePHP uses a `Makefile` (30 lines, 0.8 KB) plus `project.yml` (9 lines). C also includes `data.h` (17 lines).

## Binary size

Sizes are from Linux x86_64 with size-optimized release builds.

| Build | ELF size |
|---|---:|
| Zig `ReleaseSmall` | 223 KB |
| Odin `-o:size -disable-assert` + strip + `--gc-sections` | 259 KB |
| C `-O2 -s` + `--gc-sections` | 47 KB |
| TypePHP `-O2 --lto` + strip | 287 KB |

C is the smallest standalone ELF (~5× smaller than Zig, ~5.5× smaller than Odin, ~6× smaller than TypePHP).

TypePHP is a different class of binary. The ELF is 287 KB, close to Zig and Odin, because it is dynamically linked. At start it loads:

| Library | Stripped size |
|---|---:|
| `libphp.so` (embed SAPI) | 23.3 MB |
| `libphpx.so` | 1.4 MB |
| `lnd` + both libs | 24.9 MB |

Zig, Odin, and C do not need those libraries. A fair TypePHP deploy size is about 25 MB, not 287 KB.

## Runtime

Lookup takes about 1 ms for Zig, Odin, and C. Process startup uses most of that time.

TypePHP takes about 30 ms for the same lookup. The extra time is PHP embed startup, not the name table scan. Normal use is still not I/O-bound.

## Differences

| Topic | Zig | Odin | C | TypePHP |
|---|---|---|---|---|
| Cache format | JSON | Pipe-delimited CSV | Pipe-delimited CSV | JSON |
| Date/time | `localtime_r` via libc | `libc.localtime` | `localtime_r` | PHP `localtime` after `/etc/timezone` |
| Update fetch | `curl` via `std.process` | `curl` via `os.process_exec` | `curl` via `popen` | `curl` via `shell_exec` |
| Fallback | Embedded `data.zig` | Embedded `data.odin` | Embedded `data.c` | Embedded `data.php` |

## Build commands

```sh
# Zig (main branch)
git checkout main
zig build -Doptimize=ReleaseSmall

# Odin (odin branch)
git checkout odin
make

# C (c branch)
git checkout c
make

# TypePHP (php branch)
git checkout php
make
```
