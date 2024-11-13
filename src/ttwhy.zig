const std = @import("std");
const fs = std.fs;
const posix = std.posix;
const io = std.io;
const c = std.c;
const fmt = std.fmt;
const mem = std.mem;
const process = std.process;
const debug = std.debug;

const Allocator = mem.Allocator;
const File = fs.File;

pub const GraphicMode = enum(u8) {
    RESET_ALL = 0,
    // Foreground colors.
    FOREGROUND_BLACK = 30,
    FOREGROUND_RED = 31,
    FOREGROUND_GREEN = 32,
    FOREGROUND_YELLOW = 33,
    FOREGROUND_BLUE = 34,
    FOREGROUND_MAGENTA = 35,
    FOREGROUND_CYAN = 36,
    FOREGROUND_WHITE = 37,
    FOREGROUND_DEFAULT = 39,
    // Background colors.
    BACKGROUND_BLACK = 40,
    BACKGROUND_RED = 41,
    BACKGROUND_GREEN = 42,
    BACKGROUND_YELLOW = 43,
    BACKGROUND_BLUE = 44,
    BACKGROUND_MAGENTA = 45,
    BACKGROUND_CYAN = 46,
    BACKGROUND_WHITE = 47,
    BACKGROUND_DEFAULT = 49,
    // Styles.
    BOLD = 1,
    DIM = 2,
    RESET_BOLD_DIM = 22,
    ITALIC = 3,
    RESET_ITALIC = 23,
    UNDERLINE = 4,
    RESET_UNDERLINE = 24,
    BLINK = 5,
    RESET_BLINK = 25,
    REVERSE = 7,
    RESET_REVERSE = 27,
    INVISIBLE = 8,
    RESET_INVISIBLE = 28,
    STRIKETHROUGH = 9,
    RESET_STRIKETHROUGH = 29,
};

pub const Error = error{
    NotATty,
    UnknownSize,
    WriteFail,
};

const Writer = io.BufferedWriter(4096, File.Writer);
inline fn writer(file: File) Writer {
    return .{ .unbuffered_writer = file.writer() };
}

pub const Tty = struct {
    file: File,
    writer: Writer,
    width: u16,
    height: u16,

    pub fn init(file: File) Error!Tty {
        var tty = Tty{
            .file = file,
            .writer = writer(file),
            .width = undefined,
            .height = undefined,
        };

        if (!posix.isatty(file.handle)) return Error.NotATty;
        try tty.update();

        return tty;
    }

    pub fn update(self: *Tty) Error!void {
        self.writer.flush() catch return Error.WriteFail;

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
                const width = posix.getenv("COLUMNS") orelse break :getEnv;
                const height = posix.getenv("LINES") orelse break :getEnv;
                self.width = fmt.parseInt(u16, width, 10) catch break :getEnv;
                self.height = fmt.parseInt(u16, height, 10) catch break :getEnv;
                break :getSize;
            }
            // Else error.
            return Error.UnknownSize;
        }
    }

    pub inline fn write(self: *Tty, bytes: []const u8) Error!void {
        self.writer.writer().writeAll(bytes) catch return Error.WriteFail;
    }

    pub inline fn writeFmt(self: *Tty, comptime format: []const u8, args: anytype) Error!void {
        self.writer.writer().print(format, args) catch return Error.WriteFail;
    }

    pub inline fn home(self: *Tty) Error!void {
        try self.write("\x1B[H");
    }

    pub inline fn goto(self: *Tty, x: u16, y: u16) Error!void {
        try self.writeFmt("\x1B[{d};{d}H", .{ y, x });
    }

    pub inline fn clear(self: *Tty) Error!void {
        try self.write("\x1B[2J");
    }

    pub fn setGraphicModes(self: *Tty, graphicModes: []const GraphicMode) Error!void {
        debug.assert(0 != graphicModes.len);

        try self.write("\x1B[");
        var first = true;
        for (graphicModes) |graphicMode| {
            if (!first) try self.write(";");
            try self.writeFmt("{d}", .{@intFromEnum(graphicMode)});
            first = false;
        }
        try self.write("m");
    }

    pub inline fn resetGraphicModes(self: *Tty) Error!void {
        try self.writeFmt("\x1B[{d}m", .{@intFromEnum(GraphicMode.RESET_ALL)});
    }

    pub fn cursor(self: *Tty, enable: bool) Error!void {
        if (enable) {
            try self.write("\x1B[?25h");
        } else {
            try self.write("\x1B[?25l");
        }
    }
};
