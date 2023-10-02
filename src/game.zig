const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl.zig");
const vfs = @import("vfs.zig");
const config = @import("config.zig");

pub const allocator = std.heap.c_allocator;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const temp_allocator = arena.allocator();

fn glfwError(_: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.scoped(.glfw).err("{s}", .{description});
}

pub fn main() !void {
    try vfs.init();
    try config.load();

    glfw.setErrorCallback(glfwError);
    if (!glfw.init(.{})) return error.WindowCreation;
    defer glfw.terminate();

    const window = glfw.Window.create(config.width, config.height, "Voltyx", null, null, .{ .scale_to_monitor = true }) orelse return error.WindowCreation;
    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);
    try gl.load(glfw.getProcAddress);

    while (!window.shouldClose()) {
        _ = arena.reset(.retain_capacity);
        gl.clear(gl.COLOR_BUFFER_BIT);
        window.swapBuffers();
        glfw.pollEvents();
    }
}
