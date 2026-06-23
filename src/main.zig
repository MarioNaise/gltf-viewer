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

    var fb = try Framebuffer.init(arena, WIDTH, HEIGHT);
    defer fb.deinit();

    print("\x1b[?25l\x1b[s", .{});

    if (DEBUG) {
        gltf.debugPrint();
    }

    const DISTANCE: f32 = 5;
    var ROT_Y: f32 = 0;
    while (true) : (ROT_Y = if (ROT_Y >= 2 * std.math.pi) 0 else ROT_Y + 0.1) {
        try render.renderGltf(&gltf, &fb, bin, DISTANCE, ROT_Y);

        const encoded = try arena.alloc(u8, std.base64.standard.Encoder.calcSize(fb.rgba.len));
        const payload = std.base64.standard.Encoder.encode(encoded, fb.rgba);

        print("\x1b_Ga=d\x1b\\\x1b[u", .{});
        print(
            "\x1b_Gf=32,s={d},v={d},c={d},r={d},a=T;{s}\x1b\\\n",
            .{ fb.width, fb.height, COL, ROW, payload },
        );

        if (DEBUG)
            print(
                "distance :{}, rotY: {}",
                .{ DISTANCE, ROT_Y },
            );

        arena.free(encoded);
        @memset(fb.rgba, 0);
        try init.io.sleep(.fromMilliseconds(50), .real);
    }
}
