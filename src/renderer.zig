const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl.zig");
const glw = @import("glw.zig");
const game = @import("game.zig");
const config = @import("config.zig");

pub var width: f32 = undefined;
pub var height: f32 = undefined;
pub var ortho: [4][4]f32 = undefined;
pub var perspective: [4][4]f32 = undefined;

var rgb_program: glw.Program(.{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, texture },
}) = undefined;

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
    game.window.setSizeCallback(sizeCallback);
    sizeCallback(game.window, @bitCast(size.width), @bitCast(size.height));

    try rgb_program.compile("shaders/rgb.vert", "shaders/rgb.frag");
    try lane_program.compile("shaders/lane.vert", "shaders/lane.frag");
    lane_program.enableAttribArray(.vertex);
    lane_texture = try glw.loadPNG("textures/lane.png");
}

fn sizeCallback(_: glfw.Window, width_: i32, height_: i32) void {
    gl.viewport(0, 0, width_, height_);

    width = @floatFromInt(width_);
    height = @floatFromInt(height_);
    ortho = glw.ortho(0, width, 0, height, -1, 1);
    perspective = glw.perspective(45, width / height, 0.1, 100);
}

pub fn draw() !void {
    gl.clear(gl.COLOR_BUFFER_BIT);

    if (game.state == .ingame) {
        drawLane();
    }

    gl.enable(gl.BLEND);
    try game.state.vtable().draw();
    gl.disable(gl.BLEND);

    game.window.swapBuffers();
}

pub fn drawQuad(program: anytype, x: f32, y: f32, w: f32, h: f32) void {
    const vertices = [_]f32{
        x,     y,     0, 1,
        x,     y + h, 0, 0,
        x + w, y + h, 1, 0,
        x + w, y,     1, 1,
    };
    program.setAttribPointer(.vertex, &vertices, 4, 0);

    const indices = [_]u8{
        0, 1, 2,
        0, 2, 3,
    };
    gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_BYTE, &indices);
}

pub fn drawQuad2D(texture: u32, x: f32, y: f32, w: f32, h: f32) void {
    rgb_program.use();
    rgb_program.setUniform(.projection, &ortho);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    rgb_program.setUniform(.texture, 0);

    drawQuad(rgb_program, x, y, w, h);
}

var camera_pos = [3]f32{ 0, -0.46681779, -2.5830276 };
var pitch: f32 = -1.4167554;
var yaw: f32 = 0;
var roll: f32 = 0;

fn drawLane() void {
    lane_program.use();
    lane_program.setUniform(.projection, &perspective);
    lane_program.setUniform(.left_color, config.left_color);
    lane_program.setUniform(.right_color, config.right_color);

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

    drawQuad(lane_program, -0.5, 0, 1, 25);
}
