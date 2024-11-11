const std = @import("std");
const log = std.log;
const io = std.io;
const time = std.time;
const heap = std.heap;
const debug = std.debug;
const ttwhy = @import("ttwhy.zig");

const Tty = ttwhy.Tty;

fn drawShutter(tty: *Tty, size: f32, colorIndexOffset: usize) !void {
    comptime {
        std.debug.assert(ttwhy.foregrounds.len == ttwhy.backgrounds.len);
        std.debug.assert(0 < ttwhy.foregrounds.len);
    }
    debug.assert(0.0 <= size and 1.0 >= size);

    const shutterHeight: usize = @intFromFloat(size * @as(f32, @floatFromInt(tty.height)));
    var colorIndex: usize = colorIndexOffset;

    try tty.home();
    for (0..shutterHeight) |_| {
        colorIndex %= ttwhy.foregrounds.len;
        try tty.color(ttwhy.foregrounds[colorIndex], ttwhy.backgrounds[colorIndex]);
        colorIndex += 1;

        for (0..tty.width) |_| {
            try tty.write(" ");
        }
    }
}

pub fn main() !void {
    const allocator = heap.c_allocator;
    const stdin = io.getStdIn();

    var tty = Tty.init(stdin, allocator) catch |err| switch (err) {
        ttwhy.Error.NotATty => {
            log.err("stdin is not a tty! You need to use this program with a terminal emulator!", .{});
            return err;
        },
        else => |leftover_err| return leftover_err,
    };

    try tty.cursor(false);
    try tty.update();

    var colorIndexOffset: usize = 0;
    var shutterSize: f32 = 1.0;
    while (true) {

        try drawShutter(&tty, shutterSize, colorIndexOffset);
        colorIndexOffset +%= 1;
        shutterSize -= 0.025;
        if (shutterSize < 0.0) {
            shutterSize = 0;
        }

        try tty.update();
        time.sleep(500_000_000);
    }
}
