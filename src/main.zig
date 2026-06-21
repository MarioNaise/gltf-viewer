const std = @import("std");
const Gltf = @import("zgltf");

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
}
