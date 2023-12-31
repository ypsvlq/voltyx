const std = @import("std");
const game = @import("game.zig");
const config = @import("config.zig");
const fs = std.fs;

var vdir: fs.Dir = undefined;

pub fn init() !void {
    const self_dir_path = try fs.selfExeDirPathAlloc(game.temp_allocator);
    vdir = try fs.openDirAbsolute(self_dir_path, .{});
    try config.load();

    if (config.appdata) {
        vdir.close();
        const appdata_path = try fs.getAppDataDir(game.temp_allocator, "Voltyx");
        vdir = try fs.openDirAbsolute(appdata_path, .{});
        try config.load();
    }
}

pub fn openFile(path: []const u8) !fs.File {
    return vdir.openFile(path, .{});
}

pub fn openIterableDir(path: []const u8) !fs.IterableDir {
    try vdir.makePath(path);
    return vdir.openIterableDir(path, .{});
}

pub fn absolutePath(path: []const u8) ![:0]u8 {
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const realpath = try vdir.realpath(path, &buffer);
    return game.temp_allocator.dupeZ(u8, realpath);
}

pub fn readFileAt(allocator: std.mem.Allocator, dir: fs.Dir, path: []const u8) ![]u8 {
    const file = try dir.openFile(path, .{});
    defer file.close();
    const buf = try allocator.alloc(u8, try file.getEndPos());
    try file.reader().readNoEof(buf);
    return buf;
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return readFileAt(allocator, vdir, path);
}

pub fn createFile(path: []const u8) !fs.File {
    return vdir.createFile(path, .{});
}
