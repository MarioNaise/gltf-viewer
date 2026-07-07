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
const lerp = helpers.lerp;

const Renderer = @This();

allocator: std.mem.Allocator,

const CLIP_Z: f32 = 1;

const Config = struct {
    scale: [3]f32 = .{ 1, 1, 1 },
    translation: [3]f32 = .{ 0, 0, 0 },
    rotation: [3]f32 = .{ 0, 0, 0 },
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
    };
}

pub fn renderGltf(
    self: *Renderer,
    gltf: *Gltf,
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

    const world = Mat4.recompose(
        Vec3.fromSlice(&config.translation),
        Vec3.fromSlice(&config.rotation),
        Vec3.fromSlice(&config.scale),
    );
    for (scene.nodes.?) |node_index| {
        try self.renderNode(node_index, gltf, cv, world);
    }
}

fn renderNode(
    self: *Renderer,
    node_index: usize,
    gltf: *Gltf,
    cv: *Canvas,
    world: Mat4,
) !void {
    const node = gltf.data.nodes[node_index];

    for (node.children) |childNode| {
        try self.renderNode(childNode, gltf, cv, world);
    }

    if (node.mesh != null) {
        try self.renderMesh(node_index, gltf, cv, world);
    }
}

fn renderMesh(
    self: *Renderer,
    node_index: usize,
    gltf: *Gltf,
    cv: *Canvas,
    world: Mat4,
) !void {
    const node = gltf.data.nodes[node_index];
    const object_model = Mat4.fromSlice(&@bitCast(Gltf.getGlobalTransform(&gltf.data, node)));
    const mesh = gltf.data.meshes[node.mesh.?];

    const global_model = Mat4.mul(world, object_model);

    for (mesh.primitives) |primitive| {
        try self.renderPrimitive(gltf, cv, global_model, primitive);
    }
}

