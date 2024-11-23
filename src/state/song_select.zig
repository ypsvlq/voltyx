const std = @import("std");
const wio = @import("wio");
const config = @import("../config.zig");
const glw = @import("../glw.zig");
const game = @import("../game.zig");
const db = @import("../db.zig");
const ui = @import("../ui.zig");
const renderer = @import("../renderer.zig");
const input = @import("../input.zig");
const audio = @import("../audio.zig");
const cache = @import("cache.zig");
const ingame = @import("ingame.zig");
const jacket_cache = @import("song_select/jacket_cache.zig");

pub const Song = struct {
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

pub fn init() !void {
    try song_query.prepare("SELECT hash,name,title,artist,bpm,preview,chart1,chart2,chart3,chart4 FROM song WHERE name IS NOT NULL ORDER BY name");
    try chart_query.prepare("SELECT level,difficulty,effector,illustrator,jacket,audio FROM chart WHERE id = ?");
    try jacket_cache.init();
}

var songs = std.ArrayList(Song).init(game.allocator);
var want_preview: bool = false;

pub fn enter() !void {
    songs.clearRetainingCapacity();
    jacket_cache.clear();

    var iter = try song_query.iter({});
    while (try iter.next()) |row| {
        var song = Song{
            .hash = row.hash,
            .name = try game.state_allocator.dupe(u8, row.name),
            .title = try game.state_allocator.dupe(u8, row.title),
            .artist = try game.state_allocator.dupe(u8, row.artist),
            .bpm = try game.state_allocator.dupe(u8, row.bpm),
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
                    .effector = try game.state_allocator.dupe(u8, info.effector),
                    .illustrator = try game.state_allocator.dupe(u8, info.illustrator),
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

var last_laser_tick: [2]i64 = .{ 0, 0 };

pub fn update() !void {
    if (songs.items.len == 0) return;

    const song = songs.items[config.song];

    if (input.consume(.start)) {
        const index = song.getIndex(config.difficulty);
        try ingame.prepare(song, index);
        try game.state.change(.ingame);
        return;
    }

    var lasers: [2]i8 = .{ 0, 0 };
    for (input.state.lasers, &last_laser_tick, &lasers) |laser, *tick, *output| {
        if (laser != 0) {
            const delta: f32 = @floatFromInt(std.time.milliTimestamp() - tick.*);
            if (delta > 10 / @abs(laser)) {
                tick.* = std.time.milliTimestamp();
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
    } else if (want_preview and std.time.milliTimestamp() - last_laser_tick[1] > 500) {
        want_preview = false;
        const path = try game.format("songs/{s}/1.opus", .{song.name});
        audio.play(path, .{ .start = song.preview, .length = 10 }) catch |err| {
            std.log.err("could not play {s}: {s}", .{ path, @errorName(err) });
        };
    }
}

pub fn draw2D() !void {
    if (songs.items.len == 0) {
        ui.locate(10, 10);
        try ui.setTextSize(36);
        try ui.drawText("No songs!", .{});
        return;
    }

    var visible: u16 = @intFromFloat(renderer.height / (100 * config.scale));
    if (visible == 0) return;
    if (visible % 2 == 0) visible -= 1;

    var pos = config.song;
    for (0..visible / 2) |_| {
        if (pos == 0) {
            pos = songs.items.len;
        }
        pos -= 1;
    }

    const size = 100;
    var base: f32 = 0;
    for (0..visible) |_| {
        const song = songs.items[pos];
        const index = song.getIndex(config.difficulty);
        const chart = song.charts[index];

        const jacket = try jacket_cache.get(song.name, index);
        ui.drawImage(jacket, 0, base, size, size);

        ui.locate(size + 10, base + 5);

        try ui.setTextSize(24);
        try ui.drawText(song.title, .{ .advance_y = true });

        try ui.setTextSize(18);
        try ui.drawText(song.artist, .{ .advance_y = true });

        const difficulty = try game.format("{}", .{chart.level});
        try ui.setTextSize(24);
        try ui.drawText(difficulty, .{ .color = chart.difficulty.color });

        pos += 1;
        if (pos == songs.items.len) {
            pos = 0;
        }
        base += size;
    }
}
