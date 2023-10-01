const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl.zig");

fn glfwError(_: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.scoped(.glfw).err("{s}", .{description});
}

pub fn main() !void {
    glfw.setErrorCallback(glfwError);
    if (!glfw.init(.{})) return error.WindowCreation;
    defer glfw.terminate();

    const window = glfw.Window.create(640, 480, "Voltyx", null, null, .{ .scale_to_monitor = true }) orelse return error.WindowCreation;
    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);
    try gl.load(glfw.getProcAddress);

    while (!window.shouldClose()) {
        gl.clear(gl.COLOR_BUFFER_BIT);
        window.swapBuffers();
        glfw.pollEvents();
    }
}
