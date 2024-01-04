const std = @import("std");
const Ini = @import("Ini.zig");
const vfs = @import("vfs.zig");
const game = @import("game.zig");
const ui = @import("ui.zig");
const input = @import("input.zig");
const renderer = @import("renderer.zig");

pub var appdata = false;

pub var width: u16 = 800;
pub var height: u16 = 450;
pub var maximized: bool = false;
pub var samples: ?u31 = null;

pub var joystick_name: ?[]const u8 = null;
pub var joystick_axes = [2]u8{ 0, 1 };

pub var left_color = ui.rgb(0x1DE5EC);
pub var right_color = ui.rgb(0xF761C3);

const Handlers = struct {
    load: *const fn ([]const u8, []const u8) anyerror!void,
    save: *const fn (std.fs.File.Writer) anyerror!void,
};

const section_handlers = std.ComptimeStringMap(Handlers, .{
    .{ "keys", .{ .load = input.keyConfigLoad, .save = input.keyConfigSave } },
    .{ "joystick", .{ .load = input.joystickConfigLoad, .save = input.joystickConfigSave } },
});

fn set(allocator: std.mem.Allocator, comptime T: type, ptr: anytype, value: []const u8) !void {
    if (T == []const u8) {
        ptr.* = try allocator.dupe(u8, value);
        return;
    }
    switch (@typeInfo(T)) {
        .Int => ptr.* = try std.fmt.parseInt(T, value, 10),
        .Float => ptr.* = try std.fmt.parseFloat(T, value),
        .Bool => ptr.* = if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else return error.InvalidBool,
        .Optional => return set(allocator, std.meta.Child(T), ptr, value),
        .Array => {
            var iter = std.mem.tokenizeScalar(u8, value, ' ');
            for (ptr) |*elem_ptr| {
                const elem = iter.next() orelse return error.NotEnoughElements;
                try set(allocator, std.meta.Child(T), elem_ptr, elem);
            }
            if (iter.next() != null) return error.ExtraElement;
        },
        .Fn, .Type => {},
        else => @compileError("unhandled type: " ++ @typeName(T)),
    }
}

pub fn loadEntry(allocator: std.mem.Allocator, comptime T: type, value: anytype, entry: Ini.Entry) !void {
    const info = @typeInfo(T).Struct;
    const fields = if (info.fields.len > 0) info.fields else info.decls;
    inline for (fields) |field| {
        if (std.mem.eql(u8, field.name, entry.key)) {
            const ptr = &@field(value, field.name);
            const FieldType = @TypeOf(ptr.*);
            return set(allocator, FieldType, ptr, entry.value);
        }
    }
    return error.UnknownKey;
}

fn process(iter: *Ini) !void {
    while (try iter.next()) |entry| {
        if (iter.section.len == 0) {
            try loadEntry(game.allocator, @This(), @This(), entry);
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
        .Int, .Bool => try writer.print("{s} = {}\n", .{ name, value }),
        .Array => {
            try writer.print("{s} =", .{name});
            for (value) |elem| {
                try writer.print(" {}", .{elem});
            }
            try writer.writeByte('\n');
        },
        .Optional => if (value) |unwrapped| try writeEntry(writer, name, unwrapped),
        .Fn, .Type => {},
        else => @compileError("unhandled type: " ++ @typeName(T)),
    }
}

pub fn save() !void {
    maximized = (game.window.getAttrib(.maximized) == 1);

    if (!maximized) {
        const scale = game.window.getContentScale();
        width = @intFromFloat(renderer.width / scale.x_scale);
        height = @intFromFloat(renderer.height / scale.y_scale);
    }

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
