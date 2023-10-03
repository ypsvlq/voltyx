const std = @import("std");
const game = @import("game.zig");
const config = @import("config.zig");
const fs = std.fs;

var read_dirs = std.ArrayList(fs.Dir).init(game.allocator);
var write_dir: fs.Dir = undefined;

pub fn init() !void {
    const self_dir_path = try fs.selfExeDirPathAlloc(game.temp_allocator);

    if (std.fs.cwd().openDir("data", .{})) |data_dir| {
        try read_dirs.append(data_dir);
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    write_dir = try fs.openDirAbsolute(self_dir_path, .{});
    try read_dirs.append(write_dir);
}

fn forEachDir(comptime field: []const u8, args: anytype) @typeInfo(@TypeOf(@field(fs.Dir, field))).Fn.return_type.? {
    var iter = std.mem.reverseIterator(read_dirs.items);
    while (iter.next()) |dir| {
        if (@call(.auto, @field(fs.Dir, field), .{dir} ++ args)) |result| {
            return result;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    }
    return error.FileNotFound;
}

pub fn openFile(path: []const u8) !fs.File {
    return forEachDir("openFile", .{ path, .{} });
}

pub fn absolutePath(path: []const u8) ![:0]u8 {
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const realpath = try forEachDir("realpath", .{ path, &buffer });
    return game.temp_allocator.dupeZ(u8, realpath);
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try openFile(path);
    defer file.close();
    const buf = try allocator.alloc(u8, try file.getEndPos());
    try file.reader().readNoEof(buf);
    return buf;
}

pub fn createFile(path: []const u8) !fs.File {
    return write_dir.createFile(path, .{});
}
