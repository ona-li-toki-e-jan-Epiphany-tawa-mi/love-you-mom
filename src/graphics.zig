const std = @import("std");
const debug = std.debug;
const ttwhy = @import("ttwhy.zig");

const Tty = ttwhy.Tty;
const GraphicMode = ttwhy.GraphicMode;

////////////////////////////////////////////////////////////////////////////////
// Drawing                                                                    //
////////////////////////////////////////////////////////////////////////////////

pub fn draw(tty: *Tty, delta_time_s: f64, text: []const Shape) !void {
    const Statics = struct {
        var scene: u8 = 0;
    };

    debug.assert(delta_time_s > 0.0);

    try tty.resetGraphicModes();
    try tty.clear();

    switch (Statics.scene) {
        // Shutter opening up to show text.
        0 => {
            const SceneStatics = struct {
                var shutter_size: f32 = 1.0;
            };

            try tty.setGraphicModes(&.{.foreground_green});
            for (text) |letter| {
                try drawShape(tty, '#', letter);
            }

            if (SceneStatics.shutter_size > 0.0) {
                try tty.resetGraphicModes();
                try drawShutter(tty, SceneStatics.shutter_size);
                const shutter_speed = comptime 0.2;
                SceneStatics.shutter_size -=
                    shutter_speed * @as(f32, @floatCast(delta_time_s));
            } else {
                Statics.scene +|= 1;
            }
        },

        // Text blinks between green and bright green.
        1 => {
            const SceneStatics = struct {
                var toggle_time_s: f64 = 0.0;
                var toggle_cycles: u8 = 3;
            };

            if (1.0 < SceneStatics.toggle_time_s) {
                try tty.setGraphicModes(&.{.foreground_green});

                if (2.0 < SceneStatics.toggle_time_s) {
                    SceneStatics.toggle_time_s = 0.0;
                    SceneStatics.toggle_cycles -|= 1;
                }
            } else {
                try tty.setGraphicModes(&.{ .bold, .foreground_green });
            }
            for (text) |letter| {
                try drawShape(tty, '#', letter);
            }

            SceneStatics.toggle_time_s += delta_time_s;
            if (0 == SceneStatics.toggle_cycles) {
                Statics.scene +|= 1;
            }
        },

        // Text changes to a static red and cyan.
        2 => {
            try tty.setGraphicModes(&.{.background_red});
            try tty.clear();

            try tty.setGraphicModes(&.{ .bold, .foreground_cyan });
            for (text) |letter| {
                try drawShape(tty, '#', letter);
            }
        },

        else => unreachable,
    }
}

fn drawShutter(tty: *Tty, size: f32) !void {
    debug.assert(0.0 <= size and 1.0 >= size);
    const shutter_height: u16 = @intFromFloat(size * @as(f32, @floatFromInt(tty.height)));
    if (0 == shutter_height) return;

    try tty.home();
    try tty.resetGraphicModes();

    var y = shutter_height;
    while (true) {
        const bottom_offset = shutter_height -| y;
        switch (bottom_offset) {
            // Shutter bottom color.
            0, 2 => try tty.setGraphicModes(&.{ .bold, .background_yellow }),
            1 => try tty.setGraphicModes(&.{ .reset_bold_dim, .background_black }),
            // Shutter body color.
            else => try tty.setGraphicModes(&.{
                .reset_bold_dim,
                if (0 == y % 2) .background_white else .background_cyan,
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

    var last_point: ?Point = null;

    for (letter) |point| {
        if (null == last_point) {
            last_point = point;
            continue;
        }

        const width: f32 = @floatFromInt(tty.width);
        const x1: i32 = @intFromFloat(point[0] * width);
        const x2: i32 = @intFromFloat(last_point.?[0] * width);
        const height: f32 = @floatFromInt(tty.height);
        const y1: i32 = @intFromFloat(point[1] * height);
        const y2: i32 = @intFromFloat(last_point.?[1] * height);
        try drawLine(tty, character, x1, x2, y1, y2);

        last_point = point;
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

    var iterations = tty.width *| tty.height; // loop limit just-in-case.
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
    comptime letter_margin: f32,
    comptime text: []const u8,
) [text.len]Shape {
    debug.assert(0.0 < size);
    debug.assert(0.0 <= letter_margin);
    debug.assert(0 < text.len);

    var letters: [text.len]Shape = undefined;

    const letter_count: f32 = @floatFromInt(text.len);
    const letter_size = (size - letter_margin * (letter_count - 1)) / letter_count;
    var xOffset = 0.0;

    for (text, &letters) |character, *letter| {
        switch (character) {
            'a', 'A' => letter.* = letterA(x + xOffset, y, letter_size),
            'd', 'D' => letter.* = letterD(x + xOffset, y, letter_size),
            'e', 'E' => letter.* = letterE(x + xOffset, y, letter_size),
            'l', 'L' => letter.* = letterL(x + xOffset, y, letter_size),
            'm', 'M' => letter.* = letterM(x + xOffset, y, letter_size),
            'o', 'O' => letter.* = letterO(x + xOffset, y, letter_size),
            'u', 'U' => letter.* = letterU(x + xOffset, y, letter_size),
            'v', 'V' => letter.* = letterV(x + xOffset, y, letter_size),
            'y', 'Y' => letter.* = letterY(x + xOffset, y, letter_size),
            else => @compileError("Unhandled character: " ++ [1]u8{character}),
        }

        xOffset += letter_size + letter_margin;
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
