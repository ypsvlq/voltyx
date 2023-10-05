const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl.zig");
const game = @import("game.zig");
const ui = @import("ui.zig");

pub fn init() !void {
    glfw.makeContextCurrent(game.window);
    glfw.swapInterval(1);
    try gl.load(glfw.getProcAddress);

    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    const size = game.window.getSize();
    gl.viewport(0, 0, @bitCast(size.width), @bitCast(size.height));
    game.window.setSizeCallback(sizeCallback);
}

fn sizeCallback(_: glfw.Window, width: i32, height: i32) void {
    gl.viewport(0, 0, width, height);
}

pub fn draw() !void {
    gl.clear(gl.COLOR_BUFFER_BIT);

    gl.enable(gl.BLEND);
    try ui.drawText();
    gl.disable(gl.BLEND);

    game.window.swapBuffers();
}
