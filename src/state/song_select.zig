const std = @import("std");
const glfw = @import("mach-glfw");
const Ini = @import("../Ini.zig");
const vfs = @import("../vfs.zig");
const config = @import("../config.zig");
const glw = @import("../glw.zig");
const game = @import("../game.zig");
const ui = @import("../ui.zig");
const renderer = @import("../renderer.zig");
const text = @import("../text.zig");
const input = @import("../input.zig");
const audio = @import("../audio.zig");

const Info = struct {
    song: SongInfo = .{},
    charts: [4]ChartInfo = .{.{}} ** 4,

    const SongInfo = struct {
        title: []const u8 = "unknown",
        artist: []const u8 = "unknown",
        bpm: []const u8 = "0",
        preview: f32 = 0,
    };

    const ChartInfo = struct {
        level: u8 = 0,
        difficulty: []const u8 = "<unset>",
        effector: ?[]const u8 = null,
        illustrator: ?[]const u8 = null,
    };

    fn load(iter: *Ini) !Info {
        var info = Info{};

        while (try iter.next()) |entry| {
            if (iter.section.len == 0) {
                try config.loadEntry(arena, SongInfo, &info.song, entry);
            } else {
                const index = try std.fmt.parseInt(u8, iter.section, 10);
                if (index < 1 or index > 4) return error.InvalidChartIndex;
                try config.loadEntry(arena, ChartInfo, &info.charts[index - 1], entry);
            }
        }

        return info;
    }

    fn makeSong(self: Info, name: []const u8, dir: std.fs.Dir) !?Song {
        var song = Song{ .name = try arena.dupe(u8, name), .info = self.song };

        var has_chart = false;
        var last_effector: []const u8 = "unknown";
        var last_illustrator: []const u8 = "unknown";
        var last_jacket: u8 = '1';
        var last_audio: u8 = '1';

        for (&song.charts, self.charts, 0..) |*chart, info, i| {
            const index: u8 = @intCast(i + '1');
            if (info.level != 0) {
                has_chart = true;

                if (info.effector) |effector| last_effector = effector;
                if (info.illustrator) |illustrator| last_illustrator = illustrator;

                chart.* = .{
                    .level = info.level,
                    .difficulty = difficulties.get(info.difficulty) orelse blk: {
                        std.log.warn("{s} chart {c} has unknown difficulty {s}, assuming MXM", .{ name, index, info.difficulty });
                        break :blk difficulties.get("MXM").?;
                    },
                    .effector = last_effector,
                    .illustrator = last_illustrator,
                    .jacket = try accessChartFile(dir, ".png", index, &last_jacket),
                    .audio = try accessChartFile(dir, ".opus", index, &last_audio),
                };
            }
        }

        if (has_chart) {
            return song;
        } else {
            std.log.warn("{s} has info.txt but no charts", .{name});
            return null;
        }
    }

    fn accessChartFile(dir: std.fs.Dir, comptime ext: []const u8, index: u8, last_valid_index: *u8) !u8 {
        if (dir.access(.{index} ++ ext, .{})) {
            last_valid_index.* = index;
            return index;
        } else |err| switch (err) {
            error.FileNotFound => return last_valid_index.*,
            else => return err,
        }
    }
};

const Song = struct {
    name: []const u8,
    info: Info.SongInfo,
    charts: [4]Chart = .{std.mem.zeroes(Chart)} ** 4,

    const Chart = struct {
        level: u8,
        difficulty: Difficulty,
        effector: []const u8,
        illustrator: []const u8,
        jacket: u8,
        audio: u8,
    };

    fn getIndex(self: Song, target_difficulty: u2) u2 {
        var difficulty = target_difficulty;
        while (self.charts[difficulty].level == 0) difficulty -%= 1;
        return difficulty;
    }
};

const Difficulty = struct {
    name: []const u8,
    color: [3]f32,
};

const difficulties = std.ComptimeStringMap(Difficulty, .{
    .{ "NOV", .{ .name = "NOVICE", .color = ui.rgb(0x5A49FB) } },
    .{ "ADV", .{ .name = "ADVANCED", .color = ui.rgb(0xFBD349) } },
    .{ "EXH", .{ .name = "EXHAUST", .color = ui.rgb(0xFB494C) } },
    .{ "MXM", .{ .name = "MAXIMUM", .color = ui.rgb(0xACACAC) } },
    .{ "INF", .{ .name = "INFINITE", .color = ui.rgb(0xEE65E5) } },
    .{ "GRV", .{ .name = "GRAVITY", .color = ui.rgb(0xFB8F49) } },
    .{ "HVN", .{ .name = "HEAVENLY", .color = ui.rgb(0x49C9FB) } },
    .{ "VVD", .{ .name = "VIVID", .color = ui.rgb(0xFF59CD) } },
    .{ "XCD", .{ .name = "EXCEED", .color = ui.rgb(0x187FFF) } },
});

var default_jacket: u32 = undefined;

var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const arena = arena_instance.allocator();
var songs = std.ArrayList(Song).init(arena);

