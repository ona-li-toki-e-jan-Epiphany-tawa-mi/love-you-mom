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
    WriteFail,
};

const Writer = io.BufferedWriter(4096, File.Writer);
inline fn writer(file: File) Writer {
    return .{ .unbuffered_writer = file.writer() };
}

pub const Tty = struct {
    file: File,
    writer: Writer,

    dynamicSize: bool = true,
    width: u16 = undefined,
    height: u16 = undefined,

    pub fn init(file: File) Error!Tty {
        var tty = Tty{
            .file = file,
            .writer = writer(file),
        };

        if (!posix.isatty(file.handle)) return Error.NotATty;

        // Saves original terminal state.
        // \x1B[s      - Save cursor position.
        // \x1B[?47h   - Save screen.
        // \x1B[?1049h - Enable alternative buffer.
        try tty.write("\x1B[s\x1B[?47h\x1B[?1049h");

        try tty.update();
        return tty;
    }

    pub fn deinit(self: *Tty) void {
        // Restores original terminal state.
        // \x1B[?1049l - Disable alternative buffer.
        // \x1B[?47l   - Restore screen.
        // \x1B[u      - Restore cursor position.
        self.write("\x1B[?1049l\x1B[?47l\x1B[u") catch {};
        self.update() catch {};
    }

    pub fn update(self: *Tty) Error!void {
        self.writer.flush() catch return Error.WriteFail;

        if (self.dynamicSize) getSize: {
            {
                // First try ioctl.
                var winsize = mem.zeroes(posix.winsize);
                if (-1 != c.ioctl(self.file.handle, posix.T.IOCGWINSZ, &winsize)) {
                    self.width = winsize.ws_col;
                    self.height = winsize.ws_row;
                    break :getSize;
                }
            }
            // Remaining methods are idempotent, meaning they only need to called
            // once.
            self.dynamicSize = false;
            // Else try COLUMNS and LINES environment variables.
            getEnv: {
                const width = posix.getenv("COLUMNS") orelse break :getEnv;
                const height = posix.getenv("LINES") orelse break :getEnv;
                self.width = fmt.parseInt(u16, width, 10) catch break :getEnv;
                self.height = fmt.parseInt(u16, height, 10) catch break :getEnv;
                break :getSize;
            }
            // Else assume size.
            self.width = 80;
            self.height = 24;
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
