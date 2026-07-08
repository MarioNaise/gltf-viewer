const std = @import("std");

const Gltf = @import("zgltf");
const zalgebra = @import("zalgebra");
const Vec2 = zalgebra.Vec2;
const Vec3 = zalgebra.Vec3;
const Mat4 = zalgebra.Mat4;
const zigimg = @import("zigimg");

const Canvas = @import("Canvas.zig");
const Pixel = Canvas.Pixel;
const Color = @import("Color.zig");
const helpers = @import("helpers.zig");
const interpolate = helpers.interpolate;

const Renderer = @This();

allocator: std.mem.Allocator,
// TODO: create a loader for gltf data to hold images, positions, texcoords, etc.
image_cache: []?Texture.Image,

// TODO: clipping
// TODO: depth buffer

const CLIP_Z: f32 = 1;

const Config = struct {
    wireframe: bool = false,
    scale: [3]f32 = .{ 1, 1, 1 },
    translation: [3]f32 = .{ 0, 0, 0 },
    rotation: [3]f32 = .{ 0, 0, 0 },
};

pub const Context = struct {
    wireframe: bool = false,
    canvas: *Canvas,
    gltf: *Gltf,
    bin: []align(4) const u8,
    world: Mat4,
};

pub const Triangle = struct {
    p0: Point,
    p1: Point,
    p2: Point,
    texture: Texture,

    const Point = struct {
        vec: Vec3,
        uv: Vec2,
    };
};

pub const Texture = struct {
    color_factor: [4]f32,
    image: ?Image,

    pub const Image = struct {
        width: usize,
        height: usize,
        pixels: []zigimg.color.Colorf32,
    };
};

pub fn init(allocator: std.mem.Allocator) Renderer {
    return Renderer{
        .allocator = allocator,
        .image_cache = &[_]?Texture.Image{},
    };
}

pub fn deinit(self: *Renderer) void {
    self.clearImageCache();
}

pub fn clearImageCache(self: *Renderer) void {
    if (self.image_cache.len == 0) return;

    for (self.image_cache) |image| if (image) |img| self.allocator.free(img.pixels);

    self.allocator.free(self.image_cache);
    self.image_cache = &[_]?Texture.Image{};
}

pub fn renderGltf(
    self: *Renderer,
    gltf: *Gltf,
    bin: []align(4) const u8,
    cv: *Canvas,
    config: Config,
) !void {
    if (gltf.data.scene == null or gltf.data.scenes.len == 0) {
        return error.NoScene;
    }
    const scene = gltf.data.scenes[gltf.data.scene.?];

    if (scene.nodes == null or scene.nodes.?.len == 0) {
        return error.NoNodes;
    }

    if (!config.wireframe and self.image_cache.len < gltf.data.images.len and gltf.data.images.len > 0) {
        if (self.image_cache.len > 0) {
            self.clearImageCache();
        }
        self.image_cache = try self.allocator.alloc(?Texture.Image, gltf.data.images.len);
        @memset(self.image_cache, null);
    }

    const world = Mat4.recompose(
        Vec3.fromSlice(&config.translation),
        Vec3.fromSlice(&config.rotation),
        Vec3.fromSlice(&config.scale),
    );

    const ctx = Context{
        .wireframe = config.wireframe,
        .canvas = cv,
        .gltf = gltf,
        .bin = bin,
        .world = world,
    };

    for (scene.nodes.?) |node_index| {
        try self.renderNode(ctx, node_index);
    }
}

fn renderNode(
    self: *Renderer,
    ctx: Context,
    node_index: usize,
) !void {
    const node = ctx.gltf.data.nodes[node_index];

    const object_model: Mat4 = .{ .data = Gltf.getGlobalTransform(&ctx.gltf.data, node) };

    if (node.mesh) |idx| {
        try self.renderMesh(ctx, idx, object_model);
    }

    for (node.children) |childNode| {
        try self.renderNode(ctx, childNode);
    }
}

fn renderMesh(
    self: *Renderer,
    ctx: Context,
    mesh_index: usize,
    object_model: Mat4,
) !void {
    const mesh = ctx.gltf.data.meshes[mesh_index];

    const global_model = ctx.world.mul(object_model);
    var ctx_copy = ctx;
    ctx_copy.world = global_model;

    for (mesh.primitives) |primitive| {
        try self.renderPrimitive(ctx_copy, primitive);
    }
}

