const std = @import("std");
const glfw = @import("mach-glfw");
const game = @import("game.zig");
const text = @import("text.zig");

pub var scale: f32 = 1;

pub fn init() !void {
    scale = game.window.getContentScale().y_scale;
    game.window.setContentScaleCallback(scaleCallback);
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
