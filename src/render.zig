const std = @import("std");
const Gltf = @import("zgltf");
const Framebuffer = @import("framebuffer.zig");

const Vec3 = [3]f32;
const Mat4 = [4][4]f32;
const NormalizedCoordinate = [2]f32;

const Config = struct {
    scale: f32,
    pos: Vec3,
    rot: Vec3,
};

pub fn renderGltf(
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

    for (scene.nodes.?) |node_index| {
        try renderNode(gltf, node_index, fb, config);
    }
}

fn renderNode(gltf: *Gltf, node_index: usize, fb: *Framebuffer, config: Config) !void {
    const node = gltf.data.nodes[node_index];

    for (node.children) |childNode| {
        try renderNode(gltf, childNode, fb, config);
    }

    if (node.mesh == null) {
        return;
    }

    const model = Gltf.getGlobalTransform(&gltf.data, node);
    const mesh = gltf.data.meshes[node.mesh.?];

    for (mesh.primitives) |primitive| {
        for (primitive.attributes) |attr| {
            switch (attr) {
                .position => |idx| {
                    const indices_accessor = gltf.data.accessors[idx];
                    var it = indices_accessor.iterator(f32, gltf, gltf.glb_binary.?);
                    while (it.next()) |pos| {
                        renderVector(
                            .{ pos[0], pos[1], pos[2] },
                            model,
                            fb,
                            config,
                        );
                    }
                },
                else => {},
            }
        }
    }
}

fn renderVector(v: Vec3, model: Mat4, fb: *Framebuffer, config: Config) void {
    const w: f32 = @floatFromInt(fb.width);
    const h: f32 = @floatFromInt(fb.height);

    const v_mult = multMat4(model, v);
    const v_rot_y = rotateY(v_mult, config.rot[1]);
    const v_rot = rotateX(v_rot_y, config.rot[0]);
    const projected = project(.{
        v_rot[0] * config.scale + config.pos[0],
        v_rot[1] * config.scale + config.pos[1],
        v_rot[2] * config.scale + config.pos[2],
    });
    const coords = screen(projected, w, h);
    fb.putPixel(coords, .{ 100, 255, 100, 255 });
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
fn project(v: Vec3) NormalizedCoordinate {
    const CLIPPING: f32 = 0.1;
    if (v[2] == 0 or v[2] < CLIPPING) {
        return .{ -1, -1 };
    }
    return .{
        v[0] / v[2],
        v[1] / v[2],
    };
}

/// Rotates a 3D vector around the X-axis by a given angle.
fn rotateX(v: Vec3, angle: f32) Vec3 {
    const cos_a = @cos(angle);
    const sin_a = @sin(angle);
    return .{
        v[0],
        v[1] * cos_a - v[2] * sin_a,
        v[1] * sin_a + v[2] * cos_a,
    };
}

/// Rotates a 3D vector around the Y-axis by a given angle.
fn rotateY(v: Vec3, angle: f32) Vec3 {
    const cos_a = @cos(angle);
    const sin_a = @sin(angle);
    return .{
        v[0] * cos_a - v[2] * sin_a,
        v[1],
        v[0] * sin_a + v[2] * cos_a,
    };
}

/// Multiplies a 4x4 matrix with a 3D vector, returning the transformed vector.
fn multMat4(model: Mat4, p: Vec3) Vec3 {
    const x =
        model[0][0] * p[0] +
        model[1][0] * p[1] +
        model[2][0] * p[2] +
        model[3][0];

    const y =
        model[0][1] * p[0] +
        model[1][1] * p[1] +
        model[2][1] * p[2] +
        model[3][1];

    const z =
        model[0][2] * p[0] +
        model[1][2] * p[1] +
        model[2][2] * p[2] +
        model[3][2];

    return .{ x, y, z };
}
