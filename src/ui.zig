const std = @import("std");
const glfw = @import("mach-glfw");
const game = @import("game.zig");
const input = @import("input.zig");
const text = @import("text.zig");

var scale: f32 = 1;

pub fn init() !void {
    scale = game.window.getContentScale().y_scale;
    game.window.setContentScaleCallback(scaleCallback);
}

fn scaleCallback(_: glfw.Window, _: f32, y_scale: f32) void {
    scale = y_scale;
}

fn scaleInt(comptime T: type, value: T) T {
    const float: f32 = @floatFromInt(value);
    return @intFromFloat(float * scale);
}

pub fn drawText() !void {
    const x = 10;
    var y: u16 = 10;

    try text.setSize(scaleInt(u32, 32));
    const height: u16 = @intCast(text.getLineHeight());

    var iter = input.state.buttons.iterator();
    while (iter.next()) |button| {
        try text.draw(@tagName(button), x, y);
        y += height;
    }

    for (input.state.lasers, [2][]const u8{ "vol-l", "vol-r" }) |laser, name| {
        if (laser != 0) {
            const laser_text = try std.fmt.allocPrint(game.temp_allocator, "{s} {s}", .{ name, if (laser < 0) "left" else "right" });
            try text.draw(laser_text, x, y);
            y += height;
        }
    }
}
