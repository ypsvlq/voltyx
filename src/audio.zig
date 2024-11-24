const std = @import("std");
const wio = @import("wio");
const Opus = @import("mach-opus");
const game = @import("game.zig");
const vfs = @import("vfs.zig");
const log = std.log.scoped(.audio);

var output: ?wio.AudioOutput = null;

pub fn open(device: wio.AudioDevice) void {
    if (output) |*old| {
        old.close();
        output = null;
    }
    output = device.openOutput(writeFn, .{ .sample_rate = 48000, .channels = .initMany(&.{ .FL, .FR }) });
}

var mutex = std.Thread.Mutex{};
var samples: []f32 = &.{};
var i: usize = 0;

fn writeFn(buffer: []f32) void {
    mutex.lock();
    defer mutex.unlock();

    const end = @min(buffer.len, samples.len - i);
    @memcpy(buffer[0..end], samples[i .. i + end]);
    @memset(buffer[end..], 0);
    i += end;
}

pub const PlayOptions = struct {
    start: f32 = 0,
    length: ?f32 = null,
};

pub fn load(path: []const u8) ![]f32 {
    const file = try vfs.openFile(path);
    defer file.close();

    const decoded = try Opus.decodeStream(game.allocator, .{ .file = file });
    return decoded.samples;
}

pub fn play(buffer: []f32, options: PlayOptions) !void {
    mutex.lock();
    defer mutex.unlock();

    const indices_per_s = 48000 * 2;
    const start: usize = @intFromFloat(options.start * indices_per_s);
    const length: usize = if (options.length) |length| @intFromFloat(length * indices_per_s) else buffer.len;

    if (start + length > buffer.len) return error.InvalidOffset;

    game.allocator.free(samples);
    samples = buffer[0 .. start + length];
    i = start;
}

pub fn stop() !void {
    mutex.lock();
    defer mutex.unlock();

    game.allocator.free(samples);
    samples = &.{};
    i = 0;
}
