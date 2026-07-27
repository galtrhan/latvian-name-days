# Latvian Name Days

`lnd` looks up Latvian name days from the command line.

## Requirements

- [Odin](https://odin-lang.org/) (to build)
- `curl` (at runtime, to fetch data from VVC)

## Build

```sh
make
```

Binary: `dist/lnd`

Install the binary to `~/.local/bin`:

```sh
make install
```

### Build flags

The Makefile builds for a small binary:

```sh
odin build . -out:dist/lnd -o:size -disable-assert \
  '-extra-linker-flags:-s -Wl,--gc-sections'
```

Release size: about 260 KB.

## Usage

```sh
# Today's name days
dist/lnd

# Specific date
dist/lnd -d 2026-05-22

# Refresh cached data from VVC
dist/lnd --update
```

## Data source

The tool fetches name lists from the [VVC](https://www.vvc.gov.lv/lv/latviesu-tradicionalo-kalendarvardu-saraksts)
(Latvian State Language Center). It stores them locally as CSV (`~/.cache/lnd/namedays.csv`, 30-day TTL).
If the cache is missing, expired, or the network is unavailable, the tool uses built-in data.

### Cache format

```
version=1
cached_at=1700000000
---
1|1|Laimnesis, Solvita, Solvija
6|24|Jānis
```

Fields use pipe separators so name lists can contain commas.

## Other implementations

| Language | Branch |
|---|---|
| Zig | `main` |
| Odin | `odin` (this branch) |
| C | `c` |

See [vs.md](vs.md) for a comparison of the three versions.
