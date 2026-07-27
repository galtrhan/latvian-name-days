# Latvian Name Days

`lnd` looks up Latvian name days from the command line.

## Requirements

- [Zig](https://ziglang.org/) (to build)
- `curl` (at runtime, to fetch data from VVC)

## Build

```sh
zig build
```

Binary: `zig-out/bin/lnd`

### Minimal binary size

```sh
zig build -Doptimize=ReleaseSmall
```

A debug build (`zig build`) is about 16 MB. A `ReleaseSmall` build is about 223 KB (about 99% smaller).

## Usage

```sh
# Today's name days
lnd

# Specific date
lnd -d 2026-05-22

# Refresh cached data from VVC
lnd --update
```

## Data source

The tool fetches name lists from the [VVC](https://www.vvc.gov.lv/lv/latviesu-tradicionalo-kalendarvardu-saraksts)
(Latvian State Language Center). It stores them locally (`~/.cache/lnd/namedays.json`, 30-day TTL).
If the network is unavailable, the tool uses built-in data.

## Other implementations

| Language | Branch |
|---|---|
| Zig | `main` (this branch) |
| Odin | `odin` |
| C | `c` |

See [vs.md](vs.md) for a comparison of the three versions.
