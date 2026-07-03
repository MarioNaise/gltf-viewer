const std = @import("std");
const print = std.debug.print;
const exit = std.process.exit;
const builtin = @import("builtin");

const Gltf = @import("zgltf");

const flag = @import("flag.zig");
const Framebuffer = @import("Framebuffer.zig");
const Renderer = @import("Renderer.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    defer arena.free(args);

    if (args.len < 2) {
        print(flag.USAGE, .{});
        exit(1);
    }

    const gltf_path = args[1];

    const flags = flag.parse(args);

    if (init.environ_map.get("TMUX") != null) {
        print("gltfv cannot run under TMUX\n", .{});
        exit(1);
    }

    const io = init.io;
    const cwd = std.Io.Dir.cwd();
    const file_buf = try cwd.readFileAllocOptions(
        io,
        gltf_path,
        arena,
        .unlimited,
        .@"4",
        null,
    );
    defer arena.free(file_buf);

    var gltf = Gltf.init(arena);
    defer gltf.deinit();

    try gltf.parse(file_buf);

    const bin: []align(4) const u8 = if (gltf.glb_binary) |embedded| embedded else blk: {
        if (gltf.data.buffers.len == 0 or gltf.data.buffers[0].uri == null) {
            print("No GLB binary or buffer URI found.\n", .{});
            exit(1);
        }

        const dir = if (std.mem.lastIndexOfScalar(u8, gltf_path, '/')) |i| gltf_path[0..i] else ".";
        const bin_path = try std.fs.path.join(arena, &.{ dir, gltf.data.buffers[0].uri.? });
        defer arena.free(bin_path);

        break :blk try std.Io.Dir.cwd().readFileAllocOptions(
            io,
            bin_path,
            arena,
            .limited(gltf.data.buffers[0].byte_length + 1),
            .@"4",
            null,
        );
    };

    defer arena.free(bin);
    gltf.glb_binary = bin;

    var renderer = Renderer.init(arena);
    var fb = try Framebuffer.init(arena, flags.pixels, flags.pixels);
    defer fb.deinit(arena);

    const enc_buf = try arena.alloc(u8, std.base64.standard.Encoder.calcSize(fb.rgba.len * @sizeOf(Framebuffer.Color)));
    defer arena.free(enc_buf);

    var image_id: u8 = 1;
    var rotation: f32 = 0;

    print("\x1b_Ga=d\x1b\\\x1b[?25l\x1b[s", .{});
    defer print("\x1b[?25h", .{});

    while (image_id <= flags.frames) : ({
        rotation += 360 / @as(f32, @floatFromInt(flags.frames));
        image_id += 1;
    }) {
        print("Rendering frame {d}/{d}\r", .{ image_id, flags.frames });

        try renderer.renderGltf(
            &gltf,
            &fb,
            .{
                .scale = flags.scale,
                .translation = flags.translation,
                .rotation = .{
                    flags.rotation[0] + if (flags.rotX) rotation else 0,
                    flags.rotation[1] + if (flags.rotY) rotation else 0,
                    flags.rotation[2] + if (flags.rotZ) rotation else 0,
                },
            },
        );

        if (builtin.cpu.arch.endian() == .little) {
            std.mem.byteSwapAllElements(u32, fb.rgba);
        }
        const payload = std.base64.standard.Encoder.encode(enc_buf, std.mem.sliceAsBytes(fb.rgba));

        print(
            "\x1b_Gf=32,s={d},v={d},i={d},q=1;{s}\x1b\\",
            .{ fb.width, fb.height, image_id, payload },
        );

        fb.clear();
    }

    print("\r                          \r", .{});
    if (flags.debug) {
        gltf.debugPrint();
    }

    image_id = 1;
    const format = "\x1b[u\x1b_Ga=d\x1b\\\x1b_Ga=p,i={d},c={d},r={d},q=1;\x1b\\\n";
    while (image_id <= flags.frames) {
        print(
            format,
            .{ image_id, flags.col, flags.row },
        );
        if (flags.frames == 1) exit(0);

        try io.sleep(.fromMilliseconds(flags.timeout), .real);

        image_id += 1;
        if (flags.loop and image_id > flags.frames) image_id = 1 else print(
            format,
            .{ 1, flags.col, flags.row },
        );
    }
}
