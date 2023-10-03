const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl.zig");
const vfs = @import("vfs.zig");
const config = @import("config.zig");
const input = @import("input.zig");
const text = @import("text.zig");
const ui = @import("ui.zig");

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
    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);
    try gl.load(glfw.getProcAddress);

    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    try input.init(window);
    try text.init();

    while (!window.shouldClose()) {
        _ = arena.reset(.retain_capacity);

        gl.clear(gl.COLOR_BUFFER_BIT);
        gl.enable(gl.BLEND);
        try ui.drawText();
        gl.disable(gl.BLEND);
        window.swapBuffers();

        glfw.pollEvents();
        input.updateJoystick();
    }

    try config.save();
}
