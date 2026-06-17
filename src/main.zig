const std = @import("std");
const json = std.json;
const mem = std.mem;
const Allocator = mem.Allocator;
const ManagedArrayList = std.array_list.AlignedManaged;

const embedded = @import("data");

extern fn localtime_r(time: *const i64, result: *LibcTm) ?*LibcTm;

const LibcTm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: c_long,
    tm_zone: ?*u8,
};

const Entry = struct {
    month: u8,
    day: u8,
    names: []const u8,
};

const Date = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
};

const VVC_URL = "https://www.vvc.gov.lv/lv/latviesu-tradicionalo-kalendarvardu-saraksts";
const CACHE_SECONDS: i64 = 30 * 86400;

const month_names = [_][]const u8{
    "JANVĀRIS", "FEBRUĀRIS", "MARTS", "APRĪLIS", "MAIJS", "JŪNIJS",
    "JŪLIJS", "AUGUSTS", "SEPTEMBRIS", "OKTOBRIS", "NOVEMBRIS", "DECEMBRIS",
};

fn today() Date {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &ts);
    const epoch = @as(i64, @bitCast(ts.sec));
    var t: LibcTm = undefined;
    var epoch_copy = epoch;
    _ = localtime_r(&epoch_copy, &t);
    return .{
        .year = @intCast(t.tm_year + 1900),
        .month = @intCast(t.tm_mon + 1),
        .day = @intCast(t.tm_mday),
        .hour = @intCast(t.tm_hour),
        .minute = @intCast(t.tm_min),
    };
}

fn parseDate(s: []const u8) !Date {
    if (s.len < 10 or s[4] != '-' or s[7] != '-')
        return error.InvalidFormat;
    const year = try std.fmt.parseInt(u16, s[0..4], 10);
    const month = try std.fmt.parseInt(u8, s[5..7], 10);
    const day = try std.fmt.parseInt(u8, s[8..10], 10);
    if (month < 1 or month > 12 or day < 1 or day > 31)
        return error.InvalidDate;
    return .{ .year = year, .month = month, .day = day, .hour = 0, .minute = 0 };
}

fn lookup(entries: []const Entry, month: u8, day: u8) ?[]const u8 {
    for (entries) |e| {
        if (e.month == month and e.day == day) return e.names;
    }
    return null;
}

const CacheEntry = struct {
    m: u8,
    d: u8,
    n: []const u8,
};

const CacheFile = struct {
    version: u32,
    cached_at: i64,
    entries: []CacheEntry,
};

fn getCachePath(alloc: Allocator, environ_map: *const std.process.Environ.Map) ![]u8 {
    const xdg_cache = environ_map.get("XDG_CACHE_HOME") orelse blk: {
        const home = environ_map.get("HOME") orelse ".";
        break :blk try std.fmt.allocPrint(alloc, "{s}/.cache", .{home});
    };
    return std.fmt.allocPrint(alloc, "{s}/lnd/namedays.json", .{xdg_cache});
}

fn loadEntries(alloc: Allocator, io: std.Io, environ_map: *const std.process.Environ.Map) !ManagedArrayList(Entry, null) {
    const cache_path = try getCachePath(alloc, environ_map);
    defer alloc.free(cache_path);

    if (std.Io.Dir.openFileAbsolute(io, cache_path, .{})) |file| {
        defer file.close(io);
        var buf: [8192]u8 = undefined;
        var fr = file.reader(io, &buf);
        const content = fr.interface.readAlloc(alloc, 1024 * 1024) catch return embeddedEntries(alloc);
        defer alloc.free(content);

        const parsed = json.parseFromSlice(CacheFile, alloc, content, .{}) catch return embeddedEntries(alloc);
        defer parsed.deinit();

        const now = std.Io.Clock.real.now(io).toSeconds();
        const age = now - parsed.value.cached_at;
        if (age >= 0 and age < CACHE_SECONDS) {
            var result = ManagedArrayList(Entry, null).init(alloc);
            for (parsed.value.entries) |ce| {
                try result.append(.{ .month = ce.m, .day = ce.d, .names = try alloc.dupe(u8, ce.n) });
            }
            return result;
        }
    } else |_| {}

    return embeddedEntries(alloc);
}

fn embeddedEntries(alloc: Allocator) !ManagedArrayList(Entry, null) {
    var result = ManagedArrayList(Entry, null).init(alloc);
    for (embedded.entries) |e| {
        try result.append(.{ .month = e.month, .day = e.day, .names = try alloc.dupe(u8, e.names) });
    }
    return result;
}

