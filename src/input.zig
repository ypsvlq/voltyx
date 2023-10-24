const std = @import("std");
const glfw = @import("mach-glfw");
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

pub fn init(window: glfw.Window) !void {
    window.setKeyCallback(keyCallback);
    glfw.Joystick.setCallback(joystickCallback);

    for (std.enums.values(glfw.Joystick.Id)) |id| {
        const joystick = glfw.Joystick{ .jid = id };
        if (joystick.present()) {
            joystickCallback(joystick, .connected);
        }
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

var keymap: std.EnumMap(glfw.Key, KeyAction) = .{};

pub fn keyConfigLoad(key_name: []const u8, action_name: []const u8) !void {
    const key = std.meta.stringToEnum(glfw.Key, key_name) orelse return error.UnknownKey;
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

fn keyCallback(_: glfw.Window, key: glfw.Key, _: i32, event: glfw.Action, _: glfw.Mods) void {
    if (keymap.get(key)) |action| {
        if (event == .press) {
            switch (action) {
                .button => |button| state.buttons.insert(button),
                .laser => |laser| {
                    const ptr, const value = mapLaserKey(laser);
                    ptr.* = value;
                },
            }
        } else if (event == .release) {
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
}

var active_joystick: ?glfw.Joystick = null;
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

pub fn updateJoystick() void {
    if (active_joystick) |joystick| {
        const buttons = joystick.getButtons() orelse return;
        var new_joystick_state = State{};

        for (std.enums.values(Button)) |button| {
            if (joystick_button_map.get(button)) |index| {
                if (index < buttons.len) {
                    const was_active = last_joystick_state.buttons.contains(button);
                    if (buttons[index] == 1) {
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

        const axes = joystick.getAxes() orelse return;
        if (config.joystick_vol_l) |index| {
            if (index < axes.len)
                new_joystick_state.lasers[0] = axes[index];
        }
        if (config.joystick_vol_r) |index| {
            if (index < axes.len)
                new_joystick_state.lasers[1] = axes[index];
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

fn joystickCallback(joystick: glfw.Joystick, event: glfw.Joystick.Event) void {
    if (event == .connected and active_joystick == null) {
        if (config.joystick_name) |joystick_name| {
            if (std.mem.eql(u8, joystick.getName().?, joystick_name)) {
                active_joystick = joystick;
            }
        }
    } else if (event == .disconnected) {
        if (active_joystick) |active| {
            if (active.jid == joystick.jid) {
                active_joystick = null;

                var iter = last_joystick_state.buttons.iterator();
                while (iter.next()) |button| {
                    state.buttons.remove(button);
                }

                for (&state.lasers, &joystick_laser_flags) |*out, *flag| {
                    if (flag.*) {
                        out.* = 0;
                        flag.* = false;
                    }
                }
            }
        }
    }
}
