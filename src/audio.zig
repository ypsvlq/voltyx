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

pub fn play(path: []const u8) !void {
    mutex.lock();
    defer mutex.unlock();

    const file = try vfs.openFile(path);
    defer file.close();

    const decoded = try Opus.decodeStream(game.allocator, .{ .file = file });
    game.allocator.free(samples);
    samples = decoded.samples;
    i = 0;
}

pub fn stop() !void {
    mutex.lock();
    defer mutex.unlock();

    game.allocator.free(samples);
    samples = &.{};
}

const indices_per_s = 48000 * 2;

pub fn playLazy(path: []const u8, start: f32, length: f32) !void {
    const path_arg = try game.allocator.dupe(u8, path);
    const start_arg: usize = @intFromFloat(start * indices_per_s);
    const length_arg: usize = @intFromFloat(length * indices_per_s);

    const thread = try std.Thread.spawn(.{}, load, .{ path_arg, start_arg, length_arg });
    thread.detach();
}

var worker: std.Thread.Id = 0;

fn load(path: []const u8, start: usize, length: usize) !void {
    const id = std.Thread.getCurrentId();
    worker = id;

    const file = try vfs.openFile(path);
    defer file.close();
    game.allocator.free(path);

    const decoded = try Opus.decodeStream(game.allocator, .{ .file = file });

    mutex.lock();
    defer mutex.unlock();

    if (worker == id) {
        game.allocator.free(samples);
        samples = decoded.samples[0 .. start + length];
        i = start;
    } else {
        game.allocator.free(decoded.samples);
    }
}
