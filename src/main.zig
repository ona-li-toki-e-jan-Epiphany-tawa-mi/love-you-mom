const std = @import("std");
const log = std.log;
const io = std.io;
const time = std.time;
const fs = std.fs;
const process = std.process;
const mem = std.mem;
const ttwhy = @import("ttwhy.zig");
const graphics = @import("graphics.zig");

const Tty = ttwhy.Tty;
const Timer = time.Timer;
const ArgIterator = process.ArgIterator;
const File = fs.File;

const FileWriter = io.BufferedWriter(4096, File.Writer);

fn help(stdout: *FileWriter, parsedArgs: ParsedArgs) !void {
    const writer = stdout.writer();

    try writer.print(
        \\Usages:
        \\  {s} [OPTIONS...]
        \\
        \\Tells your mom (or dad) that you love them.
        \\
        \\Press any key to exit.
        \\Requires terminal.
        \\
        \\Options:
        \\  -h, --help            Displays this help text and exits.
        \\  -v, --version         Displays version information and exits.
        \\  -d, --love-you-dad    Tell your dad that you love him.
        \\
    , .{parsedArgs.programName});

    try stdout.flush();
}

fn version(stdout: *FileWriter) !void {
    const writer = stdout.writer();
    try writer.print("love-you-mom 0.1.0\n", .{});
    try stdout.flush();
}

// TODO Implement love you dad option.
// TODO document functions.
pub fn main() !void {
    var stdout: FileWriter = .{ .unbuffered_writer = io.getStdOut().writer() };

    var args = process.args();
    const parsedArgs = try parseArgs(&args);
    if (parsedArgs.displayHelp) {
        try help(&stdout, parsedArgs);
        return;
    } else if (parsedArgs.displayVersion) {
        try version(&stdout);
        return;
    } else if (parsedArgs.loveYouDad) {
        return error.NotImplemented;
    }

    const ttyFile = fs.cwd().openFile("/dev/tty", .{ .mode = .read_write }) catch |err| {
        log.err("Unable to open /dev/tty. You need to run this program in a terminal", .{});
        return err;
    };
    defer ttyFile.close();

    var tty = Tty.init(ttyFile) catch |err| switch (err) {
        error.NotATty => {
            log.err(
                "/dev/tty is not a tty! The sky is falling, Chicken Little!",
                .{},
            );
            return err;
        },
        else => |leftover_err| return leftover_err,
    };
    try tty.save();
    defer tty.restore() catch {};
    try tty.uncook();
    defer tty.cook() catch {};

    try run(&tty);
}

const ParsedArgs = struct {
    programName: []const u8 = undefined,
    displayHelp: bool = false,
    displayVersion: bool = false,
    loveYouDad: bool = false,
};

fn parseShortOption(parsedArgs: *ParsedArgs, option: u8) !bool {
    switch (option) {
        'h' => {
            parsedArgs.displayHelp = true;
            return true;
        },
        'v' => {
            parsedArgs.displayVersion = true;
            return true;
        },
        'd' => parsedArgs.loveYouDad = true,

        else => {
            log.err("Unknown command line option '-{c}'", .{option});
            return error.UnknownOption;
        },
    }

    return false;
}

fn parseArgs(args: *ArgIterator) !ParsedArgs {
    var parsedArgs: ParsedArgs = .{};

    parsedArgs.programName = args.next().?;

    while (args.next()) |arg| parsingLoop: {
        if (2 <= arg.len and '-' == arg[0] and '-' != arg[1]) {
            var first = true;
            for (arg) |shortOption| {
                if (first) {
                    first = false;
                    continue;
                }
                const shouldEndParsing = try parseShortOption(&parsedArgs, shortOption);
                if (shouldEndParsing) break :parsingLoop;
            }
        } else if (mem.eql(u8, "--help", arg)) {
            parsedArgs.displayHelp = true;
            break :parsingLoop;
        } else if (mem.eql(u8, "--version", arg)) {
            parsedArgs.displayVersion = true;
            break :parsingLoop;
        } else if (mem.eql(u8, "--love-you-dad", arg)) {
            parsedArgs.loveYouDad = true;
        } else {
            log.err("Unknown command line option '{s}'", .{arg});
            return error.UnknownOption;
        }
    }

    return parsedArgs;
}

fn run(tty: *Tty) !void {
    const nanosecondsPerSecond = comptime 1_000_000_000;
    const fps = comptime 15;
    const nanosecondsPerFrame: u64 = comptime nanosecondsPerSecond / fps;

    try tty.cursor(false);
    defer tty.cursor(true) catch {};

    var timer = try Timer.start();
    while (true) {
        const deltaTime_ns = timer.lap();
        if (nanosecondsPerFrame > deltaTime_ns) {
            time.sleep(nanosecondsPerFrame - deltaTime_ns);
        }

        const deltaTime_s = @as(f64, @floatFromInt(deltaTime_ns)) / nanosecondsPerSecond;
        try graphics.draw(tty, deltaTime_s);
        try tty.update();

        // Exits if any key is pressed.
        var buffer: [1]u8 = undefined;
        const bytesRead = try tty.read(&buffer);
        if (0 != bytesRead) break;
    }
}
