const std = @import("std");
const Ini = @import("Ini.zig");
const vfs = @import("vfs.zig");
const game = @import("game.zig");
const input = @import("input.zig");
const log = std.log.scoped(.config);

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

pub fn load() !void {
    const bytes = vfs.readFile(game.temp_allocator, "config.ini") catch return;
    var iter = Ini{ .bytes = bytes };
    while (iter.next() catch |err| {
        log.err("config.ini line {}: {s}", .{ iter.line, @errorName(err) });
        return error.InvalidConfig;
    }) |entry| {
        if (iter.section.len == 0) {
            inline for (@typeInfo(@This()).Struct.decls) |decl| {
                if (std.mem.eql(u8, decl.name, entry.key)) {
                    const ptr = &@field(@This(), decl.name);
                    const T = @TypeOf(ptr.*);
                    try set(T, ptr, entry.value);
                }
            }
        } else {
            const section_handlers = std.ComptimeStringMap(*const fn ([]const u8, []const u8) anyerror!void, .{
                .{ "keys", input.keyConfig },
                .{ "joystick", input.joystickConfig },
            });
            if (section_handlers.get(iter.section)) |handler| {
                try handler(entry.key, entry.value);
            } else {
                log.err("config.ini line {}: unknown section '{s}'", .{ iter.line, iter.section });
                return error.InvalidConfig;
            }
        }
    }
}
