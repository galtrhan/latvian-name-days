# Latvian Name Days

CLI tool for looking up Latvian name days.

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

Debug (`zig build`): ~17 MB → ReleaseSmall: ~225 KB (~98% smaller).

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

Name lists are fetched from the [VVC](https://www.vvc.gov.lv/lv/latviesu-tradicionalo-kalendarvardu-saraksts)
(Latvian State Language Center) and cached locally (`~/.cache/lnd/namedays.json`, 30-day TTL).
If the network is unavailable, built-in data is used as fallback.