pub fn init() !void {
    default_jacket = try glw.loadEmbeddedPNG("jacket.png");

    var dir = try vfs.openIterableDir("songs");
    defer dir.close();

    var iter = dir.iterateAssumeFirstIteration();
    while (try iter.next()) |entry| {
        var song_dir = try dir.openDir(entry.name, .{});
        defer song_dir.close();

        const bytes = vfs.readFileAt(game.temp_allocator, song_dir, "info.txt") catch |err| switch (err) {
            error.FileNotFound => {
                std.log.warn("{s} does not contain info.txt", .{entry.name});
                continue;
            },
            else => return err,
        };
        var ini = Ini{ .bytes = bytes };

        if (Info.load(&ini)) |info| {
            if (try info.makeSong(entry.name, song_dir)) |song| {
                try songs.append(song);
            }
        } else |err| {
            std.log.err("songs/{s}/info.txt line {}: {s}", .{ entry.name, ini.line, @errorName(err) });
        }
    }
}

var want_preview: bool = false;

pub fn enter() !void {
    want_preview = true;
    config.song = std.math.clamp(config.song, 0, songs.items.len - 1);
}

var last_laser_tick: [2]f64 = .{ 0, 0 };

pub fn update() !void {
    if (songs.items.len == 0) return;

    const song = songs.items[config.song];

    if (input.state.buttons.contains(.start)) {
        const index = song.getIndex(config.difficulty);

        const path = try game.format("songs/{s}/{c}.opus", .{ song.name, song.charts[index].audio });
        try audio.play(path, .{});

        try game.state.change(.ingame);
        return;
    }

    var lasers: [2]i8 = .{ 0, 0 };
    for (input.state.lasers, &last_laser_tick, &lasers) |laser, *tick, *output| {
        if (laser != 0) {
            if (glfw.getTime() - tick.* > 0.01 / @abs(laser)) {
                tick.* = glfw.getTime();
                output.* = if (laser > 0) 1 else -1;
            }
        }
    }

    if (lasers[0] > 0) {
        config.difficulty = song.getIndex(config.difficulty);
        config.difficulty +|= 1;
    } else if (lasers[0] < 0) {
        config.difficulty = song.getIndex(config.difficulty);
        config.difficulty -|= 1;
    }

    if (lasers[1] > 0) {
        if (config.song == songs.items.len - 1) {
            config.song = 0;
        } else {
            config.song += 1;
        }
    } else if (lasers[1] < 0) {
        if (config.song == 0) {
            config.song = songs.items.len - 1;
        } else {
            config.song -= 1;
        }
    }

    if (lasers[1] != 0) {
        want_preview = true;
        try audio.stop();
    } else if (want_preview and glfw.getTime() - last_laser_tick[1] > 0.5) {
        want_preview = false;
        const path = try game.format("songs/{s}/1.opus", .{song.name});
        try audio.play(path, .{ .start = song.info.preview, .length = 10 });
    }
}

pub fn draw2D() !void {
    if (songs.items.len == 0) {
        try ui.setTextSize(36);
        _ = try text.draw("No songs!", 10, 10, .{ 1, 1, 1 });
        return;
    }

    var visible: u16 = @intFromFloat(renderer.height / (100 * ui.scale));
    if (visible == 0) return;
    if (visible % 2 == 0) visible -= 1;

    var pos = config.song;
    for (0..visible / 2) |_| {
        if (pos == 0) {
            pos = songs.items.len;
        }
        pos -= 1;
    }

    const size = ui.scaleConst(100);
    var base: u16 = 0;
    for (0..visible) |_| {
        const song = songs.items[pos];
        const index = song.getIndex(config.difficulty);
        const chart = song.charts[index];

        const jacket = try loadJacket(song, index);
        ui.drawImage(jacket, 0, base, size, size);

        const x = size + ui.scaleConst(10);
        var y = base + ui.scaleConst(5);

        try ui.setTextSize(24);
        _ = try text.draw(song.info.title, x, y, .{ 1, 1, 1 });
        y += text.height;

        try ui.setTextSize(18);
        _ = try text.draw(song.info.artist, x, y, .{ 1, 1, 1 });
        y += text.height;

        const difficulty_str = try game.format("{}", .{chart.level});
        try ui.setTextSize(24);
        _ = try text.draw(difficulty_str, x, y, chart.difficulty.color);

        pos += 1;
        if (pos == songs.items.len) {
            pos = 0;
        }
        base += size;
    }
}

var jacket_cache = std.StringHashMap([4]u32).init(game.allocator);

fn loadJacket(song: Song, difficulty: u2) !u32 {
    if (@import("builtin").mode == .Debug) return default_jacket;

    if (jacket_cache.get(song.name)) |jackets| {
        return jackets[difficulty];
    }

    var jackets: [4]u32 = undefined;
    for (song.charts, &jackets) |chart, *out| {
        if (chart.level != 0) {
            const path = try game.format("songs/{s}/{c}.png", .{ song.name, chart.jacket });
            out.* = glw.loadPNG(path) catch |err| blk: {
                std.log.err("could not load {s}: {s}", .{ path, @errorName(err) });
                break :blk default_jacket;
            };
        }
    }

    try jacket_cache.put(song.name, jackets);

    return jackets[difficulty];
}
