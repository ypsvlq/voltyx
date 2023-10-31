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
};

const Difficulty = struct {
    name: []const u8,
    color: [3]f32,
};

const difficulties = std.ComptimeStringMap(Difficulty, .{
    .{ "NOV", .{ .name = "NOVICE", .color = rgb(0x5A49FB) } },
    .{ "ADV", .{ .name = "ADVANCED", .color = rgb(0xFBD349) } },
    .{ "EXH", .{ .name = "EXHAUST", .color = rgb(0xFB494C) } },
    .{ "MXM", .{ .name = "MAXIMUM", .color = rgb(0xACACAC) } },
    .{ "INF", .{ .name = "INFINITE", .color = rgb(0xEE65E5) } },
    .{ "GRV", .{ .name = "GRAVITY", .color = rgb(0xFB8F49) } },
    .{ "HVN", .{ .name = "HEAVENLY", .color = rgb(0x49C9FB) } },
    .{ "VVD", .{ .name = "VIVID", .color = rgb(0xFF59CD) } },
    .{ "XCD", .{ .name = "EXCEED", .color = rgb(0x187FFF) } },
});

fn rgb(int: u24) [3]f32 {
    const r: f32 = @floatFromInt((int & 0xFF0000) >> 16);
    const g: f32 = @floatFromInt((int & 0xFF00) >> 8);
    const b: f32 = @floatFromInt(int & 0xFF);
    return .{ r / 255, g / 255, b / 255 };
}

var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const arena = arena_instance.allocator();

var songs = std.ArrayList(Song).init(arena);

pub fn init() !void {
    if (songs.items.len > 0) return;

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

pub fn deinit() !void {}

var cur_song: usize = 0;
var cur_difficulty: u2 = 3;
var last_laser_tick: [2]f64 = .{ 0, 0 };

pub fn draw() !void {
    var y: u16 = 10;
    for (songs.items, 0..) |song, i| {
        var x: u16 = 10;
        try ui.setTextSize(24);

        if (i == cur_song) {
            var chosen_difficulty = cur_difficulty;
            while (song.charts[chosen_difficulty].level == 0) {
                if (cur_difficulty >= 2) {
                    chosen_difficulty -%= 1;
                } else {
                    chosen_difficulty +%= 1;
                }
            }

            if (input.state.buttons.contains(.start)) {
                game.state = .ingame;
                const path = try std.fmt.allocPrint(game.temp_allocator, "songs/{s}/{c}.opus", .{ song.name, song.audio[chosen_difficulty] });
                try audio.play(path);
                return;
            }

            const jacket = try loadJacket(song, chosen_difficulty);
            renderer.drawQuad2D(jacket, renderer.width - 275, renderer.height - 275, 250, 250);

            const chart = song.charts[chosen_difficulty];
            const difficulty = difficulties.get(chart.difficulty).?;
            const difficulty_str = try std.fmt.allocPrint(game.temp_allocator, "{s} {}", .{ difficulty.name, chart.level });
            const info_str = try std.fmt.allocPrint(game.temp_allocator, "artist: {s}    bpm: {s}    effector: {s}    illustrator: {s}", .{ song.info.artist, song.info.bpm, chart.effector, chart.illustrator });

            x = try text.draw(song.info.title, x, y, .{ 1, 1, 1 });
            x += ui.scaleInt(u16, 25);
            _ = try text.draw(difficulty_str, x, y, difficulty.color);

            x = 10;
            y += text.height;
            try ui.setTextSize(18);
            _ = try text.draw(info_str, x, y, .{ 1, 1, 1 });
        } else {
            _ = try text.draw(song.info.title, x, y, .{ 0.7, 0.7, 0.7 });
        }
        y += text.height;
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
        cur_difficulty +%= 1;
    } else if (lasers[0] < 0) {
        cur_difficulty -%= 1;
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
}

var jacket_cache = std.StringHashMap([4]u32).init(game.allocator);

fn loadJacket(song: Song, difficulty: u2) !u32 {
    if (jacket_cache.get(song.name)) |jackets| {
        return jackets[difficulty];
    }

    var jackets: [4]u32 = undefined;
    for (song.charts, song.jacket, &jackets) |chart, index, *out| {
        if (chart.level != 0) {
            const path = try std.fmt.allocPrint(game.temp_allocator, "songs/{s}/{c}.png", .{ song.name, index });
            out.* = try glw.loadPNG(path);
        }
    }

    try jacket_cache.put(song.name, jackets);

    return jackets[difficulty];
}
