const std = @import("std");
const game = @import("game.zig");
const config = @import("config.zig");
const fs = std.fs;

var vpath: []const u8 = undefined;
var vdir: fs.Dir = undefined;

pub fn init() !void {
    vpath = try fs.selfExeDirPathAlloc(game.allocator);
    vdir = try fs.openDirAbsolute(vpath, .{});
    try config.load();

    if (config.appdata) {
        game.allocator.free(vpath);
        vdir.close();
        vpath = try fs.getAppDataDir(game.allocator, "Voltyx");
        vdir = try fs.openDirAbsolute(vpath, .{});
        try config.load();
    }
}

pub fn openFile(path: []const u8) !fs.File {
    return vdir.openFile(path, .{});
}

pub fn openIterableDir(path: []const u8) !fs.Dir {
    try vdir.makePath(path);
    return vdir.openDir(path, .{ .iterate = true });
}

pub fn absolutePath(path: []const u8) ![:0]u8 {
    return std.fmt.allocPrintZ(game.temp_allocator, "{s}{c}{s}", .{ vpath, std.fs.path.sep, path });
}

pub fn readFileAt(allocator: std.mem.Allocator, dir: fs.Dir, path: []const u8) ![]u8 {
    const file = try dir.openFile(path, .{});
    defer file.close();

    const size = try file.getEndPos();
    if (size > std.math.maxInt(usize)) return error.OutOfMemory;

    const buf = try allocator.alloc(u8, @intCast(size));
    try file.reader().readNoEof(buf);
    return buf;
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return readFileAt(allocator, vdir, path);
}

pub fn createFile(path: []const u8) !fs.File {
    return vdir.createFile(path, .{});
}
