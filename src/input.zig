const std = @import("std");
const wio = @import("wio");
const game = @import("game.zig");
const config = @import("config.zig");

const Button = enum {
    back,
    start,
    bt_a,
    bt_b,
    bt_c,
    bt_d,
    fx_l,
    fx_r,
};

pub const State = struct {
    buttons: std.EnumSet(Button) = .{},
    lasers: [2]f32 = .{ 0, 0 },
};

pub var state = State{};

pub fn consume(button: Button) bool {
    if (state.buttons.contains(button)) {
        state.buttons.remove(button);
        return true;
    } else {
        return false;
    }
}

pub fn init() !void {
    try openJoystick();

    if (keymap.count() == 0) {
        keymap.put(.enter, .{ .button = .start });
        keymap.put(.escape, .{ .button = .back });
        keymap.put(.left, .{ .laser = .vol_l_left });
        keymap.put(.right, .{ .laser = .vol_l_right });
        keymap.put(.up, .{ .laser = .vol_r_left });
        keymap.put(.down, .{ .laser = .vol_r_right });

        keymap.put(.q, .{ .button = .bt_a });
        keymap.put(.w, .{ .button = .bt_b });
        keymap.put(.o, .{ .button = .bt_c });
        keymap.put(.p, .{ .button = .bt_d });
        keymap.put(.x, .{ .button = .fx_l });
        keymap.put(.comma, .{ .button = .fx_r });
        keymap.put(.@"1", .{ .laser = .vol_l_left });
        keymap.put(.@"2", .{ .laser = .vol_l_right });
        keymap.put(.@"0", .{ .laser = .vol_r_left });
        keymap.put(.minus, .{ .laser = .vol_r_right });

        keymap.put(.u, .{ .button = .bt_a });
        keymap.put(.i, .{ .button = .bt_b });
        keymap.put(.e, .{ .button = .bt_c });
        keymap.put(.r, .{ .button = .bt_d });
        keymap.put(.m, .{ .button = .fx_l });
        keymap.put(.c, .{ .button = .fx_r });
        keymap.put(.@"8", .{ .laser = .vol_l_left });
        keymap.put(.@"9", .{ .laser = .vol_l_right });
        keymap.put(.@"3", .{ .laser = .vol_r_left });
        keymap.put(.@"4", .{ .laser = .vol_r_right });
    }
}

const KeyAction = union(enum) {
    button: Button,
    laser: Laser,

    const Laser = enum {
        vol_l_left,
        vol_l_right,
        vol_r_left,
        vol_r_right,
    };
};

var keymap: std.EnumMap(wio.Button, KeyAction) = .{};

pub fn keyConfigLoad(key_name: []const u8, action_name: []const u8) !void {
    const key = std.meta.stringToEnum(wio.Button, key_name) orelse return error.UnknownKey;
    if (std.meta.stringToEnum(Button, action_name)) |button| {
        keymap.put(key, .{ .button = button });
    } else if (std.meta.stringToEnum(KeyAction.Laser, action_name)) |laser| {
        keymap.put(key, .{ .laser = laser });
    } else {
        return error.UnknownAction;
    }
}

pub fn keyConfigSave(writer: std.fs.File.Writer) !void {
    var iter = keymap.iterator();
    while (iter.next()) |entry| {
        const value = switch (entry.value.*) {
            .button => |button| @tagName(button),
            .laser => |laser| @tagName(laser),
        };
        try writer.print("{s} = {s}\n", .{ @tagName(entry.key), value });
    }
}

fn mapLaserKey(laser: KeyAction.Laser) struct { *f32, f32 } {
    return switch (laser) {
        .vol_l_left => .{ &state.lasers[0], -0.05 },
        .vol_l_right => .{ &state.lasers[0], 0.05 },
        .vol_r_left => .{ &state.lasers[1], -0.05 },
        .vol_r_right => .{ &state.lasers[1], 0.05 },
    };
}

pub fn buttonPress(key: wio.Button) void {
    if (keymap.get(key)) |action| {
        switch (action) {
            .button => |button| state.buttons.insert(button),
            .laser => |laser| {
                const ptr, const value = mapLaserKey(laser);
                ptr.* = value;
            },
        }
    }
}

pub fn buttonRelease(key: wio.Button) void {
    if (keymap.get(key)) |action| {
        switch (action) {
            .button => |button| state.buttons.remove(button),
            .laser => |laser| {
                const ptr, const value = mapLaserKey(laser);
                if (ptr.* == value) {
                    ptr.* = 0;
                }
            },
        }
    }
}

pub fn unfocused() void {
    state.buttons = .{};
    state.lasers = [2]f32{ 0, 0 };
}

var active_joystick: ?wio.Joystick = null;
var joystick_button_map: std.EnumMap(Button, u8) = .{};
var last_joystick_state = State{};
var joystick_laser_flags = [2]bool{ false, false };

pub fn joystickConfigLoad(button_name: []const u8, value: []const u8) !void {
    const button = std.meta.stringToEnum(Button, button_name) orelse return error.UnknownButton;
    const index = try std.fmt.parseInt(u8, value, 10);
    joystick_button_map.put(button, index);
}

pub fn joystickConfigSave(writer: std.fs.File.Writer) !void {
    var iter = joystick_button_map.iterator();
    while (iter.next()) |entry| {
        try writer.print("{s} = {}\n", .{ @tagName(entry.key), entry.value.* });
    }
}

pub fn openJoystick() !void {
    if (active_joystick) |_| return;
    if (config.joystick_id) |id| active_joystick = try wio.openJoystick(id);
}

pub fn updateJoystick() !void {
    if (active_joystick) |*joystick| {
        const data = try joystick.poll() orelse {
            joystick.close();
            active_joystick = null;
            return;
        };

        var new_joystick_state = State{};

        for (std.enums.values(Button)) |button| {
            if (joystick_button_map.get(button)) |index| {
                if (index < data.buttons.len) {
                    const was_active = last_joystick_state.buttons.contains(button);
                    if (data.buttons[index]) {
                        new_joystick_state.buttons.insert(button);
                        if (!was_active) {
                            state.buttons.insert(button);
                        }
                    } else if (was_active) {
                        state.buttons.remove(button);
                    }
                }
            }
        }

        for (config.joystick_axes, &new_joystick_state.lasers) |index, *laser| {
            if (index < data.axes.len) {
                laser.* = @as(f32, @floatFromInt(data.axes[index])) / 32767;
            }
        }

        for (&state.lasers, &joystick_laser_flags, new_joystick_state.lasers, last_joystick_state.lasers) |*out, *flag, new, last| {
            if (new != last) {
                var difference = new - last;
                if (difference > 1) {
                    difference -= 2;
                } else if (difference < -1) {
                    difference += 2;
                }
                out.* = difference;
                flag.* = true;
            } else if (flag.*) {
                out.* = 0;
                flag.* = false;
            }
        }

        last_joystick_state = new_joystick_state;
    }
}
