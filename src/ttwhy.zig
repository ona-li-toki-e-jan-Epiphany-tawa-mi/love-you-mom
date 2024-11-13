//! ttwhy terminal interface library.
//!
//! For POSIX systems and terminals that support ANSI codes and termios.
//! Requires libc.
//!
//! I add features to this library as-needed, so it may be missing something you
//! need. This library already handles the big problems (like getting terminal
//! size and dealing with termios,) so extending it should be easy peasy lemon
//! squeezy.
//!
//! Author: ona-li-toki-e-jan-Epiphany-tawa-mi
//! Version: 0.1.0.

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
const termios = posix.termios;
const V = posix.V;
const T = posix.T;
const NCSS = posix.NCSS;

pub const GraphicMode = enum(u8) {
    reset_all = 0,
    // Foreground colors.
    foreground_black = 30,
    foreground_red = 31,
    foreground_green = 32,
    foreground_yellow = 33,
    foreground_blue = 34,
    foreground_magenta = 35,
    foreground_cyan = 36,
    foreground_white = 37,
    foreground_default = 39,
    // Background colors.
    background_black = 40,
    background_red = 41,
    background_green = 42,
    background_yellow = 43,
    background_blue = 44,
    background_magenta = 45,
    background_cyan = 46,
    background_white = 47,
    background_default = 49,
    // Styles.
    bold = 1,
    dim = 2,
    reset_bold_dim = 22,
    italic = 3,
    reset_italic = 23,
    underline = 4,
    reset_underline = 24,
    blink = 5,
    reset_blink = 25,
    reverse = 7,
    reset_reverse = 27,
    invisible = 8,
    reset_invisible = 28,
    strikethrough = 9,
    reset_strikethrough = 29,
};

pub const Error = error{
    NotATty,
    WriteFail,
    TermiosFail,
    ReadFail,
};

pub const Writer = io.BufferedWriter(4096, File.Writer);