fn renderPrimitive(self: *Renderer, ctx: Context, primitive: Gltf.Primitive) !void {
    const gltf = ctx.gltf;
    const attr = try helpers.getAttributes(self.allocator, ctx, primitive.attributes);
    const positions = attr.positions;
    const texcoords = attr.texcoords;
    defer self.allocator.free(positions);
    defer self.allocator.free(texcoords);

    const material = if (primitive.material) |material_idx| gltf.data.materials[material_idx] else return error.NoMaterial;
    const col_factor = material.metallic_roughness.base_color_factor;

    const t_img = if (ctx.wireframe) null else blk: {
        const texture_info = material.metallic_roughness.base_color_texture orelse break :blk null;
        const img_idx = gltf.data.textures[texture_info.index].source orelse break :blk null;
        if (self.image_cache[img_idx]) |cached| break :blk cached;
        if (try helpers.getImage(self.allocator, gltf, img_idx)) |new_img| {
            self.image_cache[img_idx] = new_img;
            break :blk new_img;
        } else break :blk null;
    };
    const texture = Texture{
        .color_factor = col_factor,
        .image = t_img,
    };

    if (primitive.indices == null) {
        var i: usize = 0;
        while (i + 2 < positions.len) : (i += 3) {
            const coords = if (i + 2 < texcoords.len) texcoords[i .. i + 3] else &[_]Vec2{Vec2.zero()} ** 3;
            self.renderTriangle(
                ctx,
                .{
                    .p0 = .{ .vec = positions[i], .uv = coords[0] },
                    .p1 = .{ .vec = positions[i + 1], .uv = coords[1] },
                    .p2 = .{ .vec = positions[i + 2], .uv = coords[2] },
                    .texture = texture,
                },
            );
        }
        return;
    }

    const idx = primitive.indices.?;
    const indices_accessor = gltf.data.accessors[idx];
    switch (indices_accessor.component_type) {
        inline .unsigned_byte, .unsigned_short, .unsigned_integer => |component_type| {
            const IndexType = switch (component_type) {
                .unsigned_byte => u8,
                .unsigned_short => u16,
                .unsigned_integer => u32,
                else => unreachable,
            };
            var it = indices_accessor.iterator(IndexType, gltf, ctx.bin);

            while (true) {
                const idx0 = if (it.next()) |v| v[0] else break;
                const idx1 = if (it.next()) |v| v[0] else break;
                const idx2 = if (it.next()) |v| v[0] else break;

                const coords: [3]Vec2 = if (@max(idx0, idx1, idx2) < texcoords.len) .{
                    texcoords[idx0],
                    texcoords[idx1],
                    texcoords[idx2],
                } else .{Vec2.zero()} ** 3;

                self.renderTriangle(
                    ctx,
                    .{
                        .p0 = .{ .vec = positions[idx0], .uv = coords[0] },
                        .p1 = .{ .vec = positions[idx1], .uv = coords[1] },
                        .p2 = .{ .vec = positions[idx2], .uv = coords[2] },
                        .texture = texture,
                    },
                );
            }
        },
        else => return,
    }
}

fn renderTriangle(self: *Renderer, ctx: Context, triangle: Triangle) void {
    if (triangle.p0.vec.z() < CLIP_Z or triangle.p1.vec.z() < CLIP_Z or triangle.p2.vec.z() < CLIP_Z)
        return;

    const cv = ctx.canvas;

    const pa = Pixel.fromVec3(triangle.p0.vec, cv.width, cv.height);
    const pb = Pixel.fromVec3(triangle.p1.vec, cv.width, cv.height);
    const pc = Pixel.fromVec3(triangle.p2.vec, cv.width, cv.height);

    if (cv.inBounds(pa) or cv.inBounds(pb) or cv.inBounds(pc)) {
        if (ctx.wireframe) {
            cv.drawTriangle(pa, pb, pc, Color.white);
        } else {
            self.fillTriangle(
                cv,
                triangle,
            );
        }
    }
}

