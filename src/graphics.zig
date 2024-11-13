const std = @import("std");
const debug = std.debug;
const ttwhy = @import("ttwhy.zig");

const Tty = ttwhy.Tty;
const GraphicMode = ttwhy.GraphicMode;

////////////////////////////////////////////////////////////////////////////////
// Shapes                                                                     //
////////////////////////////////////////////////////////////////////////////////

const Point = [2]f32;
const Shape = []const Point;

fn letterE(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return &.{
        Point{ x, y },
        Point{ x + size, y },
        Point{ x + size, y + 0.5 * size },
        Point{ x, y + 0.5 * size },
        Point{ x, y },
        Point{ x, y + size },
        Point{ x + size, y + size },
    };
}
fn letterL(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return &.{
        Point{ x, y },
        Point{ x, y + size },
        Point{ x + size, y + size },
    };
}
fn letterM(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return &.{
        Point{ x, y + size },
        Point{ x, y },
        Point{ x + 0.5 * size, y + size },
        Point{ x + size, y },
        Point{ x + size, y + size },
    };
}
fn letterO(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return &.{
        Point{ x, y + 0.5 * size },
        Point{ x + 0.5 * size, y },
        Point{ x + size, y + 0.5 * size },
        Point{ x + 0.5 * size, y + size },
        Point{ x, y + 0.5 * size },
    };
}
fn letterU(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return &.{
        Point{ x, y },
        Point{ x, y + size },
        Point{ x + size, y + size },
        Point{ x + size, y },
    };
}
fn letterV(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return &.{
        Point{ x, y },
        Point{ x + 0.5 * size, y + size },
        Point{ x + size, y },
    };
}
fn letterY(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    return &.{
        Point{ x, y },
        Point{ x + 0.5 * size, y + 0.5 * size },
        Point{ x + size, y },
        Point{ x, y + size },
    };
}

// TODO Add assertions to line and letter functions that x, y, and size are within bounds.
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

////////////////////////////////////////////////////////////////////////////////
// Drawing                                                                    //
////////////////////////////////////////////////////////////////////////////////

fn drawShutter(tty: *Tty, size: f32) !void {
    debug.assert(0.0 <= size and 1.0 >= size);
    const shutterHeight: u16 = @intFromFloat(size * @as(f32, @floatFromInt(tty.height)));
    if (0 == shutterHeight) return;

    try tty.home();
    try tty.resetGraphicModes();

    var y = shutterHeight;
    while (true) {
        const bottomOffset = shutterHeight -| y;
        switch (bottomOffset) {
            // Shutter bottom color.
            0, 2 => try tty.setGraphicModes(&.{
                GraphicMode.BOLD,
                GraphicMode.BACKGROUND_YELLOW,
            }),
            1 => try tty.setGraphicModes(&.{
                GraphicMode.RESET_BOLD_DIM,
                GraphicMode.BACKGROUND_BLACK,
            }),
            // Shutter body color.
            else => try tty.setGraphicModes(&.{
                GraphicMode.RESET_BOLD_DIM,
                if (0 == y % 2)
                    GraphicMode.BACKGROUND_WHITE
                else
                    GraphicMode.BACKGROUND_CYAN,
            }),
        }

        try tty.goto(0, y);
        for (0..tty.width) |_| {
            try tty.write(" ");
        }

        if (0 == y) break;
        y -|= 1;
    }
}

// https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm#All_cases
fn drawLine(tty: *Tty, character: u8, x1: i32, x2: i32, y1: i32, y2: i32) !void {
    // We handle the absolute value here ourselves, instead of with @abs, to
    // avoid having to convert to unsigned and back to signed numbers.
    const dx = blk: {
        const dx = x2 - x1;
        break :blk (if (dx < 0) -dx else dx);
    };
    const dy = blk: {
        const dy = y2 - y1;
        break :blk -(if (dy < 0) -dy else dy);
    };

    const sx: i32 = if (x1 < x2) 1 else -1;
    const sy: i32 = if (y1 < y2) 1 else -1;
    var err = dx + dy;

    var iterations = tty.width *| tty.height; // loop limit just in case.
    var x = x1;
    var y = y1;
    while (0 < iterations) {
        if (0 <= x and x < tty.width and 0 <= y and y < tty.height) {
            try tty.goto(@intCast(x), @intCast(y));
            try tty.write(&.{character});
        }

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

        iterations -|= 1;
    }
}