fn renderPrimitive(self: *Renderer, gltf: *Gltf, cv: *Canvas, world: Mat4, primitive: Gltf.Primitive) !void {
    const attr = try helpers.getAttributes(self.allocator, gltf, world, primitive.attributes);
    const positions = attr.positions;
    const texcoords = attr.texcoords;
    defer self.allocator.free(positions);
    defer self.allocator.free(texcoords);

    const material = if (primitive.material) |material_idx| gltf.data.materials[material_idx] else return error.NoMaterial;
    const col_factor = material.metallic_roughness.base_color_factor;

    const t_img = try helpers.getTextureImage(self.allocator, gltf, material);
    defer if (t_img) |img| self.allocator.free(img.pixels);

    if (primitive.indices == null) {
        var i: usize = 0;
        while (i + 2 < positions.len) : (i += 3) {
            const coords = if (i + 2 < texcoords.len) texcoords[i .. i + 3] else &[_]Vec2{Vec2.zero()} ** 3;
            self.renderTriangle(
                cv,
                .{
                    .p0 = .{ .vec = positions[i], .uv = coords[0] },
                    .p1 = .{ .vec = positions[i + 1], .uv = coords[1] },
                    .p2 = .{ .vec = positions[i + 2], .uv = coords[2] },
                    .texture = .{
                        .color_factor = col_factor,
                        .image = t_img,
                    },
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
            var it = indices_accessor.iterator(IndexType, gltf, gltf.glb_binary.?);

            while (true) {
                const idx0 = if (it.next()) |v| v[0] else break;
                const idx1 = if (it.next()) |v| v[0] else break;
                const idx2 = if (it.next()) |v| v[0] else break;

                const coords = if (texcoords.len >= @max(idx0, idx1, idx2)) &[_]Vec2{
                    texcoords[idx0],
                    texcoords[idx1],
                    texcoords[idx2],
                } else &[_]Vec2{Vec2.zero()} ** 3;

                self.renderTriangle(
                    cv,
                    .{
                        .p0 = .{ .vec = positions[idx0], .uv = coords[0] },
                        .p1 = .{ .vec = positions[idx1], .uv = coords[1] },
                        .p2 = .{ .vec = positions[idx2], .uv = coords[2] },
                        .texture = .{
                            .color_factor = col_factor,
                            .image = t_img,
                        },
                    },
                );
            }
        },
        else => return,
    }
}

fn renderTriangle(self: *Renderer, cv: *Canvas, triangle: Triangle) void {
    if (triangle.p0.vec.z() < CLIP_Z or triangle.p1.vec.z() < CLIP_Z or triangle.p2.vec.z() < CLIP_Z)
        return;

    const pa = Pixel.fromVec3(triangle.p0.vec, cv.width, cv.height);
    const pb = Pixel.fromVec3(triangle.p1.vec, cv.width, cv.height);
    const pc = Pixel.fromVec3(triangle.p2.vec, cv.width, cv.height);

    if (cv.inBounds(pa) or cv.inBounds(pb) or cv.inBounds(pc)) {
        self.fillTriangle(
            cv,
            triangle,
        );
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

    var x_it_0 = lerp(i32, p0.y, p0.x, p1.y, p1.x);
    var x_it_1 = lerp(i32, p1.y, p1.x, p2.y, p2.x);
    var x_it_2 = lerp(i32, p0.y, p0.x, p2.y, p2.x);

    // placeholder values
    var h_it_0 = lerp(f32, p0.y, 1, p1.y, 1);
    var h_it_1 = lerp(f32, p1.y, 1, p2.y, 1);
    var h_it_2 = lerp(f32, p0.y, 1, p2.y, 1);

    // texture
    const has_texture = triangle.texture.image != null;

    const uv0 = ordered[0].uv;
    const uv1 = ordered[1].uv;
    const uv2 = ordered[2].uv;

    var uv_x_it_0 = if (has_texture) lerp(f32, p0.y, uv0.x(), p1.y, uv1.x()) else null;
    var uv_x_it_1 = if (has_texture) lerp(f32, p1.y, uv1.x(), p2.y, uv2.x()) else null;
    var uv_x_it_2 = if (has_texture) lerp(f32, p0.y, uv0.x(), p2.y, uv2.x()) else null;
    var uv_y_it_0 = if (has_texture) lerp(f32, p0.y, uv0.y(), p1.y, uv1.y()) else null;
    var uv_y_it_1 = if (has_texture) lerp(f32, p1.y, uv1.y(), p2.y, uv2.y()) else null;
    var uv_y_it_2 = if (has_texture) lerp(f32, p0.y, uv0.y(), p2.y, uv2.y()) else null;
    ///////////////

    var i: usize = 0;
    while (true) : (i += 1) {
        const x012 = blk: {
            if (x_it_0.peekAt(1) == null)
                break :blk x_it_1.next() orelse break;
            break :blk x_it_0.next() orelse break;
        };
        const x02 = x_it_2.next() orelse break;

        const h012 = blk: {
            if (h_it_0.peekAt(1) == null)
                break :blk h_it_1.next() orelse break;
            break :blk h_it_0.next() orelse break;
        };
        const h02 = h_it_2.next() orelse break;

        const y = p0.y + @as(i32, @intCast(i));

        var left = @min(x02, x012);
        const right = @max(x02, x012);
        const h_left = if (x02 < x012) h02 else h012;
        const h_right = if (x02 < x012) h012 else h02;

        var h_segment = lerp(
            f32,
            left,
            h_left,
            right,
            h_right,
        );

        // texture
        const uvx012 = if (!has_texture) 0 else blk: {
            if (uv_x_it_0.?.peekAt(1) == null)
                break :blk uv_x_it_1.?.next() orelse break;
            break :blk uv_x_it_0.?.next() orelse break;
        };
        const uvx02 = if (!has_texture) 0 else uv_x_it_2.?.next() orelse break;

        var uvx_segment = if (!has_texture) null else lerp(
            f32,
            left,
            if (x02 < x012) uvx02 else uvx012,
            right,
            if (x02 < x012) uvx012 else uvx02,
        );

        const uvy012 = if (!has_texture) 0 else blk: {
            if (uv_y_it_0.?.peekAt(1) == null)
                break :blk uv_y_it_1.?.next() orelse break;
            break :blk uv_y_it_0.?.next() orelse break;
        };
        const uvy02 = if (!has_texture) 0 else uv_y_it_2.?.next() orelse break;

        var uvy_segment = if (!has_texture) null else lerp(
            f32,
            left,
            if (x02 < x012) uvy02 else uvy012,
            right,
            if (x02 < x012) uvy012 else uvy02,
        );
        ///////////////

        while (left <= right) : (left += 1) {
            const color = if (!has_texture) Color.white else blk: {
                const ti = triangle.texture.image.?;
                const uv_x: usize = @trunc(@mod(uvx_segment.?.next() orelse break, 1) * @as(f32, @floatFromInt(ti.width)));
                const uv_y: usize = @trunc(@mod(uvy_segment.?.next() orelse break, 1) * @as(f32, @floatFromInt(ti.height)));

                const index = uv_y * ti.width + uv_x;

                if (index >= ti.pixels.len) break :blk Color.white;
                break :blk Color.white.mulVec4(@bitCast(ti.pixels[index]));
            };

            cv.putPixel(.{ .x = left, .y = y }, color.scale(h_segment.next() orelse 1).mulVec4(triangle.texture.color_factor));
        }
    }
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
            .vec = Vec3.new(-0.8, 0.6, 1),
            .uv = Vec2.zero(),
        },
        .p1 = .{
            .vec = Vec3.new(-0.8, -0.6, 1),
            .uv = Vec2.zero(),
        },
        .p2 = .{
            .vec = Vec3.new(0.5, -0.6, 1),
            .uv = Vec2.zero(),
        },
        .texture = .{
            .color_factor = .{ 1, 0, 0, 1 },
            .image = null,
        },
    };

    const t2: Triangle = .{
        .p0 = .{
            .vec = Vec3.new(-0.6, 0.8, 1),
            .uv = Vec2.zero(),
        },
        .p1 = .{
            .vec = Vec3.new(0.6, 0.8, 1),
            .uv = Vec2.zero(),
        },
        .p2 = .{
            .vec = Vec3.new(0.6, -0.4, 1),
            .uv = Vec2.zero(),
        },
        .texture = .{
            .color_factor = .{ 0, 1, 0, 1 },
            .image = null,
        },
    };

    renderer.fillTriangle(&cv, t1);
    renderer.fillTriangle(&cv, t2);

    try std.testing.expect(std.mem.eql(u8, cv.asBytes(), std.mem.sliceAsBytes(&[_]Color{
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
    })));

    const t3: Triangle = .{
        .p0 = .{
            .vec = Vec3.new(-1, 1, 1),
            .uv = Vec2.zero(),
        },
        .p1 = .{
            .vec = Vec3.new(0.8, 1, 1),
            .uv = Vec2.zero(),
        },
        .p2 = .{
            .vec = Vec3.new(0, 0, 1),
            .uv = Vec2.zero(),
        },
        .texture = .{
            .color_factor = .{ 1, 0, 0, 1 },
            .image = null,
        },
    };

    const t4: Triangle = .{
        .p0 = .{
            .vec = Vec3.new(-1, -0.8, 1),
            .uv = Vec2.zero(),
        },
        .p1 = .{
            .vec = Vec3.new(0, -0.8, 1),
            .uv = Vec2.zero(),
        },
        .p2 = .{
            .vec = Vec3.new(-0.6, -0.4, 1),
            .uv = Vec2.zero(),
        },
        .texture = .{
            .color_factor = .{ 0, 1, 0, 1 },
            .image = null,
        },
    };

    cv.clear();
    renderer.fillTriangle(&cv, t3);
    renderer.fillTriangle(&cv, t4);

    try std.testing.expect(std.mem.eql(u8, cv.asBytes(), std.mem.sliceAsBytes(&[_]Color{
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
    })));
}
