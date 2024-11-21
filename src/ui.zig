const std = @import("std");
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

var cursor_x: f32 = 0;
var cursor_y: f32 = 0;

pub fn locate(x: f32, y: f32) void {
    cursor_x = x * config.scale;
    cursor_y = y * config.scale;
}

pub fn newline() void {
    cursor_y += text.height;
}

pub fn drawText(string: []const u8, color: [3]f32) !void {
    _ = try text.draw(string, cursor_x, cursor_y, color);
}

pub fn setTextSize(size: u32) !void {
    return text.setSize(scale(size));
}

pub fn drawImage(texture: u32, x_: f32, y_: f32, w_: f32, h_: f32) void {
    image_program.use();
    image_program.setUniform(.projection, &renderer.ortho);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    image_program.setUniform(.texture, 0);

    const x = scale(x_);
    const y = scale(y_);
    const w = scale(w_);
    const h = scale(h_);
    renderer.drawQuad(image_program, x, renderer.height - y - h, w, h);
}

pub fn rgb(comptime value: comptime_int) [3]f32 {
    const r: comptime_float = @floatFromInt((value & 0xFF0000) >> 16);
    const g: comptime_float = @floatFromInt((value & 0xFF00) >> 8);
    const b: comptime_float = @floatFromInt(value & 0xFF);
    return .{ r / 255.0, g / 255.0, b / 255.0 };
}

fn scale(value: anytype) @TypeOf(value) {
    if (@TypeOf(value) == f32) return value * config.scale;
    const float: f32 = @floatFromInt(value);
    return @intFromFloat(float * config.scale);
}
