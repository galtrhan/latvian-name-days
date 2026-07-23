#define _GNU_SOURCE

#include "data.h"

#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#define VVC_URL "https://www.vvc.gov.lv/lv/latviesu-tradicionalo-kalendarvardu-saraksts"
#define CACHE_SECONDS (30 * 86400)
#define CACHE_VERSION 1

typedef struct {
	uint8_t month;
	uint8_t day;
} Date;

typedef struct {
	Entry *items;
	size_t len;
	size_t cap;
	bool owns_names;
} EntryList;

static const char *MONTH_NAMES[12] = {
	"JANVĀRIS", "FEBRUĀRIS", "MARTS", "APRĪLIS", "MAIJS", "JŪNIJS",
	"JŪLIJS", "AUGUSTS", "SEPTEMBRIS", "OKTOBRIS", "NOVEMBRIS", "DECEMBRIS",
};

static void die(const char *msg) {
	fprintf(stderr, "error: %s\n", msg);
	exit(1);
}

static void *xmalloc(size_t n) {
	void *p = malloc(n);
	if (!p) die("out of memory");
	return p;
}

static void *xrealloc(void *p, size_t n) {
	void *q = realloc(p, n);
	if (!q) die("out of memory");
	return q;
}

static char *xstrdup(const char *s) {
	size_t n = strlen(s) + 1;
	char *p = xmalloc(n);
	memcpy(p, s, n);
	return p;
}

static void entry_list_init(EntryList *list, bool owns_names) {
	list->items = NULL;
	list->len = 0;
	list->cap = 0;
	list->owns_names = owns_names;
}

static void entry_list_push(EntryList *list, uint8_t month, uint8_t day, const char *names) {
	if (list->len == list->cap) {
		size_t ncap = list->cap ? list->cap * 2 : 64;
		list->items = xrealloc(list->items, ncap * sizeof(Entry));
		list->cap = ncap;
	}
	list->items[list->len++] = (Entry){month, day, names};
}

static void entry_list_free(EntryList *list) {
	if (list->owns_names) {
		for (size_t i = 0; i < list->len; i++) {
			free((char *)list->items[i].names);
		}
	}
	free(list->items);
	list->items = NULL;
	list->len = 0;
	list->cap = 0;
}

static Date today(void) {
	time_t ts = time(NULL);
	struct tm t;
	localtime_r(&ts, &t);
	return (Date){
		.month = (uint8_t)(t.tm_mon + 1),
		.day = (uint8_t)t.tm_mday,
	};
}

static bool parse_u8(const char *s, size_t n, uint8_t *out) {
	if (n == 0) return false;
	unsigned long v = 0;
	for (size_t i = 0; i < n; i++) {
		if (s[i] < '0' || s[i] > '9') return false;
		v = v * 10 + (unsigned long)(s[i] - '0');
		if (v > 255) return false;
	}
	*out = (uint8_t)v;
	return true;
}

static bool parse_date(const char *s, Date *out) {
	if (strlen(s) < 10 || s[4] != '-' || s[7] != '-') {
		return false;
	}
	uint8_t month, day;
	for (int i = 0; i < 4; i++) {
		if (s[i] < '0' || s[i] > '9') return false;
	}
	if (!parse_u8(s + 5, 2, &month) || !parse_u8(s + 8, 2, &day)) {
		return false;
	}
	if (month < 1 || month > 12 || day < 1 || day > 31) {
		return false;
	}
	*out = (Date){.month = month, .day = day};
	return true;
}

static const char *lookup(const EntryList *entries, uint8_t month, uint8_t day) {
	for (size_t i = 0; i < entries->len; i++) {
		if (entries->items[i].month == month && entries->items[i].day == day) {
			return entries->items[i].names;
		}
	}
	return NULL;
}

static int mkdir_p(const char *path) {
	char tmp[PATH_MAX];
	size_t len = strlen(path);
	if (len >= sizeof(tmp)) {
		errno = ENAMETOOLONG;
		return -1;
	}
	memcpy(tmp, path, len + 1);

	for (char *p = tmp + 1; *p; p++) {
		if (*p == '/') {
			*p = '\0';
			if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
				return -1;
			}
			*p = '/';
		}
	}
	if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
		return -1;
	}
	return 0;
}

static char *get_cache_path(void) {
	const char *xdg = getenv("XDG_CACHE_HOME");
	char *path = NULL;
	if (xdg && xdg[0] != '\0') {
		if (asprintf(&path, "%s/lnd/namedays.csv", xdg) < 0) {
			die("out of memory");
		}
	} else {
		const char *home = getenv("HOME");
		if (!home || home[0] == '\0') {
			home = ".";
		}
		if (asprintf(&path, "%s/.cache/lnd/namedays.csv", home) < 0) {
			die("out of memory");
		}
	}
	return path;
}

