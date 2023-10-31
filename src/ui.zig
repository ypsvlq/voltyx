const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl.zig");
const glw = @import("glw.zig");
const game = @import("game.zig");
const text = @import("text.zig");
const renderer = @import("renderer.zig");

pub var scale: f32 = 1;

var rgb_program: glw.Program(.{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, texture },
}) = undefined;

pub fn init() !void {
    scale = game.window.getContentScale().y_scale;
    game.window.setContentScaleCallback(scaleCallback);

    try rgb_program.compile("shaders/rgb.vert", "shaders/rgb.frag");
    rgb_program.enableAttribArray(.vertex);
}

fn scaleCallback(_: glfw.Window, _: f32, y_scale: f32) void {
    scale = y_scale;
}

pub fn scaleInt(comptime T: type, value: T) T {
    const float: f32 = @floatFromInt(value);
    return @intFromFloat(float * scale);
}

pub fn setTextSize(size: u32) !void {
    return text.setSize(scaleInt(u32, size));
}

pub fn drawImage(texture: u32, x: f32, y: f32, w: f32, h: f32) void {
    rgb_program.use();
    rgb_program.setUniform(.projection, &renderer.ortho);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    rgb_program.setUniform(.texture, 0);

    renderer.drawQuad(rgb_program, x, y, w, h);
}
