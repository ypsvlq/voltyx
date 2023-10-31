const std = @import("std");
const glfw = @import("mach-glfw");
const vfs = @import("vfs.zig");
const config = @import("config.zig");
const input = @import("input.zig");
const renderer = @import("renderer.zig");
const text = @import("text.zig");
const ui = @import("ui.zig");
const audio = @import("audio.zig");

pub const State = enum {
    song_select,
    ingame,

    pub const VTable = struct {
        const Fn = *const fn () anyerror!void;

        init: Fn,
        enter: Fn,
        leave: Fn,
        update: Fn,
        draw3D: Fn,
        draw2D: Fn,
    };

    fn empty() !void {}

    fn v(comptime namespace: type) VTable {
        var result: VTable = undefined;
        inline for (@typeInfo(VTable).Struct.fields) |field| {
            @field(result, field.name) = if (@hasDecl(namespace, field.name))
                @field(namespace, field.name)
            else
                empty;
        }
        return result;
    }

    pub fn vtable(self: State) VTable {
        return switch (self) {
            .song_select => v(@import("state/song_select.zig")),
            .ingame => v(@import("state/ingame.zig")),
        };
    }
};

pub var state = State.song_select;
var last_state = State.song_select;

pub const allocator = std.heap.c_allocator;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const temp_allocator = arena.allocator();

pub var window: glfw.Window = undefined;

fn glfwError(_: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.scoped(.glfw).err("{s}", .{description});
}

pub fn main() !void {
    try vfs.init();
    try config.load();

    glfw.setErrorCallback(glfwError);
    if (!glfw.init(.{})) return error.WindowCreation;
    defer glfw.terminate();

    window = glfw.Window.create(config.width, config.height, "Voltyx", null, null, .{
        .scale_to_monitor = true,
        .maximized = config.maximized,
    }) orelse return error.WindowCreation;

    try input.init(window);
    try renderer.init();
    try text.init();
    try ui.init();
    try audio.init();
    input.initJoystickLasers();

    for (std.enums.values(State)) |state_| {
        try state_.vtable().init();
    }
    try state.vtable().enter();

    while (!window.shouldClose()) {
        _ = arena.reset(.retain_capacity);

        if (state != last_state) {
            try last_state.vtable().leave();
            try state.vtable().enter();
            last_state = state;
        }

        try state.vtable().update();
        try renderer.draw();
        glfw.pollEvents();
        input.updateJoystick();
    }

    try config.save();
}
