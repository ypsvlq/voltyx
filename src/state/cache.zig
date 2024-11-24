const std = @import("std");
const Ini = @import("ylib").Ini;
const wio = @import("wio");
const game = @import("../game.zig");
const vfs = @import("../vfs.zig");
const config = @import("../config.zig");
const db = @import("../db.zig");
const ui = @import("../ui.zig");

pub const Difficulty = struct {
    abbrev: *const [3]u8,
    name: []const u8,
    color: [3]f32,
};

// append-only, indexes stored in db
pub const difficulties = [_]Difficulty{
    .{ .abbrev = "NOV", .name = "NOVICE", .color = ui.rgb(0x5A49FB) },
    .{ .abbrev = "ADV", .name = "ADVANCED", .color = ui.rgb(0xFBD349) },
    .{ .abbrev = "EXH", .name = "EXHAUST", .color = ui.rgb(0xFB494C) },
    .{ .abbrev = "MXM", .name = "MAXIMUM", .color = ui.rgb(0xACACAC) },
    .{ .abbrev = "INF", .name = "INFINITE", .color = ui.rgb(0xEE65E5) },
    .{ .abbrev = "GRV", .name = "GRAVITY", .color = ui.rgb(0xFB8F49) },
    .{ .abbrev = "HVN", .name = "HEAVENLY", .color = ui.rgb(0x49C9FB) },
    .{ .abbrev = "VVD", .name = "VIVID", .color = ui.rgb(0xFF59CD) },
    .{ .abbrev = "XCD", .name = "EXCEED", .color = ui.rgb(0x187FFF) },
};

pub const Chart = struct {
    level: u8,
    difficulty: u8,
    effector: []const u8,
    illustrator: []const u8,
};

pub const Song = struct {
    hash: u64,
    name: []const u8,
    title: []const u8,
    artist: []const u8,
    bpm: []const u8,
    preview: f32,
    charts: [4]?i64,
};

var chart_insert: db.Statement(Chart, void) = undefined;
var song_insert: db.Statement(Song, void) = undefined;
var song_query: db.Statement([]const u8, struct { u64, [4]?i64 }) = undefined;
var song_delete: db.Statement([]const u8, void) = undefined;
var chart_delete: db.Statement([4]?i64, void) = undefined;
var song_erase: db.Statement([]const u8, void) = undefined;
var name_query: db.Statement(void, struct { []const u8, [4]?i64 }) = undefined;

pub fn init() !void {
    try chart_insert.prepare("INSERT INTO chart(level,difficulty,effector,illustrator) VALUES(?,?,?,?)");
    try song_insert.prepare("INSERT INTO song(hash,name,title,artist,bpm,preview,chart1,chart2,chart3,chart4) VALUES(?,?,?,?,?,?,?,?,?,?)");
    try song_query.prepare("SELECT hash,chart1,chart2,chart3,chart4 FROM song WHERE name = ?");
    try song_delete.prepare("DELETE FROM song WHERE name = ?");
    try chart_delete.prepare("DELETE FROM chart WHERE id = ? OR id = ? OR id = ? OR id = ?");
    try song_erase.prepare("UPDATE song SET name = NULL WHERE name = ?");
    try name_query.prepare("SELECT name,chart1,chart2,chart3,chart4 FROM song WHERE name IS NOT NULL");
}

var songs: std.fs.Dir = undefined;
var songs_iter: std.fs.Dir.Iterator = undefined;
var names = std.StringHashMap(void).init(game.state_allocator);
var name_iter: ?@TypeOf(name_query).RowIterator = null;

pub fn enter() !void {
    ui.locate(10, 10);
    try ui.setTextSize(36);
    songs = try vfs.openIterableDir("songs");
    songs_iter = songs.iterateAssumeFirstIteration();
    game.window.swapInterval(0);
    try db.exec("BEGIN");
}

pub fn leave() !void {
    try db.exec("COMMIT");
    game.window.swapInterval(config.vsync);
    songs.close();
    names.clearAndFree();
    name_iter = null;
}

fn delete(name: []const u8, charts: [4]?i64) !void {
    if (song_delete.exec(name)) {
        try chart_delete.exec(charts);
    } else |err| switch (err) {
        error.ForeignKey => try song_erase.exec(name),
        else => return err,
    }
}

