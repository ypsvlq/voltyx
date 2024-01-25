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
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .windows) {
        if (optimize != .Debug) {
            exe.subsystem = .Windows;
        }
        exe.addWin32ResourceFile(.{ .file = .{ .path = "src/windows/resource.rc" } });
    }

    const dep_optimize = if (optimize == .Debug) .ReleaseFast else optimize;
    import(exe, "mach-glfw", .{ .target = target, .optimize = dep_optimize });
    import(exe, "mach-freetype", .{ .target = target, .optimize = dep_optimize, .enable_brotli = false });
    import(exe, "mach-sysaudio", .{ .target = target, .optimize = dep_optimize });
    import(exe, "mach-opus", .{ .target = target, .optimize = dep_optimize });
    import(exe, "zigimg", .{ .target = target, .optimize = dep_optimize });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
