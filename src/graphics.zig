const std = @import("std");
const debug = std.debug;
const ttwhy = @import("ttwhy.zig");

const Tty = ttwhy.Tty;
const GraphicMode = ttwhy.GraphicMode;

////////////////////////////////////////////////////////////////////////////////
// Drawing                                                                    //
////////////////////////////////////////////////////////////////////////////////

pub fn draw(tty: *Tty, deltaTime_s: f64, text: []const Shape) !void {
    const statics = struct {
        var scene: u8 = 0;
    };

    debug.assert(deltaTime_s > 0.0);

    try tty.resetGraphicModes();
    try tty.clear();

    switch (statics.scene) {
        // Shutter opening up to show text.
        0 => {
            const sceneStatics = struct {
                var shutterSize: f32 = 1.0;
            };

            try tty.setGraphicModes(&.{.FOREGROUND_GREEN});
            for (text) |letter| {
                try drawShape(tty, '#', letter);
            }

            if (sceneStatics.shutterSize > 0.0) {
                try tty.resetGraphicModes();
                try drawShutter(tty, sceneStatics.shutterSize);
                const shutterSpeed = comptime 0.2;
                sceneStatics.shutterSize -= shutterSpeed * @as(f32, @floatCast(deltaTime_s));
            } else {
                statics.scene +|= 1;
            }
        },

        // Text blinks between green and bright green.
        1 => {
            const sceneStatics = struct {
                var toggleTime_s: f64 = 0.0;
                var toggleCycles: u8 = 3;
            };

            if (1.0 < sceneStatics.toggleTime_s) {
                try tty.setGraphicModes(&.{.FOREGROUND_GREEN});

                if (2.0 < sceneStatics.toggleTime_s) {
                    sceneStatics.toggleTime_s = 0.0;
                    sceneStatics.toggleCycles -|= 1;
                }
            } else {
                try tty.setGraphicModes(&.{ .BOLD, .FOREGROUND_GREEN });
            }
            for (text) |letter| {
                try drawShape(tty, '#', letter);
            }

            sceneStatics.toggleTime_s += deltaTime_s;
            if (0 == sceneStatics.toggleCycles) {
                statics.scene +|= 1;
            }
        },

        // Text changes to a static red and cyan.
        2 => {
            try tty.setGraphicModes(&.{.BACKGROUND_RED});
            try tty.clear();

            try tty.setGraphicModes(&.{ .BOLD, .FOREGROUND_CYAN });
            for (text) |letter| {
                try drawShape(tty, '#', letter);
            }
        },

        else => unreachable,
    }
}

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
            0, 2 => try tty.setGraphicModes(&.{ .BOLD, .BACKGROUND_YELLOW }),
            1 => try tty.setGraphicModes(&.{ .RESET_BOLD_DIM, .BACKGROUND_BLACK }),
            // Shutter body color.
            else => try tty.setGraphicModes(&.{
                .RESET_BOLD_DIM,
                if (0 == y % 2) .BACKGROUND_WHITE else .BACKGROUND_CYAN,
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

////////////////////////////////////////////////////////////////////////////////
// Shapes                                                                     //
////////////////////////////////////////////////////////////////////////////////

pub const Point = [2]f32;
pub const Shape = []const Point;

pub fn line(
    comptime x: f32,
    comptime y: f32,
    comptime size: f32,
    comptime letterMargin: f32,
    comptime text: []const u8,
) [text.len]Shape {
    debug.assert(0.0 < size);
    debug.assert(0.0 <= letterMargin);
    debug.assert(0 < text.len);

    var letters: [text.len]Shape = undefined;

    const letterCount: f32 = @floatFromInt(text.len);
    const letterSize = (size - letterMargin * (letterCount - 1)) / letterCount;
    var xOffset = 0.0;

    for (text, &letters) |character, *letter| {
        switch (character) {
            'a', 'A' => letter.* = letterA(x + xOffset, y, letterSize),
            'd', 'D' => letter.* = letterD(x + xOffset, y, letterSize),
            'e', 'E' => letter.* = letterE(x + xOffset, y, letterSize),
            'l', 'L' => letter.* = letterL(x + xOffset, y, letterSize),
            'm', 'M' => letter.* = letterM(x + xOffset, y, letterSize),
            'o', 'O' => letter.* = letterO(x + xOffset, y, letterSize),
            'u', 'U' => letter.* = letterU(x + xOffset, y, letterSize),
            'v', 'V' => letter.* = letterV(x + xOffset, y, letterSize),
            'y', 'Y' => letter.* = letterY(x + xOffset, y, letterSize),
            else => @compileError("Unhandled character: " ++ [1]u8{character}),
        }

        xOffset += letterSize + letterMargin;
    }

    return letters;
}

fn letterA(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    debug.assert(0.0 < size);
    return &.{
        Point{ x, y + size },
        Point{ x + 0.5 * size, y },
        Point{ x + size, y + size },
        Point{ x + 0.75 * size, y + 0.825 * size },
        Point{ x + 0.25 * size, y + 0.825 * size },
    };
}
fn letterD(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    debug.assert(0.0 < size);
    return &.{
        Point{ x, y },
        Point{ x, y + size },
        Point{ x + size, y + 0.5 * size },
        Point{ x, y },
    };
}
fn letterE(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    debug.assert(0.0 < size);
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
    debug.assert(0.0 < size);
    return &.{
        Point{ x, y },
        Point{ x, y + size },
        Point{ x + size, y + size },
    };
}
fn letterM(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    debug.assert(0.0 < size);
    return &.{
        Point{ x, y + size },
        Point{ x, y },
        Point{ x + 0.5 * size, y + size },
        Point{ x + size, y },
        Point{ x + size, y + size },
    };
}
fn letterO(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    debug.assert(0.0 < size);
    return &.{
        Point{ x, y + 0.5 * size },
        Point{ x + 0.5 * size, y },
        Point{ x + size, y + 0.5 * size },
        Point{ x + 0.5 * size, y + size },
        Point{ x, y + 0.5 * size },
    };
}
fn letterU(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    debug.assert(0.0 < size);
    return &.{
        Point{ x, y },
        Point{ x, y + size },
        Point{ x + size, y + size },
        Point{ x + size, y },
    };
}
fn letterV(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    debug.assert(0.0 < size);
    return &.{
        Point{ x, y },
        Point{ x + 0.5 * size, y + size },
        Point{ x + size, y },
    };
}
fn letterY(comptime x: f32, comptime y: f32, comptime size: f32) Shape {
    debug.assert(0.0 < size);
    return &.{
        Point{ x, y },
        Point{ x + 0.5 * size, y + 0.5 * size },
        Point{ x + size, y },
        Point{ x, y + size },
    };
}
