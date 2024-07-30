const std = @import("std");

fn import(exe: *std.Build.Step.Compile, name: []const u8, args: anytype) void {
    const dep = exe.step.owner.dependency(name, args);
    exe.root_module.addImport(name, dep.module(name));
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "voltyx",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .win32_manifest = b.path("src/windows/app.manifest"),
    });

    exe.subsystem = .Windows;
    exe.addWin32ResourceFile(.{ .file = b.path("src/windows/resource.rc") });

    const always_release = if (optimize == .Debug) .ReleaseFast else optimize;
    import(exe, "wio", .{ .target = target, .optimize = optimize, .win32_manifest = false });
    import(exe, "mach", .{ .target = target, .optimize = optimize, .sysaudio = true });
    import(exe, "mach-freetype", .{ .target = target, .optimize = optimize, .enable_brotli = false });
    import(exe, "mach-opus", .{ .target = target, .optimize = always_release });
    import(exe, "zigimg", .{ .target = target, .optimize = optimize });
    import(exe, "Ini", .{ .target = target, .optimize = optimize });

    var sqlite_flags = std.ArrayList([]const u8).init(b.allocator);
    sqlite_flags.appendSlice(&.{
        "-DHAVE_ISNAN",
        "-DSQLITE_DEFAULT_FOREIGN_KEYS=1",
        "-DSQLITE_DEFAULT_MEMSTATUS=0",
        "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
        "-DSQLITE_DQS=0",
        "-DSQLITE_LIKE_DOESNT_MATCH_BLOBS",
        "-DSQLITE_MAX_EXPR_DEPTH=0",
        "-DSQLITE_THREADSAFE=0",
        "-DSQLITE_USE_ALLOCA",
        "-DSQLITE_OMIT_AUTOINIT",
        "-DSQLITE_OMIT_DECLTYPE",
        "-DSQLITE_OMIT_DEPRECATED",
        "-DSQLITE_OMIT_JSON",
        "-DSQLITE_OMIT_PROGRESS_CALLBACK",
        "-DSQLITE_OMIT_SHARED_CACHE",
    }) catch unreachable;
    sqlite_flags.appendSlice(switch (exe.rootModuleTarget().os.tag) {
        .linux => &.{ "-DHAVE_MALLOC_H", "-DHAVE_MALLOC_USABLE_SIZE", "-DHAVE_STRCHRNUL" },
        .windows => &.{ "-DHAVE_MALLOC_H", "-DHAVE_MALLOC_USABLE_SIZE", "-Dmalloc_usable_size=_msize" },
        else => &.{},
    }) catch unreachable;

    const sqlite = b.dependency("sqlite", .{});
    exe.addIncludePath(sqlite.path("."));
    exe.addCSourceFile(.{ .file = sqlite.path("sqlite3.c"), .flags = sqlite_flags.items });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
