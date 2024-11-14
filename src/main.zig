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
//! ----------------------------------------------------------------------------
//! Tells your mom (or dad) you love them.

const std = @import("std");
const log = std.log;
const io = std.io;
const time = std.time;
const fs = std.fs;
const process = std.process;
const mem = std.mem;
const ttwhy = @import("ttwhy.zig");
const graphics = @import("graphics.zig");

const Tty = ttwhy.Tty;
const Timer = time.Timer;
const ArgIterator = process.ArgIterator;
const File = fs.File;
const BufferedFileWriter = io.BufferedWriter(4096, File.Writer);
const Shape = graphics.Shape;

fn help(stdout: *BufferedFileWriter, parsed_args: ParsedArgs) !void {
    const writer = stdout.writer();
    try writer.print(
        \\Usages:
        \\  {s} [OPTIONS...]
        \\
        \\Tells your mom (or dad) that you love them.
        \\
        \\Press ANY KEY to exit.
        \\Requires terminal.
        \\
        \\Options:
        \\  -h, --help            Displays this help text and exits.
        \\  -v, --version         Displays version and license information and
        \\                        exits.
        \\  -d, --love-you-dad    Tell your dad that you love him.
        \\
    , .{parsed_args.program_name});
    try stdout.flush();
}

fn version(stdout: *BufferedFileWriter) !void {
    const writer = stdout.writer();
    try writer.print(
        \\love-you-mom 0.1.0
        \\
        \\Copyright (c) 2024 ona-li-toki-e-jan-Epiphany-tawa-mi
        \\
        \\love-you-mom is free software: you can redistribute it and/or modify it
        \\under the terms of the GNU General Public License as published by the Free
        \\Software Foundation, either version 3 of the License, or (at your option)
        \\any later version.
        \\
        \\love-you-mom is distributed in the hope that it will be useful, but WITHOUT
        \\ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
        \\FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
        \\more details.
        \\
        \\You should have received a copy of the GNU General Public License along with
        \\love-you-mom. If not, see <https://www.gnu.org/licenses/>.
        \\
    , .{});
    try stdout.flush();
}

const love_you_text =
    graphics.line(0.125, 0.1, 0.75, 0.05, "love") ++
    graphics.line(0.125, 0.4, 0.75, 0.05, "you");
const love_you_mom_text = love_you_text ++ graphics.line(0.125, 0.7, 0.75, 0.05, "mom");
const love_you_dad_text = love_you_text ++ graphics.line(0.125, 0.7, 0.75, 0.05, "dad");

pub fn main() !void {
    var stdout = BufferedFileWriter{ .unbuffered_writer = io.getStdOut().writer() };
    var text = love_you_mom_text;

    var args = process.args();
    const parsed_args = try parseArgs(&args);
    if (parsed_args.display_help) {
        try help(&stdout, parsed_args);
        return;
    }
    if (parsed_args.display_version) {
        try version(&stdout);
        return;
    }
    if (parsed_args.love_you_dad) {
        text = love_you_dad_text;
    }

    const tty_file = fs.cwd().openFile("/dev/tty", .{ .mode = .read_write }) catch |err| {
        log.err("Unable to open /dev/tty. You need to run this program in a terminal", .{});
        return err;
    };
    defer tty_file.close();

    var tty = Tty.init(tty_file) catch |err| switch (err) {
        error.NotATty => {
            log.err(
                "/dev/tty is not a tty! The sky is falling, Chicken Little!",
                .{},
            );
            return err;
        },
        else => |leftover_err| return leftover_err,
    };
    try tty.save();
    defer tty.restore() catch {};
    try tty.uncook();
    defer tty.cook() catch {};

    try run(&tty, &text);
}

/// Drives the animation.
/// Handles the timing for and calls to fn graphics.draw.
/// text - the text to display throughout the animation.
fn run(tty: *Tty, text: []const Shape) !void {
    const nanoseconds_per_second = comptime 1_000_000_000;
    const fps = comptime 15;
    const nanoseconds_per_frame: u64 = comptime nanoseconds_per_second / fps;

    try tty.cursor(false);
    defer tty.cursor(true) catch {};

    var timer = try Timer.start();
    while (true) {
        const delta_time_ns = timer.lap();
        if (nanoseconds_per_frame > delta_time_ns) {
            time.sleep(nanoseconds_per_frame - delta_time_ns);
        }

        const delta_time_s =
            @as(f64, @floatFromInt(delta_time_ns)) / nanoseconds_per_second;
        try graphics.draw(tty, delta_time_s, text);
        try tty.update();

        // Exits if any key is pressed.
        var buffer: [1]u8 = undefined;
        const bytes_read = try tty.read(&buffer);
        if (0 != bytes_read) break;
    }
}

////////////////////////////////////////////////////////////////////////////////
// Arugment Parsing                                                           //
////////////////////////////////////////////////////////////////////////////////

const ParsedArgs = struct {
    program_name: []const u8 = undefined,
    /// Whether to display help text and exit.
    display_help: bool = false,
    /// Whether to display version text and exit.
    display_version: bool = false,
    /// Whether to display "love you dad" instead of "love you mom."
    love_you_dad: bool = false,
};

fn parseArgs(args: *ArgIterator) !ParsedArgs {
    var parsed_args: ParsedArgs = .{};

    parsed_args.program_name = args.next().?;

    while (args.next()) |arg| parsingLoop: {
        if (2 <= arg.len and '-' == arg[0] and '-' != arg[1]) {
            var first = true;
            for (arg) |shortOption| {
                if (first) {
                    first = false;
                    continue;
                }
                const should_end_parsing = try parseShortOption(&parsed_args, shortOption);
                if (should_end_parsing) break :parsingLoop;
            }
        } else if (mem.eql(u8, "--help", arg)) {
            parsed_args.display_help = true;
            break :parsingLoop;
        } else if (mem.eql(u8, "--version", arg)) {
            parsed_args.display_version = true;
            break :parsingLoop;
        } else if (mem.eql(u8, "--love-you-dad", arg)) {
            parsed_args.love_you_dad = true;
        } else {
            log.err("Unknown command line option '{s}'", .{arg});
            return error.UnknownOption;
        }
    }

    return parsed_args;
}

fn parseShortOption(parsed_args: *ParsedArgs, option: u8) !bool {
    switch (option) {
        'h' => {
            parsed_args.display_help = true;
            return true;
        },
        'v' => {
            parsed_args.display_version = true;
            return true;
        },
        'd' => parsed_args.love_you_dad = true,

        else => {
            log.err("Unknown command line option '-{c}'", .{option});
            return error.UnknownOption;
        },
    }

    return false;
}
