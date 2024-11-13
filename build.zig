//! This file is part of love-you-mom.
//!
//! Copyright (c) 2024 ona-li-toki-e-jan-Epiphany-tawa-mi
//!
//! love-you-mom is free software: you can redistribute it and/or modify it
//! under the terms of the GNU General Public License as published by the Free
//! Software Foundation, either version 3 of the License, or (at your option)
//! any later version.
//!
//! love-you-mom is distributed in the hope that it will be useful, but WITHOUT
//! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//! FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//! more details.
//!
//! You should have received a copy of the GNU General Public License along with
//! love-you-mom. If not, see <https://www.gnu.org/licenses/>.

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
