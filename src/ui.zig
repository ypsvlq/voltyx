const std = @import("std");
const glfw = @import("mach-glfw");
const game = @import("game.zig");

pub var scale: f32 = 1;
var last_state = game.State.song_select;

pub fn init() !void {
    scale = game.window.getContentScale().y_scale;
    game.window.setContentScaleCallback(scaleCallback);

    try @import("ui/song_select.zig").init();
}

fn scaleCallback(_: glfw.Window, _: f32, y_scale: f32) void {
    scale = y_scale;
}

pub fn scaleInt(comptime T: type, value: T) T {
    const float: f32 = @floatFromInt(value);
    return @intFromFloat(float * scale);
}

const VTable = struct {
    init: *const fn () anyerror!void,
    deinit: *const fn () anyerror!void,
    draw: *const fn () anyerror!void,
};

fn vtable(comptime namespace: type) VTable {
    return .{ .init = namespace.init, .deinit = namespace.deinit, .draw = namespace.draw };
}

fn stateVTable(state: game.State) VTable {
    return switch (state) {
        .song_select => vtable(@import("ui/song_select.zig")),
        .ingame => vtable(@import("ui/ingame.zig")),
    };
}

pub fn draw() !void {
    const namespace = stateVTable(game.state);

    if (game.state != last_state) {
        try stateVTable(last_state).deinit();
        try namespace.init();
        last_state = game.state;
    }

    try namespace.draw();
}
