const std = @import("std");
const fs = std.fs;
const posix = std.posix;
const io = std.io;
const c = std.c;
const fmt = std.fmt;
const mem = std.mem;
const process = std.process;

const Allocator = mem.Allocator;
const File = fs.File;

////////////////////////////////////////////////////////////////////////////////
// Colors                                                                     //
////////////////////////////////////////////////////////////////////////////////

pub const Foreground = enum(u8) {
    BLACK = 30,
    RED = 31,
    GREEN = 32,
    YELLOW = 33,
    BLUE = 34,
    MAGENTA = 35,
    CYAN = 36,
    WHITE = 37,
    DEFAULT = 39,
};

pub const Background = enum(u8) {
    BLACK = 40,
    RED = 41,
    GREEN = 42,
    YELLOW = 43,
    BLUE = 44,
    MAGENTA = 45,
    CYAN = 46,
    WHITE = 47,
    DEFAULT = 49,
};

pub const Style = enum(u8) {
    BOLD = 1,
    DIM = 2,
    DEFAULT = 22,
};

fn arrayFromEnum(comptime E: type) [@typeInfo(E).Enum.fields.len]E {
    const fields = @typeInfo(E).Enum.fields;
    var array: [fields.len]E = undefined;
    for (fields, &array) |field, *element| {
        element.* = @enumFromInt(field.value);
    }
    return array;
}

pub const foregrounds = arrayFromEnum(Foreground);
pub const backgrounds = arrayFromEnum(Background);
pub const styles = arrayFromEnum(Style);

////////////////////////////////////////////////////////////////////////////////
// TTY                                                                        //
////////////////////////////////////////////////////////////////////////////////

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
    allocator: Allocator,

    pub fn init(file: File, allocator: Allocator) Error!Tty {
        var tty = Tty{
            .file = file,
            .writer = writer(file),
            .width = undefined,
            .height = undefined,
            .allocator = allocator,
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
                var env = process.getEnvMap(self.allocator) catch break :getEnv;
                defer env.deinit();
                const width = env.get("COLUMNS") orelse break :getEnv;
                const height = env.get("LINES") orelse break :getEnv;
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
        fmt.format(self.writer.writer(), format, args) catch return Error.WriteFail;
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

    pub inline fn color(self: *Tty, foreground: Foreground, background: Background, style: Style) Error!void {
        try self.writeFmt("\x1B[{d};{d};{d}m", .{
            @intFromEnum(style),
            @intFromEnum(foreground),
            @intFromEnum(background),
        });
    }

    pub inline fn defaultColor(self: *Tty) Error!void {
        try self.color(Foreground.DEFAULT, Background.DEFAULT, Style.DEFAULT);
    }

    pub fn cursor(self: *Tty, enable: bool) Error!void {
        if (enable) {
            try self.write("\x1B[?25h");
        } else {
            try self.write("\x1B[?25l");
        }
    }
};
