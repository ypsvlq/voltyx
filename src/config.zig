const std = @import("std");
const Ini = @import("Ini.zig");
const vfs = @import("vfs.zig");
const game = @import("game.zig");
const log = std.log.scoped(.config);

pub var width: u16 = 640;
pub var height: u16 = 480;

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
                    switch (@typeInfo(T)) {
                        .Int => ptr.* = try std.fmt.parseInt(T, entry.value, 10),
                        .Fn => {},
                        else => @compileError("unhandled type: " ++ @typeName(T)),
                    }
                }
            }
        } else {
            log.err("config.ini line {}: unknown section '{s}'", .{ iter.line, iter.section });
            return error.InvalidConfig;
        }
    }
}