fn drawShape(tty: *Tty, character: u8, letter: Shape) !void {
    debug.assert(1 < letter.len);

    var lastPoint: ?Point = null;

    for (letter) |point| {
        if (null == lastPoint) {
            lastPoint = point;
            continue;
        }

        const width: f32 = @floatFromInt(tty.width);
        const x1: i32 = @intFromFloat(point[0] * width);
        const x2: i32 = @intFromFloat(lastPoint.?[0] * width);
        const height: f32 = @floatFromInt(tty.height);
        const y1: i32 = @intFromFloat(point[1] * height);
        const y2: i32 = @intFromFloat(lastPoint.?[1] * height);
        try drawLine(tty, character, x1, x2, y1, y2);

        lastPoint = point;
    }
}

const loveYouMomText =
    line(0.125, 0.1, 0.75, 0.05, "love") ++
    line(0.125, 0.4, 0.75, 0.05, "you") ++
    line(0.125, 0.7, 0.75, 0.05, "mom");

pub fn draw(tty: *Tty, deltaTime_s: f64) !void {
    debug.assert(deltaTime_s > 0.0);

    const static = struct {
        var scene: u8 = 0;
        // Scene 0.
        var shutterSize: f32 = 1.0;
        // Scene 1.
        var textToggleTime_s: f64 = 0.0;
        var textToggleCycles: u8 = 3;
        // Scene 2.
        var scene2Time_s: f64 = 3.0;
    };

    try tty.resetGraphicModes();
    try tty.clear();

    try switch (static.scene) {
        // Shutter opening up to show text.
        0 => {
            try tty.setGraphicModes(&.{GraphicMode.FOREGROUND_GREEN});
            for (loveYouMomText) |letter| {
                try drawShape(tty, '#', letter);
            }

            if (static.shutterSize > 0.0) {
                try tty.resetGraphicModes();
                try drawShutter(tty, static.shutterSize);
                const shutterSpeed = comptime 0.2;
                static.shutterSize -= shutterSpeed * @as(f32, @floatCast(deltaTime_s));
            } else {
                static.scene +|= 1;
            }
        },

        // Text blinks between green and bright green.
        1 => {
            if (1.0 < static.textToggleTime_s) {
                try tty.setGraphicModes(&.{GraphicMode.FOREGROUND_GREEN});

                if (2.0 < static.textToggleTime_s) {
                    static.textToggleTime_s = 0.0;
                    static.textToggleCycles -|= 1;
                }
            } else {
                try tty.setGraphicModes(&.{
                    GraphicMode.BOLD,
                    GraphicMode.FOREGROUND_GREEN,
                });
            }
            for (loveYouMomText) |letter| {
                try drawShape(tty, '#', letter);
            }

            static.textToggleTime_s += deltaTime_s;
            if (0 == static.textToggleCycles) {
                static.scene +|= 1;
            }
        },

        // Text changes to a static red and cyan.
        2 => {
            try tty.setGraphicModes(&.{GraphicMode.BACKGROUND_RED});
            try tty.clear();

            try tty.setGraphicModes(&.{ GraphicMode.BOLD, GraphicMode.FOREGROUND_CYAN });
            for (loveYouMomText) |letter| {
                try drawShape(tty, '#', letter);
            }

            static.scene2Time_s -= deltaTime_s;
            if (0.0 >= static.scene2Time_s) {
                static.scene +|= 1;
            }
        },

        else => error.EndOfPlay,
    };
}
