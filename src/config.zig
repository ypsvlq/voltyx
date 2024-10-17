const std = @import("std");
const Ini = @import("ylib").Ini;
const vfs = @import("vfs.zig");
const game = @import("game.zig");
const ui = @import("ui.zig");
const input = @import("input.zig");
const renderer = @import("renderer.zig");

pub var appdata = true;

pub var width: u16 = 800;
pub var height: u16 = 450;
pub var scale: f32 = 1;
pub var maximized: bool = false;
pub var vsync: u1 = 1;
pub var samples: ?u31 = null;

pub var language: []const u8 = "English";

pub var joystick_id: ?[]const u8 = null;
pub var joystick_axes = [2]u8{ 0, 1 };

pub var left_color = ui.rgb(0x1DE5EC);
pub var right_color = ui.rgb(0xF761C3);

pub var song: usize = 0;
pub var difficulty: u2 = 3;

const Section = struct {
    load: *const fn ([]const u8, []const u8) anyerror!void,
    save: *const fn (std.fs.File.Writer) anyerror!void,
};

const sections = std.StaticStringMap(Section).initComptime(.{
    .{ "keys", .{ .load = input.keyConfigLoad, .save = input.keyConfigSave } },
    .{ "joystick", .{ .load = input.joystickConfigLoad, .save = input.joystickConfigSave } },
});

fn process(iter: *Ini) !void {
    var section: ?Section = null;
    while (try iter.next()) |entry| {
        if (entry.value) |value| {
            if (section) |handlers| {
                try handlers.load(entry.key, value);
            } else {
                try entry.unpack(game.allocator, @This(), @This(), .{});
            }
        } else {
            section = sections.get(entry.key) orelse return error.UnknownSection;
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
        .int, .float, .bool => try writer.print("{s} = {}\n", .{ name, value }),
        .array => {
            try writer.print("{s} =", .{name});
            for (value) |elem| {
                try writer.print(" {}", .{elem});
            }
            try writer.writeByte('\n');
        },
        .optional => if (value) |unwrapped| try writeEntry(writer, name, unwrapped),
        .@"fn", .type => {},
        else => @compileError("unhandled type: " ++ @typeName(T)),
    }
}

pub fn save() !void {
    const file = try vfs.createFile("config.ini");
    defer file.close();
    const writer = file.writer();

    inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        const value = @field(@This(), decl.name);
        try writeEntry(writer, decl.name, value);
    }

    for (sections.keys(), sections.values()) |name, section| {
        try writer.print("\n[{s}]\n", .{name});
        try section.save(writer);
    }
}
