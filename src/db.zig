const std = @import("std");
const game = @import("game.zig");
const vfs = @import("vfs.zig");
const c = @cImport(@cInclude("sqlite3.h"));

var db: ?*c.sqlite3 = null;

fn logCallback(_: ?*anyopaque, _: c_int, msg: [*:0]const u8) callconv(.C) void {
    std.log.scoped(.sqlite).err("{s}", .{msg});
}

pub fn init() !void {
    _ = c.sqlite3_config(c.SQLITE_CONFIG_LOG, logCallback, @as(?*anyopaque, null));
    if (c.sqlite3_initialize() != c.SQLITE_OK) return error.Unexpected;

    const path = try vfs.absolutePath("save.db");
    if (c.sqlite3_open(path, &db) != c.SQLITE_OK) return error.Unexpected;

    comptime var migrations: [1][:0]const u8 = undefined;
    comptime for (&migrations, 1..) |*migration, i| {
        const name = std.fmt.comptimePrint("sql/{}.sql", .{i});
        migration.* = std.fmt.comptimePrint(
            \\BEGIN;
            \\{s}
            \\PRAGMA user_version={};
            \\COMMIT
        , .{ @embedFile(name), i });
    };

    const version_stmt = try prepare("PRAGMA user_version", void, u32);
    defer version_stmt.deinit();
    var iter = try version_stmt.exec({});
    var current_version = (try iter.next()).?;

    if (current_version > migrations.len) {
        return error.UnsupportedSaveVersion;
    }

    while (current_version < migrations.len) {
        if (c.sqlite3_exec(db, migrations[current_version], null, null, null) != c.SQLITE_OK) return error.Unexpected;
        current_version += 1;
    }
}

pub fn prepare(sql: [:0]const u8, comptime Params: type, comptime Row: type) !Statement(Params, Row) {
    var stmt: ?*c.sqlite3_stmt = undefined;
    if (c.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != c.SQLITE_OK) return error.Unexpected;
    return .{ .handle = stmt.? };
}

fn Statement(comptime Params: type, comptime Row: type) type {
    return struct {
        handle: *c.sqlite3_stmt,

        const RowIterator = struct {
            handle: *c.sqlite3_stmt,

            fn unpack(self: @This(), comptime T: type, ptr: *T, n: u31) !void {
                if (T == []const u8) {
                    const blob: [*]const u8 = @ptrCast(c.sqlite3_column_blob(self.handle, n));
                    const bytes: u32 = @bitCast(c.sqlite3_column_bytes(self.handle, n));
                    ptr.* = blob[0..bytes];
                    return;
                }

                ptr.* = switch (T) {
                    i32 => c.sqlite3_column_int(self.handle, n),
                    u32 => @bitCast(c.sqlite3_column_int(self.handle, n)),
                    i64 => c.sqlite3_column_int64(self.handle, n),
                    u64 => @bitCast(c.sqlite3_column_int64(self.handle, n)),
                    else => unreachable,
                };
            }

            pub fn next(self: @This()) !?Row {
                switch (c.sqlite3_step(self.handle)) {
                    c.SQLITE_ROW => {
                        var result: Row = undefined;
                        if (@typeInfo(Row) == .Struct) {
                            inline for (std.meta.fields(Row), 0..) |field, n| {
                                try self.unpack(field.type, &@field(result, field.name), n);
                            }
                        } else {
                            try self.unpack(Row, &result, 0);
                        }
                        return result;
                    },
                    c.SQLITE_DONE => return null,
                    else => return error.Unexpected,
                }
            }
        };

        pub fn exec(self: @This(), params: Params) !RowIterator {
            if (c.sqlite3_reset(self.handle) != c.SQLITE_OK) return error.Unexpected;
            _ = params;
            return .{ .handle = self.handle };
        }

        pub fn deinit(self: @This()) void {
            _ = c.sqlite3_finalize(self.handle);
        }
    };
}
