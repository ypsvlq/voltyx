const std = @import("std");
const Ini = @import("Ini");
const glfw = @import("mach-glfw");
const game = @import("../game.zig");
const vfs = @import("../vfs.zig");
const db = @import("../db.zig");
const ui = @import("../ui.zig");
const text = @import("../text.zig");

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
    jacket: u8,
    audio: u8,
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
var song_query: db.Statement([]const u8, u64) = undefined;
var song_erase: db.Statement([]const u8, void) = undefined;

pub fn init() !void {
    try chart_insert.prepare("INSERT INTO chart(level,difficulty,effector,illustrator,jacket,audio) VALUES(?,?,?,?,?,?)");
    try song_insert.prepare("INSERT INTO song(hash,name,title,artist,bpm,preview,chart1,chart2,chart3,chart4) VALUES(?,?,?,?,?,?,?,?,?,?)");
    try song_query.prepare("SELECT hash FROM song WHERE name = ?");
    try song_erase.prepare("UPDATE song SET name = NULL WHERE name = ?");
    try ui.setTextSize(36);
}

var songs: std.fs.Dir = undefined;
var songs_iter: std.fs.Dir.Iterator = undefined;

pub fn enter() !void {
    songs = try vfs.openIterableDir("songs");
    songs_iter = songs.iterateAssumeFirstIteration();
}

pub fn leave() !void {
    songs.close();
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
            const song, const charts = info.make(entry.name, song_dir) catch |err| switch (err) {
                error.Ignore => return,
                else => return err,
            };

            if (charts[0] == null and charts[1] == null and charts[2] == null and charts[3] == null) {
                std.log.err("songs/{s}/info.txt has no charts", .{song.name});
                return;
            }

            var song_iter = try song_query.iter(song.name);
            const hash = try song_iter.next();
            if (hash == song.hash) return;

            try db.exec("BEGIN");
            if (hash != null) {
                try song_erase.exec(song.name);
            }
            for (charts, &song.charts) |maybe_chart, *id| {
                if (maybe_chart) |chart| {
                    try chart_insert.exec(chart);
                    id.* = db.lastRowId();
                }
            }
            try song_insert.exec(song);
            try db.exec("COMMIT");
        } else |err| {
            std.log.err("songs/{s}/info.txt line {}: {s}", .{ entry.name, ini.line, @errorName(err) });
        }
    } else {
        try game.state.change(.song_select);
    }
}

pub fn draw2D() !void {
    _ = try text.draw("Updating song cache...", 10, 10, .{ 1, 1, 1 });
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
        difficulty: []const u8 = "<unset>",
        effector: ?[]const u8 = null,
        illustrator: ?[]const u8 = null,
    };

    fn load(iter: *Ini) !Info {
        var info = Info{};

        while (try iter.next()) |entry| {
            if (iter.section.len == 0) {
                try entry.unpack(null, SongInfo, &info.song, .{});
            } else {
                const index = try std.fmt.parseInt(u8, iter.section, 10);
                if (index < 1 or index > 4) return error.InvalidChartIndex;
                try entry.unpack(null, ChartInfo, &info.charts[index - 1], .{});
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
        var last_jacket: u8 = '1';
        var last_audio: u8 = '1';

        for (&charts, self.charts, 0..) |*chart, info, tier| {
            if (info.level != 0) {
                if (info.effector) |effector| last_effector = effector;
                if (info.illustrator) |illustrator| last_illustrator = illustrator;

                const difficulty: u8 = blk: {
                    for (difficulties, 0..) |difficulty, i| {
                        if (std.mem.eql(u8, difficulty.abbrev, info.difficulty)) {
                            break :blk @intCast(i);
                        }
                    }
                    std.log.err("{s} has unknown difficulty {s}", .{ name, info.difficulty });
                    continue;
                };

                hash.update(last_effector);
                hash.update(last_illustrator);
                hash.update(info.difficulty);
                hash.update(&[_]u8{info.level});

                const index: u8 = @intCast(tier + '1');
                hash.update(vfs.readFileAt(game.temp_allocator, dir, .{index} ++ ".bin") catch |err| {
                    std.log.err("could not read songs/{s}/{c}.bin: {s}", .{ name, index, @errorName(err) });
                    return error.Ignore;
                });

                chart.* = .{
                    .level = info.level,
                    .difficulty = difficulty,
                    .effector = last_effector,
                    .illustrator = last_illustrator,
                    .jacket = try accessChartFile(dir, ".png", index, &last_jacket),
                    .audio = try accessChartFile(dir, ".opus", index, &last_audio),
                };
            }
        }

        song.hash = hash.final();
        return .{ song, charts };
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