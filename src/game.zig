const std = @import("std");
const glfw = @import("mach-glfw");
const vfs = @import("vfs.zig");
const config = @import("config.zig");
const input = @import("input.zig");
const renderer = @import("renderer.zig");
const text = @import("text.zig");
const ui = @import("ui.zig");
const audio = @import("audio.zig");

pub const State = enum { song_select, ingame };

pub const StateVTable = struct {
    const Fn = *const fn () anyerror!void;

    init: Fn,
    enter: Fn,
    leave: Fn,
    update: Fn,
    draw3D: Fn,
    draw2D: Fn,

    pub fn change(self: *StateVTable, new: State) !void {
        try self.leave();
        self.* = get(new);
        try self.enter();
    }

    fn empty() !void {}

    fn v(comptime namespace: type) StateVTable {
        var result: StateVTable = undefined;
        inline for (@typeInfo(StateVTable).Struct.fields) |field| {
            @field(result, field.name) = if (@hasDecl(namespace, field.name))
                @field(namespace, field.name)
            else
                empty;
        }
        return result;
    }

    pub fn get(self: State) StateVTable {
        return switch (self) {
            .song_select => v(@import("state/song_select.zig")),
            .ingame => v(@import("state/ingame.zig")),
        };
    }
};

pub var state = StateVTable.get(.song_select);

pub const allocator = std.heap.c_allocator;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const temp_allocator = arena.allocator();

pub var window: glfw.Window = undefined;

fn glfwError(_: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.scoped(.glfw).err("{s}", .{description});
}

pub fn main() !void {
    try vfs.init();

    glfw.setErrorCallback(glfwError);
    if (!glfw.init(.{})) return error.WindowCreation;
    defer glfw.terminate();

    window = glfw.Window.create(config.width, config.height, "Voltyx", null, null, .{
        .scale_to_monitor = true,
        .maximized = config.maximized,
    }) orelse return error.WindowCreation;

    window.setInputMode(.cursor, .hidden);

    try input.init(window);
    try renderer.init();
    try text.init();
    try ui.init();
    try audio.init();
    input.initJoystickLasers();

    for (std.enums.values(State)) |value| {
        try StateVTable.get(value).init();
    }
    try state.enter();

    while (!window.shouldClose()) {
        _ = arena.reset(.retain_capacity);
        try state.update();
        try renderer.draw();
        glfw.pollEvents();
        input.updateJoystick();
    }

    try config.save();
}

pub fn format(comptime fmt: []const u8, args: anytype) ![]u8 {
    return try std.fmt.allocPrint(temp_allocator, fmt, args);
}
