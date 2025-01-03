const std = @import("std");
const build_options = @import("build_options");
const game = @import("game.zig");
const config = @import("config.zig");
const fs = std.fs;

var vpath: []const u8 = undefined;
var vdir: fs.Dir = undefined;
var assets: fs.Dir = undefined;

pub fn init() !void {
    vpath = try fs.selfExeDirPathAlloc(game.allocator);
    vdir = try fs.openDirAbsolute(vpath, .{});
    if (build_options.asset_path.len > 0) {
        assets = try vdir.openDir(build_options.asset_path, .{});
    }

    try config.load();
    if (config.appdata) {
        game.allocator.free(vpath);
        vdir.close();
        vpath = try fs.getAppDataDir(game.allocator, "Voltyx");
        vdir = try fs.cwd().makeOpenPath(vpath, .{});
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

pub fn loadAsset(comptime path: []const u8) ![]const u8 {
    if (build_options.asset_path.len > 0) {
        return readFileAt(game.allocator, assets, path);
    } else {
        return @embedFile("assets/" ++ path);
    }
}
