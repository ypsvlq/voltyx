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

var lane_program: glw.Program("lane", .{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, view, texture, left_color, right_color },
}) = undefined;

var color_program: glw.Program("color", .{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, view, color },
}) = undefined;

var lane_texture: u32 = undefined;

pub fn init() !void {
    try lane_program.compile();
    lane_program.enableAttribArray(.vertex);
    lane_texture = try glw.loadEmbeddedPNG("lane.png");

    try color_program.compile();
}

pub fn enter() !void {
    try ui.setTextSize(32);

    lane_program.use();
    lane_program.setUniform(.left_color, config.left_color);
    lane_program.setUniform(.right_color, config.right_color);
    calculateCamera();
}

var camera_pos = [3]f32{ 0, -0.46681779, -2.5830276 };
var pitch: f32 = -1.4167554;
var yaw: f32 = 0;
var roll: f32 = 0;

fn calculateCamera() void {
    const rx = glw.rotationX(pitch);
    const ry = glw.rotationY(yaw);
    const rz = glw.rotationZ(roll);
    const r = glw.multiply(rz, glw.multiply(ry, rx));
    const t = glw.translation(camera_pos);
    const view = glw.transpose(glw.multiply(t, r));
    lane_program.use();
    lane_program.setUniform(.view, &view);
    color_program.use();
    color_program.setUniform(.view, &view);
}

fn px(value: f32) f32 {
    return value / 770;
}

fn laneStart(lane: i32) f32 {
    return px(@floatFromInt(-269 + (136 * lane)));
}

fn drawBT(lane: u2, y: f32) void {
    renderer.drawQuad(color_program, laneStart(lane), y, px(130), px(130));
}

fn drawFX(lane: u2, y: f32) void {
    renderer.drawQuad(color_program, laneStart(lane), y, px(266), px(130));
}

pub fn draw3D() !void {
    lane_program.use();
    lane_program.setUniform(.projection, &renderer.perspective);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, lane_texture);
    lane_program.setUniform(.texture, 0);

    renderer.drawQuad(lane_program, -0.5, 0, 1, 25);

    color_program.use();
    color_program.setUniform(.projection, &renderer.perspective);

    color_program.setUniform(.color, ui.rgb(0xFF9F01));
    drawFX(2, 1);
    drawFX(2, 2);
    drawFX(0, 3);
    drawFX(0, 4);

    color_program.setUniform(.color, ui.rgb(0xFFFFFF));
    drawBT(0, 1);
    drawBT(1, 2);
    drawBT(2, 3);
    drawBT(3, 4);
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
            const laser_text = try game.format("{s} {s}", .{ name, if (laser < 0) "left" else "right" });
            _ = try text.draw(laser_text, x, y, .{ 1, 1, 1 });
            y += text.height;
        }
    }

    if (input.state.buttons.contains(.back)) {
        try audio.stop();
        try game.state.change(.song_select);
    }
}
