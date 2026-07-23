# Latvian Name Days

CLI tool for looking up Latvian name days.

## Requirements

- A C compiler (`cc` / gcc / clang)
- `curl` (at runtime, to fetch data from VVC)

## Build

```sh
make
```

Binary: `dist/lnd`

Install to `~/.local/bin`:

```sh
make install
```

### Build flags

The Makefile builds with size optimization:

```sh
cc -O2 -s -ffunction-sections -fdata-sections lnd.c data.c -o dist/lnd \
  -Wl,--gc-sections
```

Release size: ~47 KB.

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

Name lists are fetched from the [VVC](https://www.vvc.gov.lv/lv/latviesu-tradicionalo-kalendarvardu-saraksts)
(Latvian State Language Center) and cached locally as CSV (`~/.cache/lnd/namedays.csv`, 30-day TTL).
If the cache is missing, expired, or the network is unavailable, built-in data is used as fallback.

### Cache format

```
version=1
cached_at=1700000000
---
1|1|Laimnesis, Solvita, Solvija
6|24|Jānis
```

Fields are pipe-separated so name lists can contain commas.

## Other implementations

| Language | Branch |
|---|---|
| Zig | `main` |
| Odin | `odin` |
| C | `c` (this branch) |

See [vs.md](vs.md) for a side-by-side comparison.
