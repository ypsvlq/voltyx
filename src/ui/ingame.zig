const std = @import("std");
const game = @import("../game.zig");
const ui = @import("../ui.zig");
const text = @import("../text.zig");
const input = @import("../input.zig");

var height: u16 = undefined;

pub fn init() !void {
    try text.setSize(ui.scaleInt(u32, 32));
    height = @intCast(text.getLineHeight());
}

pub fn deinit() !void {}

pub fn draw() !void {
    const x = 10;
    var y: u16 = 10;

    var iter = input.state.buttons.iterator();
    while (iter.next()) |button| {
        _ = try text.draw(@tagName(button), x, y, .{ 1, 1, 1 });
        y += height;
    }

    for (input.state.lasers, [2][]const u8{ "vol-l", "vol-r" }) |laser, name| {
        if (laser != 0) {
            const laser_text = try std.fmt.allocPrint(game.temp_allocator, "{s} {s}", .{ name, if (laser < 0) "left" else "right" });
            _ = try text.draw(laser_text, x, y, .{ 1, 1, 1 });
            y += height;
        }
    }

    if (input.state.buttons.contains(.back)) {
        game.state = .song_select;
    }
}
