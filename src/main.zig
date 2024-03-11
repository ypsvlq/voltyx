const std = @import("std");
const builtin = @import("builtin");
const game = @import("game.zig");

extern fn AttachConsole(u32) callconv(std.os.windows.WINAPI) c_int;
const ATTACH_PARENT_PROCESS = 0xFFFFFFFF;

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        _ = AttachConsole(ATTACH_PARENT_PROCESS);
    }

    game.main() catch |err| {
        if (builtin.mode != .Debug and err != error.MessageBoxShown) {
            game.messageBox(game.strings.error_unhandled) catch {};
        }

        return err;
    };
}
