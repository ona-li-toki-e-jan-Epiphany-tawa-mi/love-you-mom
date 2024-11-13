const std = @import("std");
const log = std.log;
const io = std.io;
const time = std.time;
const ttwhy = @import("ttwhy.zig");
const graphics = @import("graphics.zig");

const Tty = ttwhy.Tty;

const Timer = time.Timer;
const nanosecondsPerSecond = 1_000_000_000;

// TODO added comand line options for saying love you dad.
// TODO document functions.
// TODO exit on keypress.
pub fn main() !void {
    const fps = comptime 15;
    const nanosecondsPerFrame: u64 = comptime nanosecondsPerSecond / fps;

    const stdin = io.getStdIn();
    var tty = Tty.init(stdin) catch |err| switch (err) {
        ttwhy.Error.NotATty => {
            log.err(
                "stdin is not a tty! You need to use this program with a terminal emulator",
                .{},
            );
            return err;
        },
        else => |leftover_err| return leftover_err,
    };

    try tty.cursor(false);

    var timer = try Timer.start();
    while (true) {
        const deltaTime_ns = timer.lap();
        if (nanosecondsPerFrame > deltaTime_ns) {
            time.sleep(nanosecondsPerFrame - deltaTime_ns);
        }

        const deltaTime_s = @as(f64, @floatFromInt(deltaTime_ns)) / nanosecondsPerSecond;
        graphics.draw(&tty, deltaTime_s) catch |err| switch (err) {
            error.EndOfPlay => break,
            else => |leftover_err| return leftover_err,
        };
        try tty.update();
    }

    try tty.cursor(true);
    try tty.resetGraphicModes();
    try tty.clear();
    try tty.home();
    try tty.update();
}
