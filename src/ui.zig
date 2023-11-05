const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl.zig");
const glw = @import("glw.zig");
const game = @import("game.zig");
const text = @import("text.zig");
const renderer = @import("renderer.zig");

pub var scale: f32 = 1;

var image_program: glw.Program(.{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, texture },
}) = undefined;

pub fn init() !void {
    scale = game.window.getContentScale().y_scale;
    game.window.setContentScaleCallback(scaleCallback);

    try image_program.compile("shaders/image.vert", "shaders/image.frag");
    image_program.enableAttribArray(.vertex);
}

fn scaleCallback(_: glfw.Window, _: f32, y_scale: f32) void {
    scale = y_scale;
}

pub fn scaleConst(comptime value: comptime_int) u16 {
    return @intFromFloat(value * scale);
}

pub fn scaleInt(comptime T: type, value: T) T {
    const float: f32 = @floatFromInt(value);
    return @intFromFloat(float * scale);
}

pub fn setTextSize(size: u32) !void {
    return text.setSize(scaleInt(u32, size));
}

pub fn drawImage(texture: u32, x_: u16, y_: u16, w_: u16, h_: u16) void {
    image_program.use();
    image_program.setUniform(.projection, &renderer.ortho);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    image_program.setUniform(.texture, 0);

    const x: f32 = @floatFromInt(x_);
    const y: f32 = @floatFromInt(y_);
    const w: f32 = @floatFromInt(w_);
    const h: f32 = @floatFromInt(h_);

    renderer.drawQuad(image_program, x, renderer.height - y - h, w, h);
}
