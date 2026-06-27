const std = @import("std");
const Gltf = @import("zgltf");
const Framebuffer = @import("Framebuffer.zig");
const math = @import("math.zig");
const Renderer = @This();

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const NormalizedCoordinate = [2]f32;

allocator: std.mem.Allocator,

const Config = struct {
    scale: Vec3 = .{ 1, 1, 1 },
    translation: Vec3 = .{ 0, 0, 0 },
    rotation: Vec3 = .{ 0, 0, 0 },
};

pub fn init(allocator: std.mem.Allocator) Renderer {
    return Renderer{
        .allocator = allocator,
    };
}

pub fn renderGltf(
    self: *Renderer,
    gltf: *Gltf,
    fb: *Framebuffer,
    config: Config,
) !void {
    if (gltf.data.scene == null or gltf.data.scenes.len == 0) {
        return error.NoScene;
    }
    const scene = gltf.data.scenes[gltf.data.scene.?];

    if (scene.nodes == null or scene.nodes.?.len == 0) {
        return error.NoNodes;
    }

    const world = math.composeMat(
        config.translation,
        math.quatFromVec(config.rotation),
        config.scale,
    );
    for (scene.nodes.?) |node_index| {
        try self.renderNode(node_index, gltf, fb, world);
    }
}

fn renderNode(
    self: *Renderer,
    node_index: usize,
    gltf: *Gltf,
    fb: *Framebuffer,
    world: Mat4,
) !void {
    const node = gltf.data.nodes[node_index];

    for (node.children) |childNode| {
        try self.renderNode(childNode, gltf, fb, world);
    }

    if (node.mesh != null) {
        try self.renderMesh(node_index, gltf, fb, world);
    }
}

fn renderMesh(
    self: *Renderer,
    node_index: usize,
    gltf: *Gltf,
    fb: *Framebuffer,
    world: Mat4,
) !void {
    const node = gltf.data.nodes[node_index];
    const object_model = Gltf.getGlobalTransform(&gltf.data, node);
    const mesh = gltf.data.meshes[node.mesh.?];

    const global_model = math.matMul(world, object_model);

    for (mesh.primitives) |primitive| {
        const idx = blk: {
            for (primitive.attributes) |attr| {
                switch (attr) {
                    .position => |idx| {
                        break :blk idx;
                    },
                    else => {},
                }
            }
            continue;
        };

        var positions = std.ArrayList(Vec3).empty;
        defer positions.deinit(self.allocator);

        const accessor = gltf.data.accessors[idx];
        var raw_positions_it = accessor.iterator(f32, gltf, gltf.glb_binary.?);
        while (raw_positions_it.next()) |pos| {
            try positions.append(self.allocator, math.transformVector(
                global_model,
                .{ pos[0], pos[1], pos[2] },
            ));
        }

        const base_color = if (primitive.material) |material_idx| blk: {
            const material = gltf.data.materials[material_idx];
            break :blk Framebuffer.Color{
                @intFromFloat(material.metallic_roughness.base_color_factor[0] * 100),
                @intFromFloat(material.metallic_roughness.base_color_factor[1] * 255),
                @intFromFloat(material.metallic_roughness.base_color_factor[2] * 100),
                @intFromFloat(material.metallic_roughness.base_color_factor[3] * 255),
            };
        } else Framebuffer.Color{ 255, 255, 255, 255 };

        if (primitive.indices) |indices_accessor_index| {
            const indices_accessor = gltf.data.accessors[indices_accessor_index];
            switch (indices_accessor.component_type) {
                .unsigned_byte => try self.drawIndices(u8, indices_accessor, gltf, positions.items, fb, base_color),
                .unsigned_short => try self.drawIndices(u16, indices_accessor, gltf, positions.items, fb, base_color),
                .unsigned_integer => try self.drawIndices(u32, indices_accessor, gltf, positions.items, fb, base_color),
                else => {
                    std.debug.print("Unsupported index component type. {}\n", .{indices_accessor.component_type});
                },
            }
        } else {
            var i: usize = 0;
            while (i + 2 < positions.items.len) : (i += 3) {
                self.drawTriangle(
                    positions.items[i],
                    positions.items[i + 1],
                    positions.items[i + 2],
                    fb,
                    base_color,
                );
            }
        }
    }
}

fn drawIndices(
    self: *Renderer,
    comptime T: type,
    accessor: Gltf.Accessor,
    gltf: *Gltf,
    positions: []const Vec3,
    fb: *Framebuffer,
    color: Framebuffer.Color,
) !void {
    const indices = try gltf.getDataFromBufferView(
        T,
        self.allocator,
        accessor,
        gltf.glb_binary.?,
    );
    defer self.allocator.free(indices);

    var i: usize = 0;
    while (i + 2 < indices.len) : (i += 3) {
        self.drawTriangle(
            positions[indices[i]],
            positions[indices[i + 1]],
            positions[indices[i + 2]],
            fb,
            color,
        );
    }
}

const CLIP_Z: f32 = 0.1;

fn drawTriangle(_: *Renderer, va: Vec3, vb: Vec3, vc: Vec3, fb: *Framebuffer, color: Framebuffer.Color) void {
    const w: f32 = @floatFromInt(fb.width);
    const h: f32 = @floatFromInt(fb.height);

    const a_ok = va[2] > CLIP_Z;
    const b_ok = vb[2] > CLIP_Z;
    const c_ok = vc[2] > CLIP_Z;

    const a = if (a_ok) screen(project(va), w, h) else null;
    const b = if (b_ok) screen(project(vb), w, h) else null;
    const c = if (c_ok) screen(project(vc), w, h) else null;

    if (a_ok and b_ok) fb.drawLine(a.?, b.?, color);
    if (b_ok and c_ok) fb.drawLine(b.?, c.?, color);
    if (c_ok and a_ok) fb.drawLine(c.?, a.?, color);
}

/// Maps normalized coordinates to screen coordinates
/// e.g. -1, -1, 1, 1 -> 0, 0, width, height
fn screen(p: NormalizedCoordinate, width: f32, height: f32) Framebuffer.Pixel {
    return .{
        @trunc((p[0] + 1) / 2 * width),
        @trunc((1 - (p[1] + 1) / 2) * height),
    };
}

// https://www.youtube.com/watch?v=qjWkNZ0SXfo
/// Maps 3D coordinates to 2D screen coordinates using perspective projection
/// x' = x / z, y' = y / z
/// Does not check for z == 0
/// Does not perform clipping
fn project(v: Vec3) NormalizedCoordinate {
    return .{
        v[0] / v[2],
        v[1] / v[2],
    };
}
