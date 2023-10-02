bytes: []const u8,
section: []const u8 = "",
line: usize = 0,

const std = @import("std");
const Ini = @This();

pub const Entry = struct {
    key: []const u8,
    value: []const u8,
};

pub const ParseError = error{
    ExpectedEquals,
    ExpectedCloseBracket,
    ExpectedNewline,
};

pub fn next(self: *Ini) ParseError!?Entry {
    self.line += 1;

    const whitespace = " \t\r";
    const bytes = std.mem.trimLeft(u8, self.bytes, whitespace);
    if (bytes.len == 0) {
        return null;
    }

    const newline = std.mem.indexOfScalar(u8, bytes, '\n') orelse bytes.len;
    self.bytes = bytes[@min(newline + 1, bytes.len)..];

    if (bytes[0] == '\n' or bytes[0] == ';') {
        return self.next();
    }

    if (bytes[0] == '[') {
        const end = std.mem.lastIndexOfScalar(u8, bytes[0..newline], ']') orelse return error.ExpectedCloseBracket;
        if (std.mem.indexOfNone(u8, bytes[end + 1 .. newline], whitespace)) |_| {
            return error.ExpectedNewline;
        }
        self.section = std.mem.trim(u8, bytes[1..end], whitespace);
        return self.next();
    }

    if (std.mem.indexOfScalar(u8, bytes[0..newline], '=')) |equals| {
        return .{
            .key = std.mem.trim(u8, bytes[0..equals], whitespace),
            .value = std.mem.trim(u8, bytes[equals + 1 .. newline], whitespace),
        };
    }

    return error.ExpectedEquals;
}
