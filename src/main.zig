const std = @import("std");
const Gltf = @import("zgltf");
const Framebuffer = @import("framebuffer.zig");
const render = @import("render.zig");

const WIDTH: usize = 512;
const HEIGHT: usize = 512;

const COL: u8 = 60;
const ROW: u8 = 30;

const DISTANCE: f32 = 100;

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        std.debug.print("Usage: gltfv [GLTF/GLB-FILE]\n", .{});
        return;
    }

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

    var fb = try Framebuffer.init(arena, WIDTH, HEIGHT);
    defer fb.deinit();

    std.debug.print("\x1b[?25l\x1b[s", .{});

    var rot: f32 = 0;
    while (true) : (rot = if (rot >= 2 * std.math.pi) 0 else rot + 0.1) {
        try render.renderGltf(&gltf, &fb, gltf.glb_binary.?, 100, rot);

        const encoded = try arena.alloc(u8, std.base64.standard.Encoder.calcSize(fb.rgba.len));
        const payload = std.base64.standard.Encoder.encode(encoded, fb.rgba);

        std.debug.print("\x1b_Ga=d\x1b\\\x1b[u", .{});
        std.debug.print(
            "\x1b_Gf=32,s={d},v={d},c={d},r={d},a=T;{s}\x1b\\\ni:{}, r: {}",
            .{ fb.width, fb.height, COL, ROW, payload, 100, rot },
        );
        arena.free(encoded);
        @memset(fb.rgba, 0);
        try init.io.sleep(.fromMilliseconds(50), .real);
    }
}
