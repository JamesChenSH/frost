const version = @import("builtin").zig_version;
const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("fdb.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const exe = b.addExecutable(.{
        .name = "fdb",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);
    exe.linkLibC();

    exe.linkSystemLibrary("fdb");
    exe.addIncludePath(b.path("/usr/include/"));
    exe.addLibraryPath(b.path("/usr/bin/foundationdb"));
}
