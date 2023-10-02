const std = @import("std");
const Ini = @import("Ini.zig");
const vfs = @import("vfs.zig");
const game = @import("game.zig");
const input = @import("input.zig");

pub var width: u16 = 640;
pub var height: u16 = 480;

pub var joystick_name: ?[]const u8 = null;
pub var joystick_vol_l: ?u8 = null;
pub var joystick_vol_r: ?u8 = null;

fn set(comptime T: type, ptr: anytype, value: []const u8) !void {
    if (T == []const u8) {
        ptr.* = try game.allocator.dupe(u8, value);
        return;
    }
    switch (@typeInfo(T)) {
        .Int => ptr.* = try std.fmt.parseInt(T, value, 10),
        .Optional => return set(std.meta.Child(T), ptr, value),
        .Fn => {},
        else => @compileError("unhandled type: " ++ @typeName(T)),
    }
}

fn process(iter: *Ini) !void {
    next: while (try iter.next()) |entry| {
        if (iter.section.len == 0) {
            inline for (@typeInfo(@This()).Struct.decls) |decl| {
                if (std.mem.eql(u8, decl.name, entry.key)) {
                    const ptr = &@field(@This(), decl.name);
                    const T = @TypeOf(ptr.*);
                    try set(T, ptr, entry.value);
                    continue :next;
                }
            }
            return error.UnknownKey;
        } else {
            const section_handlers = std.ComptimeStringMap(*const fn ([]const u8, []const u8) anyerror!void, .{
                .{ "keys", input.keyConfig },
                .{ "joystick", input.joystickConfig },
            });
            const handler = section_handlers.get(iter.section) orelse return error.UnknownSection;
            try handler(entry.key, entry.value);
        }
    }
}

pub fn load() !void {
    const bytes = vfs.readFile(game.temp_allocator, "config.ini") catch return;
    var iter = Ini{ .bytes = bytes };
    process(&iter) catch |err| {
        std.log.err("config.ini line {}: {s}", .{ iter.line, @errorName(err) });
        return err;
    };
}
