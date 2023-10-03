const std = @import("std");
const game = @import("game.zig");
const fs = std.fs;

var dir: fs.Dir = undefined;
var dir_path: []const u8 = undefined;

pub fn init() !void {
    dir_path = try fs.selfExeDirPathAlloc(game.allocator);
    dir = try fs.openDirAbsolute(dir_path, .{});
}

pub fn openFile(path: []const u8) !fs.File {
    return dir.openFile(path, .{});
}

pub fn createFile(path: []const u8) !fs.File {
    return dir.createFile(path, .{});
}

pub fn absolutePath(path: []const u8) ![:0]u8 {
    return std.fs.path.joinZ(game.temp_allocator, &.{ dir_path, path });
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try openFile(path);
    defer file.close();
    const buf = try allocator.alloc(u8, try file.getEndPos());
    try file.reader().readNoEof(buf);
    return buf;
}
