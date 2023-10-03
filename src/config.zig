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

const Handlers = struct {
    load: *const fn ([]const u8, []const u8) anyerror!void,
    save: *const fn (std.fs.File.Writer) anyerror!void,
};

const section_handlers = std.ComptimeStringMap(Handlers, .{
    .{ "keys", .{ .load = input.keyConfigLoad, .save = input.keyConfigSave } },
    .{ "joystick", .{ .load = input.joystickConfigLoad, .save = input.joystickConfigSave } },
});

fn set(comptime T: type, ptr: anytype, value: []const u8) !void {
    if (T == []const u8) {
        ptr.* = try game.allocator.dupe(u8, value);
        return;
    }
    switch (@typeInfo(T)) {
        .Int => ptr.* = try std.fmt.parseInt(T, value, 10),
        .Optional => return set(std.meta.Child(T), ptr, value),
        .Fn => {},
        .Type => {},
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
            const handler = section_handlers.get(iter.section) orelse return error.UnknownSection;
            try handler.load(entry.key, entry.value);
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

fn writeEntry(writer: anytype, name: []const u8, value: anytype) !void {
    const T = @TypeOf(value);
    if (T == []const u8) {
        try writer.print("{s} = {s}\n", .{ name, value });
        return;
    }
    switch (@typeInfo(T)) {
        .Int => try writer.print("{s} = {}\n", .{ name, value }),
        .Optional => if (value) |unwrapped| try writeEntry(writer, name, unwrapped),
        .Fn => {},
        .Type => {},
        else => @compileError("unhandled type: " ++ @typeName(T)),
    }
}

pub fn save() !void {
    const file = try vfs.createFile("config.ini");
    defer file.close();
    const writer = file.writer();

    inline for (@typeInfo(@This()).Struct.decls) |decl| {
        const value = @field(@This(), decl.name);
        try writeEntry(writer, decl.name, value);
    }

    for (section_handlers.kvs) |entry| {
        try writer.print("\n[{s}]\n", .{entry.key});
        try entry.value.save(writer);
    }
}
