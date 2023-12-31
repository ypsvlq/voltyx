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

const Song = struct {
    name: []const u8,
    info: Info = .{},
    charts: [4]Chart = .{.{}} ** 4,
    jacket: [4]u8 = undefined,
    audio: [4]u8 = undefined,

    const Info = struct {
        title: []const u8 = "unknown",
        artist: []const u8 = "unknown",
        bpm: []const u8 = "0",
        preview: f32 = 0,
    };

    const Chart = struct {
        level: u8 = 0,
        difficulty: []const u8 = "?",
        effector: []const u8 = "unknown",
        illustrator: []const u8 = "unknown",
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
        var song_dir = try dir.dir.openDir(entry.name, .{});
        defer song_dir.close();

        const bytes = vfs.readFileAt(game.temp_allocator, song_dir, "info.txt") catch |err| switch (err) {
            error.FileNotFound => {
                std.log.warn("{s} does not contain info.txt", .{entry.name});
                continue;
            },
            else => return err,
        };
        var ini = Ini{ .bytes = bytes };
        var song = loadInfo(&ini, entry.name) catch |err| {
            std.log.err("songs/{s}/info.txt line {}: {s}", .{ entry.name, ini.line, @errorName(err) });
            continue;
        };

        var has_chart = false;
        var jacket_index: u8 = '1';
        var audio_index: u8 = '1';
        for (song.charts, 0..) |chart, i| {
            if (chart.level != 0) {
                has_chart = true;

                const index: u8 = @intCast('1' + i);
                song.jacket[i] = try accessChartFile(song_dir, ".png", index, &jacket_index);
                song.audio[i] = try accessChartFile(song_dir, ".opus", index, &audio_index);
            }
        }

        if (has_chart) {
            try songs.append(song);
        } else {
            std.log.warn("{s} has no charts", .{entry.name});
        }
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

fn loadInfo(iter: *Ini, name: []const u8) !Song {
    var song = Song{ .name = try arena.dupe(u8, name) };
    while (try iter.next()) |entry| {
        if (iter.section.len == 0) {
            try config.loadEntry(arena, Song.Info, &song.info, entry);
        } else {
            const index = try std.fmt.parseInt(u8, iter.section, 10);
            if (index < 1 or index > 4) return error.InvalidDifficulty;
            const chart = &song.charts[index - 1];
            try config.loadEntry(arena, Song.Chart, chart, entry);
        }
    }
    for (&song.charts, 0..) |*chart, i| {
        if (chart.level != 0 and difficulties.get(chart.difficulty) == null) {
            std.log.warn("{s} difficulty {} has unknown difficulty, assuming MXM", .{ name, i });
            chart.difficulty = "MXM";
        }
    }
    return song;
}

pub fn enter() !void {
    try playPreview();
}

var cur_song: usize = 0;
var cur_difficulty: u2 = 3;
var last_laser_tick: [2]f64 = .{ 0, 0 };

pub fn update() !void {
    const song = songs.items[cur_song];

    if (input.state.buttons.contains(.start)) {
        const index = song.getIndex(cur_difficulty);

        const path = try game.format("songs/{s}/{c}.opus", .{ song.name, song.audio[index] });
        try audio.play(path, .{});

        game.state = .ingame;
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
        cur_difficulty = song.getIndex(cur_difficulty);
        cur_difficulty +|= 1;
    } else if (lasers[0] < 0) {
        cur_difficulty = song.getIndex(cur_difficulty);
        cur_difficulty -|= 1;
    }

    if (lasers[1] > 0) {
        if (cur_song == songs.items.len - 1) {
            cur_song = 0;
        } else {
            cur_song += 1;
        }
    } else if (lasers[1] < 0) {
        if (cur_song == 0) {
            cur_song = songs.items.len - 1;
        } else {
            cur_song -= 1;
        }
    }

    if (lasers[1] != 0) {
        try playPreview();
    }
}

fn playPreview() !void {
    if (@import("builtin").mode == .Debug) return;
    const song = songs.items[cur_song];
    const path = try game.format("songs/{s}/1.opus", .{song.name});
    try audio.play(path, .{ .start = song.info.preview, .length = 10 });
}

pub fn draw2D() !void {
    var visible: u16 = @intFromFloat(renderer.height / (100 * ui.scale));
    if (visible == 0) return;
    if (visible % 2 == 0) visible -= 1;

    var pos = cur_song;
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
        const index = song.getIndex(cur_difficulty);
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

        const difficulty = difficulties.get(chart.difficulty).?;
        const difficulty_str = try game.format("{}", .{chart.level});
        try ui.setTextSize(24);
        _ = try text.draw(difficulty_str, x, y, difficulty.color);

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
    for (song.charts, song.jacket, &jackets) |chart, index, *out| {
        if (chart.level != 0) {
            const path = try game.format("songs/{s}/{c}.png", .{ song.name, index });
            out.* = glw.loadPNG(path) catch |err| blk: {
                std.log.err("could not load {s}: {s}", .{ path, @errorName(err) });
                break :blk default_jacket;
            };
        }
    }

    try jacket_cache.put(song.name, jackets);

    return jackets[difficulty];
}
