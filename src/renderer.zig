const std = @import("std");
const glfw = @import("mach-glfw");
const img = @import("zigimg");
const gl = @import("gl.zig");
const glw = @import("glw.zig");
const game = @import("game.zig");
const vfs = @import("vfs.zig");
const config = @import("config.zig");
const ui = @import("ui.zig");

var lane_program: glw.Program(.{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, view, texture, left_color, right_color },
}) = undefined;

var lane_texture: u32 = undefined;

pub fn init() !void {
    glfw.makeContextCurrent(game.window);
    glfw.swapInterval(1);
    try gl.load(glfw.getProcAddress);

    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    const size = game.window.getSize();
    gl.viewport(0, 0, @bitCast(size.width), @bitCast(size.height));
    game.window.setSizeCallback(sizeCallback);

    lane_texture = try glw.loadPNG("textures/lane.png");
    try lane_program.compile("shaders/lane.vert", "shaders/lane.frag");
    lane_program.enableAttribArray(.vertex);
}

fn sizeCallback(_: glfw.Window, width: i32, height: i32) void {
    gl.viewport(0, 0, width, height);
}

pub fn draw() !void {
    gl.clear(gl.COLOR_BUFFER_BIT);

    drawLane();

    gl.enable(gl.BLEND);
    try ui.drawText();
    gl.disable(gl.BLEND);

    game.window.swapBuffers();
}

var camera_pos = [3]f32{ 0, -0.6, -1 };
var pitch: f32 = 0.3;
var yaw: f32 = 0;
var roll: f32 = 0;

fn drawLane() void {
    lane_program.use();

    const size = game.window.getSize();
    const width: f32 = @floatFromInt(size.width);
    const height: f32 = @floatFromInt(size.height);
    const perspective = glw.perspective(60, width / height, 0.1, 100);
    lane_program.setUniform(.projection, &perspective);

    const rx = glw.rotationX(pitch);
    const ry = glw.rotationY(yaw);
    const rz = glw.rotationZ(roll);
    const r = glw.multiply(rz, glw.multiply(ry, rx));
    const t = glw.translation(camera_pos);
    const view = glw.transpose(glw.multiply(t, r));
    lane_program.setUniform(.view, &view);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, lane_texture);
    lane_program.setUniform(.texture, 0);

    lane_program.setUniform(.left_color, config.left_color);
    lane_program.setUniform(.right_color, config.right_color);

    const vertices = [_]f32{
        -0.5, 0,   0, 1,
        -0.5, -10, 0, 0,
        0.5,  -10, 1, 0,
        0.5,  0,   1, 1,
    };
    lane_program.setAttribPointer(.vertex, &vertices, 4, 0);

    const indices = [_]u8{
        0, 1, 2,
        0, 2, 3,
    };
    gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_BYTE, &indices);
}
