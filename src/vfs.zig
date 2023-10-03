const std = @import("std");
const game = @import("game.zig");
const fs = std.fs;

var dir: fs.Dir = undefined;

pub fn init() !void {
    const path = try fs.selfExeDirPathAlloc(game.temp_allocator);
    dir = try fs.openDirAbsolute(path, .{});
}

pub fn openFile(path: []const u8) !fs.File {
    return dir.openFile(path, .{});
}

pub fn createFile(path: []const u8) !fs.File {
    return dir.createFile(path, .{});
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try openFile(path);
    defer file.close();
    const buf = try allocator.alloc(u8, try file.getEndPos());
    try file.reader().readNoEof(buf);
    return buf;
}
