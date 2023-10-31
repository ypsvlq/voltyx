const std = @import("std");
const gl = @import("../gl.zig");
const glw = @import("../glw.zig");
const game = @import("../game.zig");
const config = @import("../config.zig");
const renderer = @import("../renderer.zig");
const ui = @import("../ui.zig");
const text = @import("../text.zig");
const input = @import("../input.zig");
const audio = @import("../audio.zig");

var lane_program: glw.Program(.{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, view, texture, left_color, right_color },
}) = undefined;

var lane_texture: u32 = undefined;

pub fn init() !void {
    try lane_program.compile("shaders/lane.vert", "shaders/lane.frag");
    lane_program.enableAttribArray(.vertex);
    lane_texture = try glw.loadPNG("textures/lane.png");
}

pub fn enter() !void {
    try ui.setTextSize(32);
}

var camera_pos = [3]f32{ 0, -0.46681779, -2.5830276 };
var pitch: f32 = -1.4167554;
var yaw: f32 = 0;
var roll: f32 = 0;

pub fn draw3D() !void {
    lane_program.use();
    lane_program.setUniform(.projection, &renderer.perspective);
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

    renderer.drawQuad(lane_program, -0.5, 0, 1, 25);
}

pub fn draw2D() !void {
    const x = 10;
    var y: u16 = 10;

    var iter = input.state.buttons.iterator();
    while (iter.next()) |button| {
        _ = try text.draw(@tagName(button), x, y, .{ 1, 1, 1 });
        y += text.height;
    }

    for (input.state.lasers, [2][]const u8{ "vol-l", "vol-r" }) |laser, name| {
        if (laser != 0) {
            const laser_text = try std.fmt.allocPrint(game.temp_allocator, "{s} {s}", .{ name, if (laser < 0) "left" else "right" });
            _ = try text.draw(laser_text, x, y, .{ 1, 1, 1 });
            y += text.height;
        }
    }

    if (input.state.buttons.contains(.back)) {
        game.state = .song_select;
        try audio.stop();
    }
}