pub fn update() !void {
    if (try songs_iter.next()) |entry| {
        var song_dir = songs.openDir(entry.name, .{}) catch {
            std.log.err("could not open songs/{s}", .{entry.name});
            return;
        };
        defer song_dir.close();

        const bytes = vfs.readFileAt(game.temp_allocator, song_dir, "info.txt") catch |err| {
            std.log.err("could not read songs/{s}/info.txt: {s}", .{ entry.name, @errorName(err) });
            return err;
        };
        var ini = Ini{ .bytes = bytes };
        if (Info.load(&ini)) |info| {
            var song, const charts = info.make(entry.name, song_dir) catch |err| switch (err) {
                error.Ignore => return,
                else => return err,
            };

            if (charts[0] == null and charts[1] == null and charts[2] == null and charts[3] == null) {
                std.log.err("songs/{s}/info.txt has no charts", .{song.name});
                return;
            }

            try names.put(try game.state_allocator.dupe(u8, entry.name), {});

            var song_iter = try song_query.iter(song.name);
            if (try song_iter.next()) |value| {
                const hash, const old_charts = value;
                if (hash == song.hash) return;
                try delete(song.name, old_charts);
            }

            for (charts, &song.charts) |maybe_chart, *id| {
                if (maybe_chart) |chart| {
                    try chart_insert.exec(chart);
                    id.* = db.lastRowId();
                }
            }
            try song_insert.exec(song);
        } else |err| {
            std.log.err("songs/{s}/info.txt line {}: {s}", .{ entry.name, ini.line, @errorName(err) });
        }
    } else if (name_iter) |iter| {
        if (try iter.next()) |value| {
            const name, const charts = value;
            if (!names.contains(name)) {
                try delete(name, charts);
            }
        } else {
            try game.state.change(.song_select);
        }
    } else {
        name_iter = try name_query.iter({});
    }
}

pub fn draw2D() !void {
    try ui.drawText("Updating song cache...", .{});
}

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
        difficulty: u8 = 0,
        effector: ?[]const u8 = null,
        illustrator: ?[]const u8 = null,
    };

    fn load(iter: *Ini) !Info {
        var info = Info{};
        var current_chart: ?*ChartInfo = null;

        while (try iter.next()) |entry| {
            if (entry.value) |_| {
                if (current_chart) |chart| {
                    try entry.unpack(null, ChartInfo, chart, .{});
                } else {
                    try entry.unpack(null, SongInfo, &info.song, .{});
                }
            } else {
                current_chart = blk: {
                    for (difficulties, 0..) |difficulty, i| {
                        if (std.mem.eql(u8, difficulty.abbrev, entry.key)) {
                            const chart = &info.charts[std.math.clamp(i, 0, 3)];
                            chart.difficulty = @intCast(i);
                            break :blk chart;
                        }
                    }
                    return error.UnknownDifficulty;
                };
            }
        }

        return info;
    }

    fn make(self: Info, name: []const u8, dir: std.fs.Dir) !struct { Song, [4]?Chart } {
        var song = Song{
            .hash = undefined,
            .name = name,
            .title = self.song.title,
            .artist = self.song.artist,
            .bpm = self.song.bpm,
            .preview = self.song.preview,
            .charts = .{null} ** 4,
        };
        var charts: [4]?Chart = .{null} ** 4;
        var hash = std.hash.XxHash3.init(0);

        hash.update(song.title);
        hash.update(song.artist);
        hash.update(song.bpm);
        hash.update(std.mem.asBytes(&song.preview));

        var last_effector: []const u8 = "unknown";
        var last_illustrator: []const u8 = "unknown";

        for (&charts, self.charts, 0..) |*chart, info, tier| {
            if (info.level != 0) {
                if (info.effector) |effector| last_effector = effector;
                if (info.illustrator) |illustrator| last_illustrator = illustrator;

                hash.update(last_effector);
                hash.update(last_illustrator);
                hash.update(&[_]u8{ info.difficulty, info.level });

                const index: u8 = @intCast(tier + '1');
                hash.update(vfs.readFileAt(game.temp_allocator, dir, .{index} ++ ".bin") catch |err| {
                    std.log.err("could not read songs/{s}/{c}.bin: {s}", .{ name, index, @errorName(err) });
                    return error.Ignore;
                });

                chart.* = .{
                    .level = info.level,
                    .difficulty = info.difficulty,
                    .effector = last_effector,
                    .illustrator = last_illustrator,
                };
            }
        }

        song.hash = hash.final();
        return .{ song, charts };
    }
};
