const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const vfs = @import("vfs.zig");
const config = @import("config.zig");
const input = @import("input.zig");
const renderer = @import("renderer.zig");
const text = @import("text.zig");
const ui = @import("ui.zig");
const audio = @import("audio.zig");
const db = @import("db.zig");
const Strings = @import("Strings.zig");

pub const State = struct {
    const Fn = *const fn () anyerror!void;

    init: Fn,
    deinit: Fn,
    enter: Fn,
    leave: Fn,
    update: Fn,
    draw3D: Fn,
    draw2D: Fn,

    fn empty() !void {}

    fn v(comptime namespace: type) State {
        var result: State = undefined;
        inline for (@typeInfo(State).Struct.fields) |field| {
            @field(result, field.name) = if (@hasDecl(namespace, field.name))
                @field(namespace, field.name)
            else
                empty;
        }
        return result;
    }

    const vtables = struct {
        pub const song_select = v(@import("state/song_select.zig"));
        pub const cache = v(@import("state/cache.zig"));
        pub const ingame = v(@import("state/ingame.zig"));
    };

    pub fn change(self: *State, comptime name: anytype) !void {
        try self.leave();
        _ = state_arena.reset(.retain_capacity);
        self.* = @field(vtables, @tagName(name));
        try self.enter();
    }
};

pub var state = State.vtables.cache;
pub var strings = &Strings.English;

pub const allocator = std.heap.c_allocator;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var state_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const temp_allocator = arena.allocator();
pub const state_allocator = state_arena.allocator();

pub var window: glfw.Window = undefined;

fn glfwError(_: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.scoped(.glfw).err("{s}", .{description});
}

pub fn main() !void {
    try vfs.init();

    glfw.setErrorCallback(glfwError);
    if (!glfw.init(.{})) return error.WindowCreation;
    defer glfw.terminate();

    window = glfw.Window.create(config.width, config.height, "Voltyx", null, null, .{
        .scale_to_monitor = true,
        .maximized = config.maximized,
        .samples = config.samples,
    }) orelse return error.WindowCreation;

    window.setInputMode(.cursor, .hidden);

    try input.init(window);
    try renderer.init();
    try text.init();
    try ui.init();
    try audio.init();
    try db.init();
    input.initJoystickLasers();

    inline for (@typeInfo(State.vtables).Struct.decls) |decl| {
        try @field(State.vtables, decl.name).init();
    }
    try state.enter();

    while (!window.shouldClose()) {
        _ = arena.reset(.retain_capacity);
        try state.update();
        try renderer.draw();
        glfw.pollEvents();
        input.updateJoystick();
    }

    try config.save();

    inline for (@typeInfo(State.vtables).Struct.decls) |decl| {
        try @field(State.vtables, decl.name).deinit();
    }
    db.deinit();
}

pub fn format(comptime fmt: []const u8, args: anytype) ![]u8 {
    return try std.fmt.allocPrint(temp_allocator, fmt, args);
}

extern fn MessageBoxW(hwnd: ?*anyopaque, text: [*:0]const u16, caption: [*:0]const u16, type: u32) callconv(std.os.windows.WINAPI) i32;
const MB_ICONERROR = 0x00000010;

pub fn messageBox(message: []const u8) !void {
    const title = "Voltyx";

    switch (builtin.os.tag) {
        .windows => {
            const wtitle = std.unicode.utf8ToUtf16LeStringLiteral(title);
            if (std.unicode.utf8ToUtf16LeWithNull(temp_allocator, message)) |wmessage| {
                _ = MessageBoxW(null, wmessage, wtitle, MB_ICONERROR);
            } else |_| {}
        },
        else => std.log.err("{s}", .{message}),
    }

    return error.MessageBoxShown;
}
