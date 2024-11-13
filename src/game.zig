const std = @import("std");
const builtin = @import("builtin");
const wio = @import("wio");
const vfs = @import("vfs.zig");
const config = @import("config.zig");
const input = @import("input.zig");
const renderer = @import("renderer.zig");
const text = @import("text.zig");
const ui = @import("ui.zig");
const audio = @import("audio.zig");
const db = @import("db.zig");
const Strings = @import("Strings.zig");

pub const State = struct {
    const Fn = *const fn () anyerror!void;

    init: Fn,
    enter: Fn,
    leave: Fn,
    update: Fn,
    draw3D: Fn,
    draw2D: Fn,

    fn empty() !void {}

    fn v(comptime namespace: type) State {
        var result: State = undefined;
        inline for (@typeInfo(State).@"struct".fields) |field| {
            @field(result, field.name) = if (@hasDecl(namespace, field.name))
                @field(namespace, field.name)
            else
                empty;
        }
        return result;
    }

    const vtables = struct {
        pub const song_select = v(@import("state/song_select.zig"));
        pub const cache = v(@import("state/cache.zig"));
        pub const ingame = v(@import("state/ingame.zig"));
    };

    pub fn change(self: *State, comptime name: anytype) !void {
        try self.leave();
        _ = state_arena.reset(.retain_capacity);
        self.* = @field(vtables, @tagName(name));
        try self.enter();
    }
};

pub var state = State.vtables.cache;
pub var strings = &Strings.English;

const Language = struct {
    name: []const u8,
    strings: *const Strings,
};

pub const languages = blk: {
    const decls = @typeInfo(Strings).@"struct".decls;
    var result: [decls.len]Language = undefined;
    for (decls, &result) |decl, *p| {
        p.* = .{ .name = decl.name, .strings = &@field(Strings, decl.name) };
    }
    break :blk result;
};

pub const allocator = std.heap.c_allocator;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var state_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const temp_allocator = arena.allocator();
pub const state_allocator = state_arena.allocator();

pub var window: wio.Window = undefined;

pub fn main() !void {
    try wio.init(allocator, .{
        .joystick = true,
        .joystickConnectedFn = input.joystickConnected,
        .audio = true,
        .audioDefaultOutputFn = audio.open,
        .opengl = true,
    });
    try vfs.init();

    for (languages) |language| {
        if (std.mem.eql(u8, language.name, config.language)) {
            strings = language.strings;
            break;
        }
    }

    window = try wio.createWindow(.{
        .title = "Voltyx",
        .size = .{ .width = config.width, .height = config.height },
        .scale = config.scale,
        .mode = config.window_mode,
        .cursor_mode = .hidden,
    });

    try input.init();
    try renderer.init();
    try text.init();
    try ui.init();
    try db.init();

    inline for (@typeInfo(State.vtables).@"struct".decls) |decl| {
        try @field(State.vtables, decl.name).init();
    }

    return wio.run(loop, .{});
}

fn loop() !bool {
    _ = arena.reset(.retain_capacity);

    while (window.getEvent()) |event| switch (event) {
        .close => {
            try config.save();
            return false;
        },
        .create => try state.enter(),
        .size => |size| {
            if (config.window_mode == .normal) {
                config.width = size.width;
                config.height = size.height;
            }
        },
        .mode => |mode| config.window_mode = mode,
        .framebuffer => |size| renderer.viewport(size),
        .scale => |scale| config.scale = scale,
        .button_press => |button| input.buttonPress(button),
        .button_release => |button| input.buttonRelease(button),
        .unfocused => input.unfocused(),
        else => {},
    };

    try input.updateJoystick();
    try state.update();
    try renderer.draw();

    return true;
}

pub fn format(comptime fmt: []const u8, args: anytype) ![]u8 {
    return try std.fmt.allocPrint(temp_allocator, fmt, args);
}

pub fn messageBox(message: []const u8) !void {
    wio.messageBox(.err, "Voltyx", message);
    return error.MessageBoxShown;
}
