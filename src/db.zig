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
    var iter = try version_stmt.iter({});
    var current_version = (try iter.next()).?;

    if (current_version > migrations.len) {
        return game.messageBox(game.strings.error_save_version);
    }

    while (current_version < migrations.len) : (current_version += 1) {
        try exec(migrations[current_version]);
    }
}

pub fn exec(sql: [:0]const u8) !void {
    if (c.sqlite3_exec(db, sql, null, null, null) != c.SQLITE_OK) return error.Unexpected;
}

pub fn prepare(sql: [:0]const u8, comptime Params: type, comptime Row: type) !Statement(Params, Row) {
    var statement = Statement(Params, Row){};
    try statement.prepare(sql);
    return statement;
}

pub fn Statement(comptime Params: type, comptime Row: type) type {
    return struct {
        handle: *c.sqlite3_stmt = undefined,

        pub fn prepare(self: *@This(), sql: [:0]const u8) !void {
            var stmt: ?*c.sqlite3_stmt = undefined;
            if (c.sqlite3_prepare_v2(db, sql, @intCast(sql.len + 1), &stmt, null) != c.SQLITE_OK) return error.Unexpected;
            self.handle = stmt.?;
        }

        pub fn deinit(self: @This()) void {
            _ = c.sqlite3_finalize(self.handle);
        }

        pub fn iter(self: @This(), params: Params) !RowIterator {
            if (c.sqlite3_reset(self.handle) != c.SQLITE_OK) return error.Unexpected;

            var counter: u31 = 1;
            if (@typeInfo(Params) == .Struct) {
                inline for (std.meta.fields(Params)) |field| {
                    try self.bind(&counter, @field(params, field.name));
                }
            } else if (Params != void) {
                try self.bind(&counter, params);
            }

            return .{ .handle = self.handle };
        }

        pub fn exec(self: @This(), params: Params) !void {
            if (try (try self.iter(params)).next() != null) return error.Unexpected;
        }

        fn bind(self: @This(), counter: *u31, value: anytype) !void {
            switch (@typeInfo(@TypeOf(value))) {
                .Array => {
                    for (value) |element| {
                        try self.bind(counter, element);
                    }
                    return;
                },
                .Optional => {
                    if (value) |unwrapped| {
                        return self.bind(counter, unwrapped);
                    } else {
                        return self.bind(counter, null);
                    }
                },
                else => {},
            }

            const index = counter.*;
            counter.* += 1;

            const result = switch (@TypeOf(value)) {
                u8, i32 => c.sqlite3_bind_int(self.handle, index, value),
                u64, i64 => c.sqlite3_bind_int64(self.handle, index, @bitCast(value)),
                f32 => c.sqlite3_bind_double(self.handle, index, value),
                []const u8 => c.sqlite3_bind_blob(self.handle, index, value.ptr, @intCast(value.len), c.SQLITE_STATIC),
                @TypeOf(null) => c.sqlite3_bind_null(self.handle, index),
                else => @compileError("unhandled type: " ++ @typeName(@TypeOf(value))),
            };

            if (result != c.SQLITE_OK) return error.Unexpected;
        }

        const RowIterator = struct {
            handle: *c.sqlite3_stmt,

            pub fn next(self: @This()) !?Row {
                switch (c.sqlite3_step(self.handle)) {
                    c.SQLITE_ROW => {
                        var result: Row = undefined;
                        var counter: u31 = 0;
                        if (@typeInfo(Row) == .Struct) {
                            inline for (std.meta.fields(Row)) |field| {
                                @field(result, field.name) = try self.column(&counter, field.type);
                            }
                        } else {
                            result = try self.column(&counter, Row);
                        }
                        return result;
                    },
                    c.SQLITE_DONE => return null,
                    else => return error.Unexpected,
                }
            }

            fn column(self: @This(), counter: *u31, comptime T: type) !T {
                const index = counter.*;

                switch (@typeInfo(T)) {
                    .Array => |info| {
                        var result: T = undefined;
                        for (&result) |*element| {
                            element.* = try self.column(counter, info.child);
                        }
                        return result;
                    },
                    .Optional => |info| {
                        if (c.sqlite3_column_type(self.handle, index) != c.SQLITE_NULL) {
                            return try self.column(counter, info.child);
                        } else {
                            return null;
                        }
                    },
                    else => {},
                }

                counter.* += 1;

                if (T == []const u8) {
                    const blob: [*]const u8 = @ptrCast(c.sqlite3_column_blob(self.handle, index));
                    const bytes: u32 = @bitCast(c.sqlite3_column_bytes(self.handle, index));
                    return blob[0..bytes];
                }

                return switch (T) {
                    i32, u32 => @bitCast(c.sqlite3_column_int(self.handle, index)),
                    i64, u64 => @bitCast(c.sqlite3_column_int64(self.handle, index)),
                    f32 => @floatCast(c.sqlite3_column_double(self.handle, index)),
                    u8 => std.math.cast(T, c.sqlite3_column_int(self.handle, index)) orelse error.Overflow,
                    void => {},
                    else => @compileError("unhandled type: " ++ @typeName(T)),
                };
            }
        };
    };
}

pub fn lastRowId() i64 {
    return c.sqlite3_last_insert_rowid(db);
}
