const std = @import("std");
const wio = @import("wio");
const gl = @import("gl.zig");
const glw = @import("glw.zig");
const game = @import("game.zig");
const config = @import("config.zig");

pub var width: f32 = undefined;
pub var height: f32 = undefined;
pub var ortho: [4][4]f32 = undefined;
pub var perspective: [4][4]f32 = undefined;
var buffer: u32 = undefined;

pub fn init() !void {
    try game.window.createContext(.{});
    game.window.makeContextCurrent();
    game.window.swapInterval(config.vsync);
    try gl.load(wio.glGetProcAddress);

    gl.clearColor(0, 0, 0, 1);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    gl.genBuffers(1, &buffer);
}

pub fn viewport(size: wio.Size) void {
    gl.viewport(0, 0, size.width, size.height);

    width = @floatFromInt(size.width);
    height = @floatFromInt(size.height);
    ortho = glw.ortho(0, width, 0, height, -1, 1);
    perspective = glw.perspective(45, width / height, 0.1, 100);
}

pub fn draw() !void {
    gl.clear(gl.COLOR_BUFFER_BIT);
    try game.state.draw3D();

    gl.enable(gl.BLEND);
    try game.state.draw2D();
    gl.disable(gl.BLEND);

    game.window.swapBuffers();
}

pub fn drawQuad(program: anytype, x: f32, y: f32, w: f32, h: f32) void {
    const vertices = [_]f32{
        x,     y,     0, 1,
        x,     y + h, 0, 0,
        x + w, y + h, 1, 0,
        x,     y,     0, 1,
        x + w, y + h, 1, 0,
        x + w, y,     1, 1,
    };
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);
    program.setAttribPointer(.vertex, 4, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
}
