const std = @import("std");

const Build = std.Build;

pub fn build(b: *Build) void {
    // Default build options.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main program.
    const exe = b.addExecutable(.{
        .name = "love-you-mom",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    b.installArtifact(exe);

    // Run program command.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        // This allows the user to pass arguments to the application in the build
        // command itself, like this: `zig build run -- arg1 arg2 etc`
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Tell your mom you love her");
    run_step.dependOn(&run_cmd.step);
}