fn saveCache(alloc: Allocator, io: std.Io, entries: []const Entry, environ_map: *const std.process.Environ.Map) !void {
    const cache_path = try getCachePath(alloc, environ_map);
    defer alloc.free(cache_path);

    const dir_path = std.fs.path.dirname(cache_path) orelse ".";
    _ = std.Io.Dir.createDirAbsolute(io, dir_path, @as(std.Io.File.Permissions, .default_dir)) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var ce_list = ManagedArrayList(CacheEntry, null).init(alloc);
    defer ce_list.deinit();

    for (entries) |e| {
        try ce_list.append(.{ .m = e.month, .d = e.day, .n = e.names });
    }

    const file = try std.Io.Dir.createFileAbsolute(io, cache_path, .{});
    defer file.close(io);

    const cf = CacheFile{
        .version = 1,
        .cached_at = std.Io.Clock.real.now(io).toSeconds(),
        .entries = ce_list.items,
    };
    var buf: [8192]u8 = undefined;
    var fw = file.writer(io, &buf);
    try json.fmt(cf, .{}).format(&fw.interface);
}

fn parseVvcHtml(alloc: Allocator, html: []const u8) !ManagedArrayList(Entry, null) {
    var entries = ManagedArrayList(Entry, null).init(alloc);
    var current_month: u8 = 0;
    var current_day: u8 = 0;
    var in_month_section = false;

    var pos: usize = 0;
    while (pos < html.len) {
        var matched_month = false;
        for (month_names, 1..) |mn, month_num| {
            const search = try std.fmt.allocPrint(alloc, ">{s}</button>", .{mn});
            defer alloc.free(search);
            if (pos + search.len <= html.len and mem.eql(u8, html[pos..][0..search.len], search)) {
                current_month = @intCast(month_num);
                current_day = 0;
                in_month_section = true;
                matched_month = true;
                pos += search.len;
                break;
            }
        }
        if (matched_month) continue;

        if (in_month_section) {
            const li_tag = "<li>";
            if (pos + li_tag.len <= html.len and mem.startsWith(u8, html[pos..], li_tag)) {
                pos += li_tag.len;
                const close_tag = "</li>";
                if (mem.indexOf(u8, html[pos..], close_tag)) |end| {
                    const text = html[pos..][0..end];
                    const trimmed = mem.trim(u8, text, " \t\r\n");
                    if (trimmed.len > 0 and !mem.eql(u8, trimmed, "\u{2013}") and !mem.eql(u8, trimmed, "-")) {
                        current_day += 1;
                        const names = try alloc.dupe(u8, trimmed);
                        try entries.append(.{ .month = current_month, .day = current_day, .names = names });
                    }
                    pos += end + close_tag.len;
                    continue;
                }
            }
        }

        pos += 1;
    }

    return entries;
}

fn fetchVvcPage(alloc: Allocator, io: std.Io) ![]u8 {
    const result = try std.process.run(alloc, io, .{
        .argv = &.{ "curl", "-sL", VVC_URL },
    });
    defer alloc.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return error.CurlFailed,
        else => return error.CurlFailed,
    }

    return result.stdout;
}

fn printUsage(prog: []const u8) void {
    std.debug.print(
        \\Usage: {s} [OPTIONS]
        \\Look up Latvian name days.
        \\
        \\Options:
        \\  -d YYYY-MM-DD  Look up names for a specific date
        \\  --update       Fetch latest name day data from VVC and cache it
        \\  --help         Show this help message
        \\
        \\Without arguments, shows today's name days.
        \\
    , .{prog});
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;

    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer args_iter.deinit();

    const prog = args_iter.next() orelse "lnd";

    var custom_date: ?Date = null;
    var do_update = false;

    while (args_iter.next()) |arg| {
        if (mem.eql(u8, arg, "--help")) {
            printUsage(prog);
            return;
        } else if (mem.eql(u8, arg, "--update")) {
            do_update = true;
        } else if (mem.eql(u8, arg, "-d")) {
            const date_str = args_iter.next() orelse {
                std.debug.print("error: -d requires a date argument\n", .{});
                printUsage(prog);
                std.process.exit(1);
            };
            custom_date = parseDate(date_str) catch {
                std.debug.print("error: invalid date format '{s}'. Use YYYY-MM-DD\n", .{date_str});
                std.process.exit(1);
            };
        } else {
            std.debug.print("error: unknown option '{s}'\n", .{arg});
            printUsage(prog);
            std.process.exit(1);
        }
    }

    if (do_update) {
        std.debug.print("Fetching name day data from VVC...\n", .{});

        const html = fetchVvcPage(alloc, io) catch |err| {
            std.debug.print("error: failed to fetch data: {}\n", .{err});
            std.process.exit(1);
        };
        defer alloc.free(html);

        const entries = try parseVvcHtml(alloc, html);
        try saveCache(alloc, io, entries.items, init.environ_map);

        std.debug.print("Cached {d} entries successfully.\n", .{entries.items.len});
    }

    const entries = try loadEntries(alloc, io, init.environ_map);
    defer entries.deinit();

    const date = custom_date orelse today();

    const names = lookup(entries.items, date.month, date.day) orelse "\u{2014}";

    var stdout_file = std.Io.File.stdout();
    var stdout_buf: [8192]u8 = undefined;
    var stdout_fw = stdout_file.writer(io, &stdout_buf);
    try stdout_fw.interface.print("{s}\n", .{names});
    try stdout_fw.interface.flush();
}
