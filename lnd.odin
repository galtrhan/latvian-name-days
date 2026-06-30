package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:c/libc"

VVC_URL :: "https://www.vvc.gov.lv/lv/latviesu-tradicionalo-kalendarvardu-saraksts"
CACHE_SECONDS :: 30 * 86400
CACHE_VERSION :: 1

Date :: struct {
	year:   u16,
	month:  u8,
	day:    u8,
	hour:   u8,
	minute: u8,
}

MONTH_NAMES := [12]string{
	"JANVĀRIS", "FEBRUĀRIS", "MARTS", "APRĪLIS", "MAIJS", "JŪNIJS",
	"JŪLIJS", "AUGUSTS", "SEPTEMBRIS", "OKTOBRIS", "NOVEMBRIS", "DECEMBRIS",
}

today :: proc() -> Date {
	ts: libc.time_t
	libc.time(&ts)
	t := libc.localtime(&ts)
	return Date{
		year   = u16(t.tm_year + 1900),
		month  = u8(t.tm_mon + 1),
		day    = u8(t.tm_mday),
		hour   = u8(t.tm_hour),
		minute = u8(t.tm_min),
	}
}

parse_date :: proc(s: string) -> (Date, bool) {
	if len(s) < 10 || s[4] != '-' || s[7] != '-' {
		return {}, false
	}
	year, y_ok := strconv.parse_u64(s[:4])
	month, m_ok := strconv.parse_u64(s[5:7])
	day, d_ok := strconv.parse_u64(s[8:10])
	if !y_ok || !m_ok || !d_ok {
		return {}, false
	}
	if month < 1 || month > 12 || day < 1 || day > 31 {
		return {}, false
	}
	return Date{year = u16(year), month = u8(month), day = u8(day)}, true
}

parse_cache_line :: proc(line: string, allocator := context.allocator) -> (entry: Entry, ok: bool) {
	first := strings.index_byte(line, '|')
	if first < 0 do return
	second := strings.index_byte(line[first + 1:], '|')
	if second < 0 do return
	second += first + 1

	month, m_ok := strconv.parse_u64(line[:first])
	day, d_ok := strconv.parse_u64(line[first + 1:second])
	if !m_ok || !d_ok do return

	names, alloc_err := strings.clone(line[second + 1:], allocator)
	if alloc_err != nil do return
	return Entry{month = u8(month), day = u8(day), names = names}, true
}

parse_cache :: proc(content: string, allocator := context.allocator) -> (entries: [dynamic]Entry, cached_at: i64, ok: bool) {
	lines := strings.split_lines(content, allocator)
	defer delete(lines)

	cached_at = 0
	in_data := false

	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 do continue

		if strings.has_prefix(trimmed, "cached_at=") {
			cached_at, _ = strconv.parse_i64_of_base(trimmed[len("cached_at="):], 10)
			continue
		}
		if trimmed == "---" {
			in_data = true
			continue
		}
		if !in_data do continue

		entry, parsed := parse_cache_line(trimmed, allocator)
		if parsed {
			append(&entries, entry)
		}
	}

	ok = len(entries) > 0
	return
}

lookup :: proc(entries: []Entry, month, day: u8) -> (string, bool) {
	for e in entries {
		if e.month == month && e.day == day {
			return e.names, true
		}
	}
	return "", false
}

get_cache_path :: proc(allocator := context.allocator) -> (path: string, err: os.Error) {
	xdg_cache := os.get_env("XDG_CACHE_HOME", allocator)
	defer if xdg_cache != "" {
		delete(xdg_cache, allocator)
	}
	if xdg_cache == "" {
		home := os.get_env("HOME", allocator)
		defer delete(home, allocator)
		if home == "" {
			home = "."
		}
		return os.join_path({home, ".cache", "lnd", "namedays.csv"}, allocator)
	}
	return os.join_path({xdg_cache, "lnd", "namedays.csv"}, allocator)
}

embedded_entries :: proc(allocator := context.allocator) -> (result: [dynamic]Entry, err: os.Error) {
	for e in EMBEDDED_ENTRIES {
		names := strings.clone(e.names, allocator) or_return
		append(&result, Entry{month = e.month, day = e.day, names = names})
	}
	return
}

load_entries :: proc(allocator := context.allocator) -> (result: [dynamic]Entry, err: os.Error) {
	cache_path := get_cache_path(allocator) or_return
	defer delete(cache_path, allocator)

	content, read_err := os.read_entire_file(cache_path, allocator)
	if read_err == nil {
		defer delete(content, allocator)

		cached, cached_at, parse_ok := parse_cache(string(content), allocator)
		defer if parse_ok {
			for e in cached {
				delete(e.names, allocator)
			}
			delete(cached)
		}

		if parse_ok {
			now := time.time_to_unix(time.now())
			age := now - cached_at
			if age >= 0 && age < CACHE_SECONDS {
				for e in cached {
					names := strings.clone(e.names, allocator) or_return
					append(&result, Entry{month = e.month, day = e.day, names = names})
				}
				return
			}
		}
	}

	return embedded_entries(allocator)
}

