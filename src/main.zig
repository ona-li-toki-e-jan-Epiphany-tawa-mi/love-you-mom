const std = @import("std");
const log = std.log;
const io = std.io;
const time = std.time;
const heap = std.heap;
const ttwhy = @import("ttwhy.zig");

const Tty = ttwhy.Tty;

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

    //const oldTermios = try configure(tty);
    //defer reset(tty, oldTermios) catch {};

    try tty.cursor(false);
    try tty.update(allocator);

    var colorIndex: usize = 0;
    while (true) {
        try tty.home();
        for (0..tty.height) |_| {
            try tty.color(ttwhy.foregrounds[colorIndex], ttwhy.backgrounds[colorIndex]);
            colorIndex += 1;
            if (colorIndex >= ttwhy.foregrounds.len) {
                colorIndex = 0;
            }

            for (0..tty.width) |_| {
                try tty.write(" ");
            }
        }
        try tty.update(allocator);

        time.sleep(250_000_000);
    }
}
