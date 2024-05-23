const std = @import("std");
const glfw = @import("mach-glfw");
const config = @import("../config.zig");
const glw = @import("../glw.zig");
const game = @import("../game.zig");
const db = @import("../db.zig");
const ui = @import("../ui.zig");
const renderer = @import("../renderer.zig");
const text = @import("../text.zig");
const input = @import("../input.zig");
const audio = @import("../audio.zig");
const cache = @import("cache.zig");

const Song = struct {
    hash: u64,
    name: []const u8,
    title: []const u8,
    artist: []const u8,
    bpm: []const u8,
    preview: f32,
    charts: [4]Chart,

    const Chart = struct {
        level: u8,
        difficulty: cache.Difficulty,
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

var song_query: db.Statement(void, cache.Song) = undefined;
var chart_query: db.Statement(i64, cache.Chart) = undefined;
var default_jacket: u32 = undefined;

pub fn init() !void {
    try song_query.prepare("SELECT hash,name,title,artist,bpm,preview,chart1,chart2,chart3,chart4 FROM song WHERE name IS NOT NULL ORDER BY name");
    try chart_query.prepare("SELECT level,difficulty,effector,illustrator,jacket,audio FROM chart WHERE id = ?");
    default_jacket = try glw.loadEmbeddedPNG("jacket.png");
}

pub fn deinit() !void {
    song_query.deinit();
    chart_query.deinit();
}

const arena = game.state_allocator;
var songs = std.ArrayList(Song).init(arena);

var want_preview: bool = false;

pub fn enter() !void {
    songs.clearAndFree();

    var iter = try song_query.iter({});
    while (try iter.next()) |row| {
        var song = Song{
            .hash = row.hash,
            .name = try arena.dupe(u8, row.name),
            .title = try arena.dupe(u8, row.title),
            .artist = try arena.dupe(u8, row.artist),
            .bpm = try arena.dupe(u8, row.bpm),
            .preview = row.preview,
            .charts = undefined,
        };

        for (row.charts, &song.charts) |maybe_chart, *chart| {
            if (maybe_chart) |id| {
                var chart_iter = try chart_query.iter(id);
                const info = (try chart_iter.next()).?;
                chart.* = .{
                    .level = info.level,
                    .difficulty = cache.difficulties[info.difficulty],
                    .effector = try arena.dupe(u8, info.effector),
                    .illustrator = try arena.dupe(u8, info.illustrator),
                    .jacket = info.jacket,
                    .audio = info.audio,
                };
            } else {
                chart.level = 0;
            }
        }

        try songs.append(song);
    }

    if (songs.items.len != 0) {
        config.song = std.math.clamp(config.song, 0, songs.items.len - 1);
        want_preview = true;
    }
}

var last_laser_tick: [2]f64 = .{ 0, 0 };

pub fn update() !void {
    if (songs.items.len == 0) return;

    const song = songs.items[config.song];

    if (input.consume(.start)) {
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
        try audio.play(path, .{ .start = song.preview, .length = 10 });
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
        _ = try text.draw(song.title, x, y, .{ 1, 1, 1 });
        y += text.height;

        try ui.setTextSize(18);
        _ = try text.draw(song.artist, x, y, .{ 1, 1, 1 });
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
