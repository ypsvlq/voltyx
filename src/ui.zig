const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl.zig");
const glw = @import("glw.zig");
const game = @import("game.zig");
const config = @import("config.zig");
const text = @import("text.zig");
const renderer = @import("renderer.zig");

var image_program: glw.Program("image", .{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, texture },
}) = undefined;

pub fn init() !void {
    try image_program.compile();
    image_program.enableAttribArray(.vertex);
}

pub fn scaleConst(comptime value: comptime_int) u16 {
    return @intFromFloat(value * config.scale);
}

pub fn scaleInt(comptime T: type, value: T) T {
    const float: f32 = @floatFromInt(value);
    return @intFromFloat(float * config.scale);
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

pub fn rgb(comptime value: comptime_int) [3]f32 {
    const r: comptime_float = @floatFromInt((value & 0xFF0000) >> 16);
    const g: comptime_float = @floatFromInt((value & 0xFF00) >> 8);
    const b: comptime_float = @floatFromInt(value & 0xFF);
    return .{ r / 255.0, g / 255.0, b / 255.0 };
}
