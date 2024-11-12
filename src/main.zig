const std = @import("std");
const log = std.log;
const io = std.io;
const time = std.time;
const heap = std.heap;
const debug = std.debug;
const ttwhy = @import("ttwhy.zig");

const Tty = ttwhy.Tty;
const Foreground = ttwhy.Foreground;
const Background = ttwhy.Background;

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

    try tty.defaultColor();
}

const Point = [2]f32;
const Shape = []const Point;

fn drawShape(tty: *Tty, letter: Shape) !void {
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

        // https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm#All_cases
        // We handle the absolute value manually here to avoid having to convert
        // to unsigned and back to signed numbers.
        const dx = blk: {
            const dx = x2 - x1;
            break :blk (if (dx < 0) -dx else dx);
        };
        const sx: i16 = if (x1 < x2) 1 else -1;
        var x = x1;
        const dy = blk: {
            const dy = y2 - y1;
            break :blk -(if (dy < 0) -dy else dy);
        };
        const sy: i16 = if (y1 < y2) 1 else -1;
        var y = y1;
        var err = dx + dy;
        while (true) {
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

fn letterE(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return ([_]Point{
        Point{ x, y },
        Point{ x + size, y },
        Point{ x + size, y + 0.5 * size },
        Point{ x, y + 0.5 * size },
        Point{ x, y },
        Point{ x, y + size },
        Point{ x + size, y + size },
    })[0..];
}
fn letterL(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return ([_]Point{
        Point{ x, y },
        Point{ x, y + size },
        Point{ x + size, y + size },
    })[0..];
}
fn letterM(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return ([_]Point{
        Point{ x, y + size },
        Point{ x, y },
        Point{ x + 0.5 * size, y + size },
        Point{ x + size, y },
        Point{ x + size, y + size },
    })[0..];
}
fn letterO(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return ([_]Point{
        Point{ x, y + 0.5 * size },
        Point{ x + 0.5 * size, y },
        Point{ x + size, y + 0.5 * size },
        Point{ x + 0.5 * size, y + size },
        Point{ x, y + 0.5 * size },
    })[0..];
}
fn letterU(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return ([_]Point{
        Point{ x, y },
        Point{ x, y + size },
        Point{ x + size, y + size },
        Point{ x + size, y },
    })[0..];
}
fn letterV(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return ([_]Point{
        Point{ x, y },
        Point{ x + 0.5 * size, y + size },
        Point{ x + size, y },
    })[0..];
}
fn letterY(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return ([_]Point{
        Point{ x, y },
        Point{ x + 0.5 * size, y + 0.5 * size },
        Point{ x + size, y },
        Point{ x, y + size },
    })[0..];
}

fn line(
    comptime x: f32,
    comptime y: f32,
    comptime size: f32,
    comptime letterMargin: f32,
    comptime text: []const u8,
) [text.len]Shape {
    var letters: [text.len]Shape = undefined;

    const letterCount: f32 = @floatFromInt(text.len);
    const letterSize = (size - letterMargin * (letterCount - 1)) / letterCount;
    var xOffset = 0.0;

    for (text, &letters) |character, *letter| {
        switch (character) {
            'e', 'E' => letter.* = letterE(x + xOffset, y, letterSize),
            'l', 'L' => letter.* = letterL(x + xOffset, y, letterSize),
            'm', 'M' => letter.* = letterM(x + xOffset, y, letterSize),
            'o', 'O' => letter.* = letterO(x + xOffset, y, letterSize),
            'u', 'U' => letter.* = letterU(x + xOffset, y, letterSize),
            'v', 'V' => letter.* = letterV(x + xOffset, y, letterSize),
            'y', 'Y' => letter.* = letterY(x + xOffset, y, letterSize),
            else => unreachable,
        }

        xOffset += letterSize + letterMargin;
    }

    return letters;
}

const loveYouMomText =
    line(0.125, 0.1, 0.75, 0.05, "love") ++
    line(0.125, 0.4, 0.75, 0.05, "you") ++
    line(0.125, 0.7, 0.75, 0.05, "mom");

// TODO undo changes to terminal on close.
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

        try tty.color(Foreground.GREEN, Background.BLACK);
        for (loveYouMomText) |letter| {
            try drawShape(&tty, letter);
        }
        if (shutterSize > 0.0) {
            try drawShutter(&tty, shutterSize, colorIndexOffset);
            colorIndexOffset +%= 11;
            shutterSize -= 0.1;
        }

        try tty.update();
        time.sleep(500_000_000);
    }
}
