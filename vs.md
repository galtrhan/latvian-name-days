# Zig vs Odin vs C

This page compares the three `lnd` implementations.

| | **Zig** (`main`) | **Odin** (`odin`) | **C** (`c`) |
|---|---|---|---|
| Branch | `main` | `odin` | `c` |
| Build | `zig build -Doptimize=ReleaseSmall` | `make` | `make` |
| Binary | `zig-out/bin/lnd` | `dist/lnd` | `dist/lnd` |
| Release size | ~223 KB | ~259 KB | ~47 KB |
| Cache file | `~/.cache/lnd/namedays.json` | `~/.cache/lnd/namedays.csv` | `~/.cache/lnd/namedays.csv` |

The three versions use the same CLI, embedded fallback data, VVC `--update` fetch, and 30-day cache TTL.

## Source size

App code only (`main` + embedded data):

| | Zig | Odin | C |
|---|---:|---:|---:|
| Lines | 680 | 736 | 891 |
| Words | 5,781 | 5,103 | 3,528 |
| Size | 34.8 KB | 30.3 KB | 25.5 KB |

Per file:

| File | Lines | Words | Size |
|---|---:|---:|---:|
| `src/main.zig` / `lnd.odin` / `lnd.c` | 306 / 361 / 518 | 1,071 / 1,136 / 1,743 | 9.8 KB / 8.6 KB / 11.6 KB |
| `src/data.zig` / `data.odin` / `data.c` | 374 / 375 / 373 | 4,710 / 3,967 / 1,785 | 25.0 KB / 21.7 KB / 13.9 KB |

Zig also includes `build.zig` (34 lines, 0.9 KB). Odin and C use a `Makefile` instead. C also includes `data.h` (17 lines).

## Binary size

Sizes are from Linux x86_64 with size-optimized release builds:

| Build | Size |
|---|---:|
| Zig `ReleaseSmall` | 223 KB |
| Odin `-o:size -disable-assert` + strip + `--gc-sections` | 259 KB |
| C `-O2 -s` + `--gc-sections` | 47 KB |

C is the smallest (~5× smaller than Zig, ~5.5× smaller than Odin).

## Runtime

Lookup takes about 1 ms for all three. Process startup uses most of that time. Normal use is not I/O-bound.

## Differences

| Topic | Zig | Odin | C |
|---|---|---|---|
| Cache format | JSON | Pipe-delimited CSV | Pipe-delimited CSV |
| Date/time | `localtime_r` via libc | `libc.localtime` | `localtime_r` |
| Update fetch | `curl` via `std.process` | `curl` via `os.process_exec` | `curl` via `popen` |
| Fallback | Embedded `data.zig` | Embedded `data.odin` | Embedded `data.c` |

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
```