fn fillTriangle(
    _: *Renderer,
    cv: *Canvas,
    triangle: Triangle,
) void {
    var ordered = [_]Triangle.Point{ triangle.p0, triangle.p1, triangle.p2 };
    std.sort.block(Triangle.Point, &ordered, cv, struct {
        pub fn lessThan(canvas: *Canvas, pa: Triangle.Point, pb: Triangle.Point) bool {
            const pxa = Pixel.fromVec3(pa.vec, canvas.width, canvas.height);
            const pxb = Pixel.fromVec3(pb.vec, canvas.width, canvas.height);

            return pxa.y < pxb.y;
        }
    }.lessThan);

    const p0 = Pixel.fromVec3(ordered[0].vec, cv.width, cv.height);
    const p1 = Pixel.fromVec3(ordered[1].vec, cv.width, cv.height);
    const p2 = Pixel.fromVec3(ordered[2].vec, cv.width, cv.height);

    const has_texture = triangle.texture.image != null;

    const uv0 = ordered[0].uv;
    const uv1 = ordered[1].uv;
    const uv2 = ordered[2].uv;

    var y = p0.y;
    while (y <= p2.y) : (y += 1) {
        const x012 = if (y < p1.y)
            interpolate(i32, p0.y, p0.x, p1.y, p1.x, y)
        else
            interpolate(i32, p1.y, p1.x, p2.y, p2.x, y);
        const x02 = interpolate(i32, p0.y, p0.x, p2.y, p2.x, y);

        // placeholder values
        const h012 = if (y < p1.y)
            interpolate(f32, p0.y, 1, p1.y, 1, y)
        else
            interpolate(f32, p1.y, 1, p2.y, 1, y);
        const h02 = interpolate(f32, p0.y, 1, p2.y, 1, y);

        const left = @min(x02, x012);
        const right = @max(x02, x012);
        const h_left = if (x02 < x012) h02 else h012;
        const h_right = if (x02 < x012) h012 else h02;

        // texture
        const uvx012 = if (!has_texture) 0 else if (y < p1.y)
            interpolate(f32, p0.y, uv0.x(), p1.y, uv1.x(), y)
        else
            interpolate(f32, p1.y, uv1.x(), p2.y, uv2.x(), y);
        const uvx02 = if (!has_texture) 0 else interpolate(f32, p0.y, uv0.x(), p2.y, uv2.x(), y);

        const uvy012 = if (!has_texture) 0 else if (y < p1.y)
            interpolate(f32, p0.y, uv0.y(), p1.y, uv1.y(), y)
        else
            interpolate(f32, p1.y, uv1.y(), p2.y, uv2.y(), y);
        const uvy02 = if (!has_texture) 0 else interpolate(f32, p0.y, uv0.y(), p2.y, uv2.y(), y);
        ///////////////

        var x = left;
        while (x <= right) : (x += 1) {
            const color: Color = if (!has_texture) .white else blk: {
                const ti = triangle.texture.image.?;
                const uv_x_value = interpolate(
                    f32,
                    left,
                    if (x02 < x012) uvx02 else uvx012,
                    right,
                    if (x02 < x012) uvx012 else uvx02,
                    x,
                );
                const uv_y_value = interpolate(
                    f32,
                    left,
                    if (x02 < x012) uvy02 else uvy012,
                    right,
                    if (x02 < x012) uvy012 else uvy02,
                    x,
                );
                const uv_x: usize = @trunc(@mod(uv_x_value, 1) * @as(f32, @floatFromInt(ti.width)));
                const uv_y: usize = @trunc(@mod(uv_y_value, 1) * @as(f32, @floatFromInt(ti.height)));

                const index = uv_y * ti.width + uv_x;

                if (index >= ti.pixels.len) break :blk .white;
                break :blk Color.white.mulVec4(@bitCast(ti.pixels[index]));
            };

            const h = interpolate(f32, left, h_left, right, h_right, x);
            cv.putPixel(.{ .x = x, .y = y }, color.scale(h).mulVec4(triangle.texture.color_factor));
        }
    }
}

test "deinit" {
    const allocator = std.testing.allocator;
    const file_buf = std.Io.Dir.cwd().readFileAllocOptions(
        std.testing.io,
        "zgltf/test-samples/box_binary_textured/BoxTextured.glb",
        allocator,
        .limited(512_000),
        .@"4",
        null,
    ) catch unreachable;
    defer allocator.free(file_buf);

    var gltf = Gltf.init(allocator);
    defer gltf.deinit();

    gltf.parse(file_buf) catch unreachable;

    var renderer = Renderer.init(allocator);

    var cv = Canvas.init(allocator, 50, 50) catch unreachable;
    defer cv.deinit(allocator);

    renderer.renderGltf(&gltf, gltf.glb_binary.?, &cv, .{}) catch unreachable;

    renderer.deinit();
}

