const std = @import("std");
const sysaudio = @import("mach-sysaudio");
const Opus = @import("mach-opus");
const game = @import("game.zig");
const vfs = @import("vfs.zig");
const log = std.log.scoped(.audio);

var context: sysaudio.Context = undefined;
var player: sysaudio.Player = undefined;
var samples: []f32 = &.{};
var i: usize = 0;

pub fn init() !void {
    context = try sysaudio.Context.init(null, game.allocator, .{ .app_name = "Voltyx" });
}

fn writeFn(_: ?*anyopaque, frame_count_max: usize) void {
    for (0..frame_count_max) |frame| {
        for (0..2) |channel| {
            if (i == samples.len) {
                player.pause() catch log.err("could not pause", .{});
                return;
            }
            player.write(player.channels()[channel], frame, samples[i]);
            i += 1;
        }
    }
}

pub fn play(path: []const u8) !void {
    try context.refresh();
    const device = context.defaultDevice(.playback) orelse return error.NoDevice;
    player = try context.createPlayer(device, writeFn, .{ .sample_rate = 48000, .media_role = .game });

    if (samples.len > 0) {
        i = 0;
        game.allocator.free(samples);
    }

    const file = try vfs.openFile(path);
    defer file.close();

    const decoded = try Opus.decodeStream(game.allocator, std.io.StreamSource{ .file = file });
    samples = decoded.samples;
    try player.start();
}

pub fn stop() !void {
    player.deinit();
}
