const std = @import("std");
const fs = std.fs;
const posix = std.posix;
const log = std.log;
const io = std.io;
const time = std.time;
const c = std.c;
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const process = std.process;

const Allocator = mem.Allocator;
const File = fs.File;

const TtyError = error{
    NotATty,
    UnknownSize,
    WriteFail,
};

const TtyWriter = io.BufferedWriter(4096, File.Writer);

inline fn ttyWriter(file: File) TtyWriter {
    return .{ .unbuffered_writer = file.writer() };
}

const Foreground = enum(u8) {
    BLACK = 30,
    RED = 31,
    GREEN = 32,
    YELLOW = 33,
    BLUE = 34,
    MAGENTA = 35,
    CYAN = 36,
    WHITE = 37,
};

const Background = enum(u8) {
    BLACK = 40,
    RED = 41,
    GREEN = 42,
    YELLOW = 43,
    BLUE = 44,
    MAGENTA = 45,
    CYAN = 46,
    WHITE = 47,
};

fn arrayFromEnum(comptime E: type) [@typeInfo(E).Enum.fields.len]E {
    const fields = @typeInfo(E).Enum.fields;
    var array: [fields.len]E = undefined;
    for (fields, &array) |field, *element| {
        element.* = @enumFromInt(field.value);
    }
    return array;
}

const Tty = struct {
    file: File,
    writer: TtyWriter,
    width: usize,
    height: usize,

    fn init(file: File, allocator: Allocator) TtyError!Tty {
        var tty = Tty{
            .file = file,
            .writer = ttyWriter(file),
            .width = undefined,
            .height = undefined,
        };

        if (!posix.isatty(file.handle)) {
            return TtyError.NotATty;
        }
        try tty.update(allocator);

        return tty;
    }

    fn update(self: *Tty, allocator: Allocator) TtyError!void {
        self.writer.flush() catch return TtyError.WriteFail;

        getSize: {
            // First try ioctl.
            {
                var winsize = mem.zeroes(posix.winsize);
                if (-1 != c.ioctl(self.file.handle, posix.T.IOCGWINSZ, &winsize)) {
                    self.width = winsize.ws_col;
                    self.height = winsize.ws_row;
                    break :getSize;
                }
            }
            // Else try COLUMNS and LINES environment variables.
            getEnv: {
                var env = process.getEnvMap(allocator) catch break :getEnv;
                defer env.deinit();
                const width = env.get("COLUMNS") orelse break :getEnv;
                const height = env.get("LINES") orelse break :getEnv;
                self.width = fmt.parseInt(usize, width, 10) catch break :getEnv;
                self.height = fmt.parseInt(usize, height, 10) catch break :getEnv;
                break :getSize;
            }
            // Else error.
            return TtyError.UnknownSize;
        }
    }

    inline fn write(self: *Tty, bytes: []const u8) TtyError!void {
        self.writer.writer().writeAll(bytes) catch return TtyError.WriteFail;
    }

    inline fn writeFmt(self: *Tty, comptime format: []const u8, args: anytype) TtyError!void {
        fmt.format(self.writer.writer(), format, args) catch return TtyError.WriteFail;
    }

    inline fn home(self: *Tty) TtyError!void {
        try self.write("\x1B[H");
    }

    inline fn clear(self: *Tty) TtyError!void {
        try self.write("\x1B[2J");
    }

    inline fn color(self: *Tty, foreground: Foreground, background: Background) TtyError!void {
        try self.writeFmt("\x1B[{d};{d}m", .{
            @intFromEnum(foreground),
            @intFromEnum(background),
        });
    }

    inline fn defaultColor(self: *Tty) TtyError!void {
        try self.write("\x1B[39;49m");
    }

    fn cursor(self: *Tty, enable: bool) TtyError!void {
        if (enable) {
            try self.write("\x1B[?25h");
        } else {
            try self.write("\x1B[?25l");
        }
    }
};

//inline fn setTermios(tty: Tty, termios: posix.termios) !void {
//    try posix.tcsetattr(tty.handle, .FLUSH, termios);
//}

// fn configure(tty: Tty) !posix.termios {
//     const oldTermios = try posix.tcgetattr(tty.handle);
//     errdefer setTermios(tty, oldTermios) catch {};

//     var newTermios = oldTermios;
//     newTermios.lflag.ICANON = false; // Switch to non-canonical mode.
//     newTermios.lflag.ECHO = false; // Do not echo input.
//     try setTermios(tty, newTermios);
//     try tty.writeAll("\x1B[?25l"); // Hide the cursor.

//     return oldTermios;
// }

// fn reset(tty: Tty, oldTermios: posix.termios) !void {
//     try setTermios(tty, oldTermios);
//     try tty.writeAll("\x1B[?25h"); // Show the cursor.
// }

pub fn main() !void {
    const allocator = heap.c_allocator;
    const stdin = io.getStdIn();

    var tty = Tty.init(stdin, allocator) catch |err| switch (err) {
        TtyError.NotATty => {
            log.err("stdin is not a tty! You need to use this program with a terminal emulator!", .{});
            return err;
        },
        else => |leftover_err| return leftover_err,
    };

    //const oldTermios = try configure(tty);
    //defer reset(tty, oldTermios) catch {};

    const foregrounds = comptime arrayFromEnum(Foreground);
    const backgrounds = comptime arrayFromEnum(Background);

    try tty.cursor(false);
    try tty.update(allocator);

    var colorIndex: usize = 0;
    while (true) {
        try tty.home();
        for (0..tty.height) |_| {
            try tty.color(foregrounds[colorIndex], backgrounds[colorIndex]);
            colorIndex += 1;
            if (colorIndex >= foregrounds.len) {
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