test "fillTriangle" {
    var cv = Canvas.init(std.testing.allocator, 10, 10) catch unreachable;
    defer cv.deinit(std.testing.allocator);
    var renderer = Renderer.init(std.testing.allocator);

    const c0 = Color.transparent;
    const c1 = Color.new(0xFF, 0, 0, 0xFF);
    const c2 = Color.new(0, 0xFF, 0, 0xFF);

    const t1: Triangle = .{
        .p0 = .{
            .vec = .new(-0.8, 0.6, 1),
            .uv = .zero(),
        },
        .p1 = .{
            .vec = .new(-0.8, -0.6, 1),
            .uv = .zero(),
        },
        .p2 = .{
            .vec = .new(0.5, -0.6, 1),
            .uv = .zero(),
        },
        .texture = .{
            .color_factor = .{ 1, 0, 0, 1 },
            .image = null,
        },
    };

    const t2: Triangle = .{
        .p0 = .{
            .vec = .new(-0.6, 0.8, 1),
            .uv = .zero(),
        },
        .p1 = .{
            .vec = .new(0.6, 0.8, 1),
            .uv = .zero(),
        },
        .p2 = .{
            .vec = .new(0.6, -0.4, 1),
            .uv = .zero(),
        },
        .texture = .{
            .color_factor = .{ 0, 1, 0, 1 },
            .image = null,
        },
    };

    renderer.fillTriangle(&cv, t1);
    renderer.fillTriangle(&cv, t2);

    try std.testing.expectEqualSlices(u8, cv.asBytes(), std.mem.sliceAsBytes(&[_]Color{
        c0, c0, c0, c0, c0, c0, c0, c0, c0, c0,
        c0, c0, c2, c2, c2, c2, c2, c2, c2, c0,
        c0, c1, c0, c2, c2, c2, c2, c2, c2, c0,
        c0, c1, c1, c0, c2, c2, c2, c2, c2, c0,
        c0, c1, c1, c1, c0, c2, c2, c2, c2, c0,
        c0, c1, c1, c1, c1, c0, c2, c2, c2, c0,
        c0, c1, c1, c1, c1, c1, c0, c2, c2, c0,
        c0, c1, c1, c1, c1, c1, c1, c0, c2, c0,
        c0, c1, c1, c1, c1, c1, c1, c1, c0, c0,
        c0, c0, c0, c0, c0, c0, c0, c0, c0, c0,
    }));

    const t3: Triangle = .{
        .p0 = .{
            .vec = .new(-1, 1, 1),
            .uv = .zero(),
        },
        .p1 = .{
            .vec = .new(0.8, 1, 1),
            .uv = .zero(),
        },
        .p2 = .{
            .vec = .new(0, 0, 1),
            .uv = .zero(),
        },
        .texture = .{
            .color_factor = .{ 1, 0, 0, 1 },
            .image = null,
        },
    };

    const t4: Triangle = .{
        .p0 = .{
            .vec = .new(-1, -0.8, 1),
            .uv = .zero(),
        },
        .p1 = .{
            .vec = .new(0, -0.8, 1),
            .uv = .zero(),
        },
        .p2 = .{
            .vec = .new(-0.6, -0.4, 1),
            .uv = .zero(),
        },
        .texture = .{
            .color_factor = .{ 0, 1, 0, 1 },
            .image = null,
        },
    };

    cv.clear();
    renderer.fillTriangle(&cv, t3);
    renderer.fillTriangle(&cv, t4);

    try std.testing.expectEqualSlices(u8, cv.asBytes(), std.mem.sliceAsBytes(&[_]Color{
        c1, c1, c1, c1, c1, c1, c1, c1, c1, c1,
        c0, c1, c1, c1, c1, c1, c1, c1, c1, c0,
        c0, c0, c1, c1, c1, c1, c1, c1, c0, c0,
        c0, c0, c0, c1, c1, c1, c1, c1, c0, c0,
        c0, c0, c0, c0, c1, c1, c1, c0, c0, c0,
        c0, c0, c0, c0, c0, c1, c0, c0, c0, c0,
        c0, c0, c0, c0, c0, c0, c0, c0, c0, c0,
        c0, c0, c2, c0, c0, c0, c0, c0, c0, c0,
        c0, c2, c2, c2, c0, c0, c0, c0, c0, c0,
        c2, c2, c2, c2, c2, c2, c0, c0, c0, c0,
    }));
}