static char *read_entire_file(const char *path) {
	FILE *f = fopen(path, "rb");
	if (!f) return NULL;
	if (fseek(f, 0, SEEK_END) != 0) {
		fclose(f);
		return NULL;
	}
	long sz = ftell(f);
	if (sz < 0) {
		fclose(f);
		return NULL;
	}
	if (fseek(f, 0, SEEK_SET) != 0) {
		fclose(f);
		return NULL;
	}
	char *buf = xmalloc((size_t)sz + 1);
	size_t n = fread(buf, 1, (size_t)sz, f);
	fclose(f);
	buf[n] = '\0';
	return buf;
}

static char *trim_inplace(char *s) {
	while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') s++;
	if (*s == '\0') return s;
	char *end = s + strlen(s) - 1;
	while (end > s && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')) {
		*end-- = '\0';
	}
	return s;
}

static char *trim_dup(const char *s, size_t n) {
	while (n > 0 && (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n')) {
		s++;
		n--;
	}
	while (n > 0) {
		char c = s[n - 1];
		if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
		n--;
	}
	char *out = xmalloc(n + 1);
	memcpy(out, s, n);
	out[n] = '\0';
	return out;
}

static bool parse_cache_line(char *line, EntryList *out) {
	char *first = strchr(line, '|');
	if (!first) return false;
	*first = '\0';
	char *second = strchr(first + 1, '|');
	if (!second) return false;
	*second = '\0';

	uint8_t month, day;
	if (!parse_u8(line, strlen(line), &month) || !parse_u8(first + 1, strlen(first + 1), &day)) {
		return false;
	}

	entry_list_push(out, month, day, xstrdup(second + 1));
	return true;
}

static bool parse_cache(char *content, EntryList *out, int64_t *cached_at) {
	entry_list_init(out, true);
	*cached_at = 0;
	bool in_data = false;

	char *save = NULL;
	for (char *line = strtok_r(content, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
		char *trimmed = trim_inplace(line);
		if (trimmed[0] == '\0') continue;

		if (strncmp(trimmed, "cached_at=", 10) == 0) {
			*cached_at = (int64_t)strtoll(trimmed + 10, NULL, 10);
			continue;
		}
		if (strcmp(trimmed, "---") == 0) {
			in_data = true;
			continue;
		}
		if (!in_data) continue;

		parse_cache_line(trimmed, out);
	}
	return out->len > 0;
}

static void load_entries(EntryList *out) {
	char *cache_path = get_cache_path();
	char *content = read_entire_file(cache_path);
	free(cache_path);

	if (content) {
		EntryList cached;
		int64_t cached_at = 0;
		bool ok = parse_cache(content, &cached, &cached_at);
		free(content);
		if (ok) {
			int64_t now = (int64_t)time(NULL);
			int64_t age = now - cached_at;
			if (age >= 0 && age < CACHE_SECONDS) {
				*out = cached;
				return;
			}
			entry_list_free(&cached);
		}
	}

	entry_list_init(out, false);
	for (size_t i = 0; i < EMBEDDED_ENTRIES_COUNT; i++) {
		entry_list_push(out,
			EMBEDDED_ENTRIES[i].month,
			EMBEDDED_ENTRIES[i].day,
			EMBEDDED_ENTRIES[i].names);
	}
}

static int save_cache(const EntryList *entries) {
	char *cache_path = get_cache_path();
	char *dir = xstrdup(cache_path);
	char *slash = strrchr(dir, '/');
	if (slash) {
		*slash = '\0';
		if (mkdir_p(dir) != 0) {
			free(dir);
			free(cache_path);
			return -1;
		}
	}
	free(dir);

	FILE *f = fopen(cache_path, "wb");
	free(cache_path);
	if (!f) return -1;

	fprintf(f, "version=%d\n", CACHE_VERSION);
	fprintf(f, "cached_at=%lld\n", (long long)time(NULL));
	fprintf(f, "---\n");
	for (size_t i = 0; i < entries->len; i++) {
		fprintf(f, "%u|%u|%s\n",
			entries->items[i].month,
			entries->items[i].day,
			entries->items[i].names);
	}
	fclose(f);
	return 0;
}

static char *fetch_vvc_page(size_t *out_len) {
	char *cmd = NULL;
	if (asprintf(&cmd, "curl -sL '%s'", VVC_URL) < 0) {
		die("out of memory");
	}
	FILE *p = popen(cmd, "r");
	free(cmd);
	if (!p) return NULL;

	size_t cap = 64 * 1024;
	size_t len = 0;
	char *buf = xmalloc(cap);
	for (;;) {
		if (len + 4096 + 1 > cap) {
			cap *= 2;
			buf = xrealloc(buf, cap);
		}
		size_t n = fread(buf + len, 1, 4096, p);
		len += n;
		if (n < 4096) break;
	}
	int status = pclose(p);
	if (status != 0) {
		free(buf);
		return NULL;
	}
	buf[len] = '\0';
	if (out_len) *out_len = len;
	return buf;
}

static void parse_vvc_html(const char *html, size_t html_len, EntryList *out) {
	entry_list_init(out, true);
	uint8_t current_month = 0;
	uint8_t current_day = 0;
	bool in_month_section = false;

	char month_btn[12][64];
	size_t month_btn_len[12];
	for (int i = 0; i < 12; i++) {
		int n = snprintf(month_btn[i], sizeof(month_btn[i]), ">%s</button>", MONTH_NAMES[i]);
		if (n < 0 || (size_t)n >= sizeof(month_btn[i])) {
			month_btn_len[i] = 0;
		} else {
			month_btn_len[i] = (size_t)n;
		}
	}

	size_t pos = 0;
	while (pos < html_len) {
		bool matched_month = false;
		for (int i = 0; i < 12; i++) {
			size_t n = month_btn_len[i];
			if (n == 0 || pos + n > html_len) continue;
			if (memcmp(html + pos, month_btn[i], n) == 0) {
				current_month = (uint8_t)(i + 1);
				current_day = 0;
				in_month_section = true;
				matched_month = true;
				pos += n;
				break;
			}
		}
		if (matched_month) continue;

		if (in_month_section && pos + 4 <= html_len && memcmp(html + pos, "<li>", 4) == 0) {
			pos += 4;
			const char *close = memmem(html + pos, html_len - pos, "</li>", 5);
			if (close) {
				size_t end_offset = (size_t)(close - (html + pos));
				char *trimmed = trim_dup(html + pos, end_offset);
				if (trimmed[0] != '\0' &&
				    strcmp(trimmed, "\xe2\x80\x93") != 0 &&
				    strcmp(trimmed, "-") != 0) {
					current_day++;
					entry_list_push(out, current_month, current_day, trimmed);
				} else {
					free(trimmed);
				}
				pos += end_offset + 5;
				continue;
			}
		}

		pos++;
	}
}

static void print_usage(const char *prog) {
	printf(
		"Usage: %s [OPTIONS]\n"
		"Look up Latvian name days.\n\n"
		"Options:\n"
		"  -d YYYY-MM-DD  Look up names for a specific date\n"
		"  --update       Fetch latest name day data from VVC and cache it\n"
		"  --help         Show this help message\n\n"
		"Without arguments, shows today's name days.\n",
		prog);
}

int main(int argc, char **argv) {
	const char *prog = (argc > 0 && argv[0] && argv[0][0]) ? argv[0] : "lnd";

	Date date = {0};
	bool do_update = false;

	for (int i = 1; i < argc; i++) {
		const char *arg = argv[i];
		if (strcmp(arg, "--help") == 0) {
			print_usage(prog);
			return 0;
		} else if (strcmp(arg, "--update") == 0) {
			do_update = true;
		} else if (strcmp(arg, "-d") == 0) {
			if (i + 1 >= argc) {
				fprintf(stderr, "error: -d requires a date argument\n");
				print_usage(prog);
				return 1;
			}
			i++;
			if (!parse_date(argv[i], &date)) {
				fprintf(stderr, "error: invalid date format '%s'. Use YYYY-MM-DD\n", argv[i]);
				return 1;
			}
		} else {
			fprintf(stderr, "error: unknown option '%s'\n", arg);
			print_usage(prog);
			return 1;
		}
	}

	EntryList entries;
	entry_list_init(&entries, false);

	if (do_update) {
		printf("Fetching name day data from VVC...\n");
		size_t html_len = 0;
		char *html = fetch_vvc_page(&html_len);
		if (!html) {
			fprintf(stderr, "error: failed to fetch data\n");
			return 1;
		}

		parse_vvc_html(html, html_len, &entries);
		free(html);

		if (save_cache(&entries) != 0) {
			fprintf(stderr, "error: failed to save cache\n");
			entry_list_free(&entries);
			return 1;
		}
		printf("Cached %zu entries successfully.\n", entries.len);
	} else {
		load_entries(&entries);
	}

	if (date.month == 0) {
		date = today();
	}

	const char *names = lookup(&entries, date.month, date.day);
	if (!names) {
		names = "\xe2\x80\x94";
	}
	printf("%s\n", names);

	entry_list_free(&entries);
	return 0;
}
