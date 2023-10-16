const std = @import("std");
const glfw = @import("mach-glfw");
const vfs = @import("vfs.zig");
const config = @import("config.zig");
const input = @import("input.zig");
const renderer = @import("renderer.zig");
const text = @import("text.zig");
const ui = @import("ui.zig");
const audio = @import("audio.zig");

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

    window = glfw.Window.create(config.width, config.height, "Voltyx", null, null, .{ .scale_to_monitor = true }) orelse return error.WindowCreation;

    try input.init(window);
    try renderer.init();
    try text.init();
    try ui.init();
    try audio.init();

    if (config.song) |song| {
        try audio.play(song);
    }

    while (!window.shouldClose()) {
        _ = arena.reset(.retain_capacity);
        try renderer.draw();
        glfw.pollEvents();
        input.updateJoystick();
    }

    try config.save();
}
