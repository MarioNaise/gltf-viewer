const std = @import("std");

pub const USAGE =
    \\GLTF Viewer - A simple GLTF/GLB viewer for the terminal
    \\
    \\  Usage: gltfv [GLTF/GLB-FILE] [ARGS]
    \\
    \\  Note: This program is using the Kitty terminal graphics protocol, so it will only work
    \\  in terminals that support it (e.g. Kitty, WezTerm, Ghostty...).
    \\
    \\  Args:
    \\  Arguments can be specified in any order and can be combined (e.g. -dly).
    \\  If an argument requires a value, it must be specified after (e.g. -c 80).
    \\
    \\  General:
    \\
    \\    -D                Print debug information
    \\    -L                Loop the animation
    \\
    \\    -C <number>       Width of frame in terminal columns (affects aspect ratio)
    \\    -R <number>       Height of frame in terminal rows (affects aspect ratio)
    \\    -P <number>       Width and height of the output image in pixels
    \\    -F <number>       Amount of frames to render
    \\    -T <number>       Timeout between frames in milliseconds
    \\
    \\  Model manipulation:
    \\
    \\    Rotate 360 degrees around the specified axis over the course of the animation.
    \\    -x                Rotate model around X axis
    \\    -y                Rotate model around Y axis
    \\    -z                Rotate model around Z axis
    \\
    \\  Vectors:
    \\  For vector arguments, the value must be specified as a comma-separated list (e.g. -s 1,2,3).
    \\  If only one number is provided, it will be used for all axes.
    \\  Values can be skipped by providing only a comma, in which case the default value will be used for
    \\  that axis (e.g. -s 1,,3 will set scale to 1,1,3).
    \\
    \\    -s <vector>       Scale of the model (default: 1,1,1)
    \\
    \\    -t <vector>       Translation of the model (default: 0,0,5)
    \\
    \\    -r <vector>       Rotation of the model in radians (default: 0,0,0)
    \\
    \\    -h / --help       Show this message
    \\
;

pub const FlagSet = struct {
    debug: bool = false,
    loop: bool = false,
    rotX: bool = false,
    rotY: bool = false,
    rotZ: bool = false,
    col: u8 = 60,
    row: u8 = 30,
    frames: u32 = 1,
    timeout: u32 = 200,
    pixels: usize = 512,
    scale: [3]f32 = .{ 1, 1, 1 },
    translation: [3]f32 = .{ 0, 0, 5 },
    rotation: [3]f32 = .{ 0, 0, 0 },
};

const err_invalid = "Invalid value '{s}' for argument '{s}'";
const err_missing = "Value missing for argument '{s}'";

pub fn parse(args: []const [:0]const u8) FlagSet {
    var flags = FlagSet{};

    outer: for (args, 0..) |arg, i| {
        if (arg.len < 2 or arg[0] != '-') continue;
        for (arg[1..]) |char| {
            if (char >= '0' and char <= '9') continue :outer;
            switch (char) {
                'h' => usage(),
                '-' => if (std.mem.eql(u8, arg[2..], "help"))
                    usage()
                else
                    errExit("Unknown argument '{s}'", .{arg}),
                'D' => flags.debug = true,
                'L' => flags.loop = true,
                'x' => flags.rotX = true,
                'y' => flags.rotY = true,
                'z' => flags.rotZ = true,
                'C' => flags.col = parseFlagNumber(u8, args[i..]),
                'R' => flags.row = parseFlagNumber(u8, args[i..]),
                'F' => flags.frames = parseFlagNumber(u32, args[i..]),
                'T' => flags.timeout = parseFlagNumber(u32, args[i..]),
                'P' => flags.pixels = parseFlagNumber(usize, args[i..]),
                's' => flags.scale = parseFlagVec3(args[i..], .{ 1, 1, 1 }),
                't' => flags.translation = parseFlagVec3(args[i..], .{ 0, 0, 5 }),
                'r' => flags.rotation = parseFlagVec3(args[i..], .{ 0, 0, 0 }),
                else => errExit("Unknown argument -{c}", .{char}),
            }
        }
    }
    return flags;
}

pub fn usage() noreturn {
    std.debug.print(USAGE, .{});
    std.process.exit(0);
}

