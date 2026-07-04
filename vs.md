# Zig vs Odin

Side-by-side comparison of the two implementations of `lnd`.

| | **Zig** (`main`) | **Odin** (`odin`) |
|---|---|---|
| Branch | `main` | `odin` |
| Build | `zig build -Doptimize=ReleaseSmall` | `make` |
| Binary | `zig-out/bin/lnd` | `dist/lnd` |
| Release size | ~223 KB | ~259 KB |
| Cache file | `~/.cache/lnd/namedays.json` | `~/.cache/lnd/namedays.csv` |

Both share the same CLI, embedded fallback data, VVC `--update` fetch, and 30-day cache TTL.

## Source size

App code only (`main` + embedded data):

| | Zig | Odin | Δ (Odin vs Zig) |
|---|---:|---:|---:|
| Lines | 680 | 736 | +56 (+8.2%) |
| Words | 5,781 | 5,103 | −678 (−11.7%) |
| Size | 34.8 KB | 30.3 KB | −4.5 KB (−12.9%) |

Per file:

| File | Lines | Words | Size |
|---|---:|---:|---:|
| `src/main.zig` / `lnd.odin` | 306 / 361 | 1,071 / 1,136 | 9.8 KB / 8.6 KB |
| `src/data.zig` / `data.odin` | 374 / 375 | 4,710 / 3,967 | 25.0 KB / 21.7 KB |

Zig also has `build.zig` (34 lines, 0.9 KB). Odin uses a `Makefile` instead.

## Binary size

Measured on Linux x86_64 with size-optimized release builds:

| Build | Size |
|---|---:|
| Zig `ReleaseSmall` | 223 KB |
| Odin `-o:size -disable-assert` + strip + `--gc-sections` | 259 KB |

Odin is ~16% larger. The Odin build avoids `encoding/json` (CSV cache instead), which closed much of an earlier gap.

## Runtime

Lookup is effectively instant for both (~1 ms, dominated by process startup). Neither implementation is I/O-bound for normal use.

## Differences

| Topic | Zig | Odin |
|---|---|---|
| Cache format | JSON | Pipe-delimited CSV |
| Date/time | `localtime_r` via libc | `libc.localtime` |
| Update fetch | `curl` via `std.process` | `curl` via `os.process_exec` |
| Fallback | Embedded `data.zig` | Embedded `data.odin` |

## Build commands

```sh
# Zig (main branch)
git checkout main
zig build -Doptimize=ReleaseSmall

# Odin (odin branch)
git checkout odin
make
```
