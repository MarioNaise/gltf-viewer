const std = @import("std");
const Gltf = @import("zgltf");
const Framebuffer = @import("framebuffer.zig");
const render = @import("render.zig");

const print = std.debug.print;

const WIDTH: usize = 512;
const HEIGHT: usize = 512;

const COL: u8 = 60;
const ROW: u8 = 30;

var DEBUG = false;

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        print("Usage: gltfv [GLTF/GLB-FILE]\n", .{});
        return;
    }

    if (args.len > 2 and std.mem.eql(u8, args[2], "-d"))
        DEBUG = true;

    const gltf_path = args[1];

    const buf = try std.Io.Dir.cwd().readFileAllocOptions(
        init.io,
        gltf_path,
        arena,
        .unlimited,
        .@"4",
        null,
    );
    defer arena.free(buf);

    var gltf = Gltf.init(arena);
    defer gltf.deinit();

    try gltf.parse(buf);

    const bin: []align(4) const u8 = if (gltf.glb_binary) |embedded| embedded else blk: {
        if (gltf.data.buffers.len == 0 or gltf.data.buffers[0].uri == null) {
            print("No GLB binary or buffer URI found.\n", .{});
            return;
        }

        const dir = if (std.mem.lastIndexOfScalar(u8, gltf_path, '/')) |i| gltf_path[0..i] else ".";
        const bin_path = try std.fs.path.join(arena, &.{ dir, gltf.data.buffers[0].uri.? });

        break :blk try std.Io.Dir.cwd().readFileAllocOptions(
            init.io,
            bin_path,
            arena,
            .limited(gltf.data.buffers[0].byte_length + 1),
            .@"4",
            null,
        );
    };
    gltf.glb_binary = bin;

    var fb = try Framebuffer.init(arena, WIDTH, HEIGHT);
    defer fb.deinit();

    const MAX_IMAGES: u8 = 25;
    const DISTANCE: f32 = 5;
    const ROT_DISTANCE: f32 = (std.math.pi * 2) / @as(f32, MAX_IMAGES);
    var ROT_Y: f32 = 0;
    var ID: u8 = 0;

    print("\x1b[?25l", .{});
    while (ID < MAX_IMAGES) : (ROT_Y += ROT_DISTANCE) {
        print("\r                          \r", .{});
        print("Rendering frame {d}/{d}", .{ ID + 1, MAX_IMAGES });
        ID += 1;
        try render.renderGltf(&gltf, &fb, DISTANCE, ROT_Y);

        const encoded = try arena.alloc(u8, std.base64.standard.Encoder.calcSize(fb.rgba.len));
        const payload = std.base64.standard.Encoder.encode(encoded, fb.rgba);

        print(
            "\x1b_Gf=32,s={d},v={d},i={d},q=1;{s}\x1b\\",
            .{ fb.width, fb.height, ID, payload },
        );

        arena.free(encoded);
        @memset(fb.rgba, 0);
    }

    print("\x1b[s\r                          \r", .{});
    if (DEBUG) {
        gltf.debugPrint();
    }

    ID = 1;
    while (true) : (ID = if (ID >= MAX_IMAGES) 1 else ID + 1) {
        print(
            "\x1b[u\x1b_Ga=d\x1b\\\x1b_Ga=p,i={d},c={d},r={d},q=1;\x1b\\\n",
            .{ ID, COL, ROW },
        );
        try init.io.sleep(.fromMilliseconds(100), .real);
    }
}
