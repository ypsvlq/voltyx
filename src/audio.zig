const std = @import("std");
const sysaudio = @import("mach-sysaudio");
const Opus = @import("mach-opus");
const game = @import("game.zig");
const vfs = @import("vfs.zig");
const log = std.log.scoped(.audio);

var context: sysaudio.Context = undefined;
var player: sysaudio.Player = undefined;

pub fn init() !void {
    context = try sysaudio.Context.init(null, game.allocator, .{ .app_name = "Voltyx" });
    try context.refresh();
    const device = context.defaultDevice(.playback) orelse return error.NoDevice;
    player = try context.createPlayer(device, writeFn, .{ .sample_rate = 48000, .media_role = .game });
    try player.start();
}

var mutex = std.Thread.Mutex{};
var samples: []f32 = &.{};
var i: usize = 0;

fn writeFn(_: ?*anyopaque, frames: usize) void {
    mutex.lock();
    defer mutex.unlock();

    for (0..frames) |frame| {
        for (0..2) |channel| {
            const sample = if (i < samples.len) samples[i] else 0;
            player.write(player.channels()[channel], frame, sample);
            i +|= 1;
        }
    }
}

pub const PlayOptions = struct {
    start: f32 = 0,
    length: ?f32 = null,
};

pub fn play(path: []const u8, options: PlayOptions) !void {
    mutex.lock();
    defer mutex.unlock();

    const file = try vfs.openFile(path);
    defer file.close();

    const decoded = try Opus.decodeStream(game.allocator, .{ .file = file });

    const indices_per_s = 48000 * 2;
    const start: usize = @intFromFloat(options.start * indices_per_s);
    const length: usize = if (options.length) |length| @intFromFloat(length * indices_per_s) else decoded.samples.len;

    game.allocator.free(samples);
    samples = decoded.samples[0 .. start + length];
    i = start;
}

pub fn stop() !void {
    mutex.lock();
    defer mutex.unlock();

    game.allocator.free(samples);
    samples = &.{};
}
