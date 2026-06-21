const std = @import("std");
const Gltf = @import("zgltf");
const Framebuffer = @import("framebuffer.zig");
const vec = @import("vector.zig");

const WIDTH: usize = 512;
const HEIGHT: usize = 512;

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

    gltf.debugPrint();

    var fb = try Framebuffer.init(arena, WIDTH, HEIGHT);
    defer fb.deinit();

    fb.drawLine(.{ .x = 0, .y = 0 }, .{ .x = 512, .y = 512 });

    const encoded = try arena.alloc(u8, std.base64.standard.Encoder.calcSize(fb.rgba.len));
    const enc = std.base64.standard.Encoder.encode(encoded, fb.rgba);

    std.debug.print("\x1b_Gf=32,s={d},v={d},a=T;{s}\x1b\\\n", .{ fb.width, fb.height, enc });
    arena.free(encoded);
}