save_cache :: proc(entries: []Entry, allocator := context.allocator) -> os.Error {
	cache_path := get_cache_path(allocator) or_return
	defer delete(cache_path, allocator)

	dir := os.dir(cache_path)
	if dir != "" {
		os.make_directory_all(dir) or_return
	}

	b: strings.Builder
	strings.builder_init(&b, allocator)
	defer strings.builder_destroy(&b)

	fmt.sbprintfln(&b, "version=%d", CACHE_VERSION)
	fmt.sbprintfln(&b, "cached_at=%d", time.time_to_unix(time.now()))
	fmt.sbprintfln(&b, "---")
	for e in entries {
		fmt.sbprintfln(&b, "%d|%d|%s", e.month, e.day, e.names)
	}

	return os.write_entire_file(cache_path, strings.to_string(b))
}

parse_vvc_html :: proc(html: string, allocator := context.allocator) -> (entries: [dynamic]Entry, err: os.Error) {
	current_month: u8 = 0
	current_day: u8 = 0
	in_month_section := false

	pos := 0
	for pos < len(html) {
		matched_month := false
		for mn, i in MONTH_NAMES {
			search := fmt.tprintf(">%s</button>", mn)
			if pos + len(search) <= len(html) && html[pos:pos + len(search)] == search {
				current_month = u8(i + 1)
				current_day = 0
				in_month_section = true
				matched_month = true
				pos += len(search)
				break
			}
		}
		if matched_month do continue

		if in_month_section {
			li_tag := "<li>"
			if pos + len(li_tag) <= len(html) && strings.has_prefix(html[pos:], li_tag) {
				pos += len(li_tag)
				close_tag := "</li>"
				end_offset := strings.index(html[pos:], close_tag)
				if end_offset >= 0 {
					text := html[pos:pos + end_offset]
					trimmed := strings.trim_space(text)
					if len(trimmed) > 0 && trimmed != "\u2013" && trimmed != "-" {
						current_day += 1
						names := strings.clone(trimmed, allocator) or_return
						append(&entries, Entry{
							month = current_month,
							day   = current_day,
							names = names,
						})
					}
					pos += end_offset + len(close_tag)
					continue
				}
			}
		}

		pos += 1
	}

	return
}

fetch_vvc_page :: proc(allocator := context.allocator) -> ([]byte, os.Error) {
	state, stdout, stderr, err := os.process_exec({
		command = {"curl", "-sL", VVC_URL},
	}, allocator)
	defer delete(stderr, allocator)

	if err != nil {
		delete(stdout, allocator)
		return nil, err
	}
	if !state.exited || state.exit_code != 0 {
		delete(stdout, allocator)
		return nil, .Invalid_Command
	}

	return stdout, nil
}

print_usage :: proc(prog: string) {
	fmt.printfln(
		"Usage: %s [OPTIONS]\n" +
		"Look up Latvian name days.\n\n" +
		"Options:\n" +
		"  -d YYYY-MM-DD  Look up names for a specific date\n" +
		"  --update       Fetch latest name day data from VVC and cache it\n" +
		"  --help         Show this help message\n\n" +
		"Without arguments, shows today's name days.\n",
		prog,
	)
}

main :: proc() {
	prog := "lnd"
	if len(os.args) > 0 {
		prog = os.args[0]
	}

	custom_date: Maybe(Date)
	do_update := false

	i := 1
	for i < len(os.args) {
		arg := os.args[i]
		switch arg {
		case "--help":
			print_usage(prog)
			return
		case "--update":
			do_update = true
		case "-d":
			if i + 1 >= len(os.args) {
				fmt.fprintln(os.stderr, "error: -d requires a date argument")
				print_usage(prog)
				os.exit(1)
			}
			i += 1
			date, ok := parse_date(os.args[i])
			if !ok {
				fmt.fprintfln(os.stderr, "error: invalid date format '%s'. Use YYYY-MM-DD", os.args[i])
				os.exit(1)
			}
			custom_date = date
		case:
			fmt.fprintfln(os.stderr, "error: unknown option '%s'", arg)
			print_usage(prog)
			os.exit(1)
		}
		i += 1
	}

	if do_update {
		fmt.println("Fetching name day data from VVC...")

		html, fetch_err := fetch_vvc_page()
		if fetch_err != nil {
			fmt.fprintfln(os.stderr, "error: failed to fetch data: %v", fetch_err)
			os.exit(1)
		}
		defer delete(html)

		entries, parse_err := parse_vvc_html(string(html))
		if parse_err != nil {
			fmt.fprintfln(os.stderr, "error: failed to parse data: %v", parse_err)
			os.exit(1)
		}
		defer {
			for e in entries {
				delete(e.names)
			}
			delete(entries)
		}

		if save_err := save_cache(entries[:]); save_err != nil {
			fmt.fprintfln(os.stderr, "error: failed to save cache: %v", save_err)
			os.exit(1)
		}

		fmt.printfln("Cached %d entries successfully.", len(entries))
	}

	entries, load_err := load_entries()
	if load_err != nil {
		fmt.fprintfln(os.stderr, "error: failed to load entries: %v", load_err)
		os.exit(1)
	}
	defer {
		for e in entries {
			delete(e.names)
		}
		delete(entries)
	}

	date := custom_date.? or_else today()
	names, found := lookup(entries[:], date.month, date.day)
	if !found {
		names = "\u2014"
	}

	fmt.println(names)
}
