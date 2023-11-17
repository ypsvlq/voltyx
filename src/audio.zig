const std = @import("std");
const sysaudio = @import("mach-sysaudio");
const Opus = @import("mach-opus");
const game = @import("game.zig");
const vfs = @import("vfs.zig");
const log = std.log.scoped(.audio);

var context: sysaudio.Context = undefined;
var player: sysaudio.Player = undefined;
var mutex = std.Thread.Mutex{};
var samples: []f32 = &.{};
var i: usize = 0;

pub fn init() !void {
    context = try sysaudio.Context.init(null, game.allocator, .{ .app_name = "Voltyx" });
    try context.refresh();
    const device = context.defaultDevice(.playback) orelse return error.NoDevice;
    player = try context.createPlayer(device, writeFn, .{ .sample_rate = 48000, .media_role = .game });
    try player.start();
}

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

pub fn play(path: []const u8) !void {
    mutex.lock();
    defer mutex.unlock();

    if (samples.len > 0) {
        game.allocator.free(samples);
    }

    const file = try vfs.openFile(path);
    defer file.close();

    const decoded = try Opus.decodeStream(game.allocator, .{ .file = file });
    samples = decoded.samples;
    i = 0;
}

pub fn stop() !void {
    mutex.lock();
    defer mutex.unlock();

    game.allocator.free(samples);
    samples = &.{};
}
