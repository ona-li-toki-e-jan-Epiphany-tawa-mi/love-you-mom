const std = @import("std");
const log = std.log;
const io = std.io;
const time = std.time;
const fs = std.fs;
const ttwhy = @import("ttwhy.zig");
const graphics = @import("graphics.zig");

const Tty = ttwhy.Tty;
const Timer = time.Timer;

const nanosecondsPerSecond = 1_000_000_000;
const fps = 15;
const nanosecondsPerFrame: u64 = nanosecondsPerSecond / fps;

fn run(tty: *Tty) !void {
    try tty.cursor(false);
    defer tty.cursor(true) catch {};

    var timer = try Timer.start();
    while (true) {
        const deltaTime_ns = timer.lap();
        if (nanosecondsPerFrame > deltaTime_ns) {
            time.sleep(nanosecondsPerFrame - deltaTime_ns);
        }

        const deltaTime_s = @as(f64, @floatFromInt(deltaTime_ns)) / nanosecondsPerSecond;
        try graphics.draw(tty, deltaTime_s);
        try tty.update();

        // Exits if any key is pressed.
        var buffer: [1]u8 = undefined;
        const bytesRead = try tty.read(&buffer);
        if (0 != bytesRead) break;
    }
}

// TODO added comand line options for saying love you dad.
// TODO document functions.
pub fn main() !void {
    const ttyFile = fs.cwd().openFile("/dev/tty", .{ .mode = .read_write }) catch |err| {
        log.err("Unable to open /dev/tty. You need to run this program in a terminal", .{});
        return err;
    };
    defer ttyFile.close();

    var tty = Tty.init(ttyFile) catch |err| switch (err) {
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

    try run(&tty);
}
