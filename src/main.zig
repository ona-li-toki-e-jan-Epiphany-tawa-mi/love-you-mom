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

const Point = [2]f32;

fn drawShape(tty: *Tty, letter: []const Point) !void {
    debug.assert(1 < letter.len);

    var lastPoint: ?Point = null;

    for (letter) |point| {
        if (null == lastPoint) {
            lastPoint = point;
            continue;
        }

        const width: f32 = @floatFromInt(tty.width);
        const height: f32 = @floatFromInt(tty.height);
        const x1: i16 = @intFromFloat(point[0] * width);
        const y1: i16 = @intFromFloat(point[1] * height);
        const x2: i16 = @intFromFloat(lastPoint.?[0] * width);
        const y2: i16 = @intFromFloat(lastPoint.?[1] * height);

        // TODO: this algo ends up in an infinite loop, hence the interation limit.
        // please fix.
        var iterations: u8 = 100;
        // https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm#All_cases
        const dx = @as(i32, @abs(x2 - x1));
        const sx: i16 = if (x1 < x2) 1 else -1;
        var x = x1;
        const dy = -@as(i32, @abs(y2 - y1));
        const sy: i16 = if (y1 < y2) 1 else -1;
        var y = y1;
        var err = dx + dy;
        while (true) {
            if (iterations == 0) break;
            iterations -|= 1;
            try tty.goto(@abs(x), @abs(y));
            try tty.write("#");
            if (x == x2 and y == y2) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                x += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y += sy;
            }
        }

        lastPoint = point;
    }
}

// TODO: make text. It's just a square right now.
const loveYouMomText = [_][]const Point{
    ([_]Point{
        Point{ 0.25, 0.25 },
        Point{ 0.75, 0.25 },
        Point{ 0.75, 0.75 },
        Point{ 0.25, 0.75 },
        Point{ 0.25, 0.25 },
    })[0..],
};

pub fn main() !void {
    const allocator = heap.c_allocator;
    const stdin = io.getStdIn();

    var tty = Tty.init(stdin, allocator) catch |err| switch (err) {
        ttwhy.Error.NotATty => {
            log.err("stdin is not a tty! You need to use this program with a terminal emulator", .{});
            return err;
        },
        ttwhy.Error.UnknownSize => {
            log.err("Unable to get terminal size", .{});
            return err;
        },
        else => |leftover_err| return leftover_err,
    };

    try tty.cursor(false);

    var colorIndexOffset: usize = 0;
    var shutterSize: f32 = 1.0;
    while (true) {
        try tty.clear();

        for (loveYouMomText) |letter| {
            try drawShape(&tty, letter);
        }
        //try drawShutter(&tty, shutterSize, colorIndexOffset);
        colorIndexOffset +%= 1;
        shutterSize -= 0.025;
        if (shutterSize < 0.0) {
            shutterSize = 0;
        }

        try tty.update();
        time.sleep(500_000_000);
    }
}