fn errExit(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n" ++ USAGE, args);
    std.process.exit(1);
}

fn parseFlagVec3(rest_args: []const [:0]const u8, fallback: [3]f32) [3]f32 {
    if (rest_args.len < 2) {
        errExit(err_missing, .{rest_args[0]});
    }

    var vec: [3]f32 = fallback;
    var it = std.mem.splitScalar(u8, rest_args[1], ',');

    var i: usize = 0;
    while (it.next()) |value| : (i += 1) {
        if (value.len == 0) continue;
        if (i >= 3) {
            errExit(err_invalid, .{ rest_args[1], rest_args[0] });
        }
        vec[i] = parseNumber(f32, value) catch {
            errExit(err_invalid, .{ value, rest_args[0] });
        };
        if (i == 0 and it.peek() == null) return .{ vec[0], vec[0], vec[0] };
    }
    return vec;
}

fn parseFlagNumber(comptime T: type, rest_args: []const [:0]const u8) T {
    if (rest_args.len < 2) {
        errExit(err_missing, .{rest_args[0]});
    }
    return parseNumber(T, rest_args[1]) catch {
        errExit(err_invalid, .{ rest_args[1], rest_args[0] });
    };
}

fn parseNumber(comptime T: type, str: []const u8) !T {
    switch (@typeInfo(T)) {
        .int => {
            return std.fmt.parseInt(T, str, 10);
        },
        .float => {
            return std.fmt.parseFloat(T, str);
        },
        else => {
            @compileError("Unsupported type for parseNumber");
        },
    }
}

test "parse" {
    try std.testing.expectEqual(FlagSet{
        .debug = true,
        .loop = true,
        .rotX = true,
        .rotY = true,
        .rotZ = true,
        .col = 80,
        .row = 40,
        .frames = 10,
        .timeout = 100,
        .pixels = 1024,
        .scale = .{ 1, 2, 3 },
        .translation = .{ 4, 5, 5 },
        .rotation = .{ 0, 8, 9 },
    }, parse(&[_][:0]const u8{
        "",   "-D",   "-L", "-xyz",  "-C", "80",  "-R", "40",   "-F", "10", "-T", "100",
        "-P", "1024", "-s", "1,2,3", "-t", "4,5", "-r", ",8,9",
    }));
}

test "parseFlagVec3" {
    const expectEql = std.testing.expectEqual;

    try expectEql([3]f32{ 1, 2, 3 }, parseFlagVec3(&[_][:0]const u8{ "", "1,2,3" }, .{ 0, 0, 0 }));
    try expectEql([3]f32{ 1, 1, 1 }, parseFlagVec3(&[_][:0]const u8{ "", "1" }, .{ 0, 0, 0 }));
    try expectEql([3]f32{ 1, 0, 3 }, parseFlagVec3(&[_][:0]const u8{ "", "1,,3" }, .{ 0, 0, 0 }));
    try expectEql([3]f32{ 1, 1, 3 }, parseFlagVec3(&[_][:0]const u8{ "", ",,3" }, .{ 1, 1, 1 }));
}

test "parseFlagNumber" {
    const expectEql = std.testing.expectEqual;

    try expectEql(42, parseFlagNumber(u8, &[_][:0]const u8{ "", "42" }));
    try expectEql(42, parseFlagNumber(u32, &[_][:0]const u8{ "", "42" }));
    try expectEql(42, parseFlagNumber(usize, &[_][:0]const u8{ "", "42" }));
}

test "parseNumber" {
    const expectEql = std.testing.expectEqual;
    const expectError = std.testing.expectError;

    const x = parseNumber(i32, "42") catch unreachable;
    try expectEql(42, x);
    try expectEql(i32, @TypeOf(x));

    const y = parseNumber(f32, ".42") catch unreachable;
    try expectEql(0.42, y);
    try expectEql(f32, @TypeOf(y));

    try expectError(error.Overflow, parseNumber(i32, "2147483648"));
    try expectError(error.InvalidCharacter, parseNumber(i32, "2,55"));
    try expectError(error.InvalidCharacter, parseNumber(f32, "2,55"));
}