/// tty interface abstraction.
pub const Tty = struct {
    /// Terminal width/columns. Run fn self.update before querying.
    width: u16 = undefined,
    /// Terminal height/rows. Run fn self.update before querying.
    height: u16 = undefined,

    file: File,
    writer: Writer,
    /// Whether the size fetch commands in fn self.update can be rerun to keep
    /// the width and height up-to-date.
    dynamic_size: bool = true,
    /// Whether fn self.save has been run without running fn self.restore.
    saved: bool = false,
    /// The terminal's original termios state before running fn self.uncook.
    /// null if it hasn't been called or fn self.cook was.
    original_termios: ?termios = null,

    const Self = @This();

    /// Creates a new Tty from the given file. The file should either be
    /// (ideally) /dev/tty opened in read/write mode, or stdin (if stdin points
    /// to a terminal.)
    pub fn init(file: File) Error!Tty {
        if (!posix.isatty(file.handle)) return Error.NotATty;

        return Self{
            .file = file,
            .writer = .{ .unbuffered_writer = file.writer() },
        };
    }

    /// Saves the state of the terminal's buffer at the time of calling. The
    /// state can (and must) be restored later by calling fn self.restore.
    ///
    /// Terminal must not be saved prior to calling.
    pub fn save(self: *Self) Error!void {
        debug.assert(!self.saved);

        // \x1B[s      - Save cursor position.
        // \x1B[?47h   - Save screen.
        // \x1B[?1049h - Enable alternative buffer.
        try self.write("\x1B[s\x1B[?47h\x1B[?1049h");
        try self.update();
        self.saved = true;
    }

    /// Restores the state of the terminal's buffer saved by fn self.save.
    ///
    /// Terminal must be saved prior to calling.
    pub fn restore(self: *Self) Error!void {
        debug.assert(self.saved);

        // \x1B[?1049l - Disable alternative buffer.
        // \x1B[?47l   - Restore screen.
        // \x1B[u      - Restore cursor position.
        try self.write("\x1B[?1049l\x1B[?47l\x1B[u");
        try self.update();
        self.saved = false;
    }

    /// 'Uncooks' the terminal, switching it into non-canonical mode, meaning
    /// that the terminal reads input byte-by-byte rather than line-by-line.
    /// Disables handling of control characters (i.e. C-c and C-v) so you cannot
    /// handle them yourself.
    ///
    /// Reads are set to not timeout and not have a minimum number of bytes to
    /// read. For more information/configure uncooked reads, see fn
    /// self.configureUncookedRead.
    ///
    /// Caller should call fn self.cook to restore the terminal when done.
    ///
    /// Terminal must not be uncooked prior to calling.
    pub fn uncook(self: *Self) Error!void {
        debug.assert(null == self.original_termios);
        self.original_termios = posix.tcgetattr(self.file.handle) catch
            return Error.TermiosFail;

        // https://zig.news/lhp/want-to-create-a-tui-application-the-basics-of-uncooked-terminal-io-17gm
        var new_termios = self.original_termios.?;
        new_termios.lflag.ECHO = false; // Do not display user typed keys.
        new_termios.lflag.ICANON = false; // Disables canonical mode.
        new_termios.lflag.ISIG = false; // Disables external C-c and C-z handling.
        new_termios.lflag.IEXTEN = false; // Disables external C-v handling.
        new_termios.iflag.IXON = false; // Disables external C-s and C-q handling.
        new_termios.iflag.ICRNL = false; // Disables external C-j and C-m handling.
        new_termios.oflag.OPOST = false; // Disables output processing.
        // Makes reads not timeout.
        new_termios.cc[@intFromEnum(V.TIME)] = 0;
        new_termios.cc[@intFromEnum(V.MIN)] = 0;

        posix.tcsetattr(self.file.handle, .FLUSH, new_termios) catch
            return Error.TermiosFail;
    }

    /// 'Un-uncooks' the terminal, restoring the terminal's termios to the state
    /// before fn self.uncook was run.
    ///
    /// Terminal must be uncooked prior to calling.
    pub fn cook(self: *Self) Error!void {
        debug.assert(null != self.original_termios);

        posix.tcsetattr(self.file.handle, .FLUSH, self.original_termios.?) catch
            return Error.TermiosFail;

        self.original_termios = null;
    }

    /// Configures the timeout and minimum bytes to read in uncooked mode. See
    /// VTIME and VMIN in 'man termios' for more information.
    ///
    /// Terminal must uncooked with fn self.uncook prior to calling.
    pub fn configureUncookedRead(self: *Self, time: NCSS, min: NCSS) Error!void {
        debug.assert(null != self.original_termios);

        var new_termios = posix.tcgetattr(self.file.handle) catch
            return Error.TermiosFail;
        new_termios.cc[@intFromEnum(V.TIME)] = time;
        new_termios.cc[@intFromEnum(V.MIN)] = min;
        posix.tcsetattr(self.file.handle, .NOW, new_termios) catch
            return Error.TermiosFail;
    }

    /// Syncronizes the actual terminal and this representation
    /// Needs to be called after issuing commands or writing text to the
    /// terminal for the writes to actually occur.
    pub fn update(self: *Self) Error!void {
        self.writer.flush() catch return Error.WriteFail;

        if (self.dynamic_size) getSize: {
            {
                // First try ioctl.
                var winsize = mem.zeroes(posix.winsize);
                if (-1 != c.ioctl(self.file.handle, T.IOCGWINSZ, &winsize)) {
                    self.width = winsize.ws_col;
                    self.height = winsize.ws_row;
                    break :getSize;
                }
            }
            // Remaining methods are idempotent, meaning they only need to called
            // once.
            self.dynamic_size = false;
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

    /// Call fn self.update to write data out to terminal.
    pub inline fn write(self: *Self, bytes: []const u8) Error!void {
        self.writer.writer().writeAll(bytes) catch return Error.WriteFail;
    }

    /// Call fn self.update to write data out to terminal.
    pub inline fn writeFmt(
        self: *Self,
        comptime format: []const u8,
        args: anytype,
    ) Error!void {
        self.writer.writer().print(format, args) catch return Error.WriteFail;
    }

    /// Reads data from the terminal's input buffer.
    /// Reads line-by-line in cooked mode (default.)
    /// Reads byte-by-byte in uncooked mode (see fn self.uncook.)
    pub inline fn read(self: *Self, buffer: []u8) Error!usize {
        return self.file.read(buffer) catch return Error.ReadFail;
    }

    /// Moves the cursor to it's home position (0,0).
    ///
    /// Call fn self.update to write data out to terminal.
    pub inline fn home(self: *Self) Error!void {
        try self.write("\x1B[H");
    }

    /// Moves the cursor to (x,y).
    ///
    /// Call fn self.update to write data out to terminal.
    pub inline fn goto(self: *Self, x: u16, y: u16) Error!void {
        try self.writeFmt("\x1B[{d};{d}H", .{ y, x });
    }

    /// Call fn self.update to write data out to terminal.
    pub inline fn clear(self: *Self) Error!void {
        try self.write("\x1B[2J");
    }

    /// Sets the graphics modes for any written text that follows this command.
    ///
    /// Call fn self.update to write data out to terminal.
    pub fn setGraphicModes(self: *Self, graphic_modes: []const GraphicMode) Error!void {
        debug.assert(0 != graphic_modes.len);

        try self.write("\x1B[");
        var first = true;
        for (graphic_modes) |graphic_mode| {
            if (!first) try self.write(";");
            try self.writeFmt("{d}", .{@intFromEnum(graphic_mode)});
            first = false;
        }
        try self.write("m");
    }

    /// Call fn self.update to write data out to terminal.
    pub inline fn resetGraphicModes(self: *Self) Error!void {
        try self.writeFmt("\x1B[{d}m", .{@intFromEnum(GraphicMode.reset_all)});
    }

    /// Enables/shows or disables/hides the cursor.
    ///
    /// Call fn self.update to write data out to terminal.
    pub fn cursor(self: *Self, enable: bool) Error!void {
        if (enable) {
            try self.write("\x1B[?25h");
        } else {
            try self.write("\x1B[?25l");
        }
    }
};
