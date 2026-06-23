const std = @import("std");
const Gltf = @import("zgltf");
const Framebuffer = @import("framebuffer.zig");
const Vec3 = [3]f32;

pub fn renderGltf(
    gltf: *Gltf,
    fb: *Framebuffer,
    distance: f32,
    rotY: f32,
) !void {
    if (gltf.data.scene == null or gltf.data.scenes.len == 0) {
        return error.NoScene;
    }
    const scene = gltf.data.scenes[gltf.data.scene.?];

    if (scene.nodes == null or scene.nodes.?.len == 0) {
        return error.NoNodes;
    }

    for (scene.nodes.?) |node_index| {
        try renderNode(gltf, node_index, fb, distance, rotY);
    }
}

fn renderNode(gltf: *Gltf, node_index: usize, fb: *Framebuffer, distance: f32, rotY: f32) !void {
    const node = gltf.data.nodes[node_index];
    const w: f32 = @floatFromInt(fb.width);
    const h: f32 = @floatFromInt(fb.height);

    if (node.mesh != null) {
        const model = Gltf.getGlobalTransform(&gltf.data, node);
        const mesh = gltf.data.meshes[node.mesh.?];

        for (mesh.primitives) |primitive| {
            for (primitive.attributes) |attr| {
                switch (attr) {
                    .position => |idx| {
                        const indices_accessor = gltf.data.accessors[idx];
                        var it = indices_accessor.iterator(f32, gltf, gltf.glb_binary.?);
                        while (it.next()) |pos| {
                            const v = Vec3{ pos[0], pos[1], pos[2] };
                            const world = multMat4(model, v);
                            const world_rotated = rotateY(world, rotY);
                            const pr = project(.{ world_rotated[0], world_rotated[1], world_rotated[2] + distance });
                            const pixel_coords = screen(pr, w, h);

                            fb.putPixel(.{ pixel_coords[0], pixel_coords[1] }, .{ 100, 255, 100, 255 });
                        }
                    },
                    else => {},
                }
            }
        }
    }
    for (node.children) |childNode| {
        try renderNode(gltf, childNode, fb, distance, rotY);
    }
}

/// Maps normalized coordinates to screen coordinates
/// e.g. -1, -1, 1, 1 -> 0, 0, width, height
fn screen(p: [2]f32, width: f32, height: f32) [2]i32 {
    return .{
        @intFromFloat((p[0] + 1) / 2 * width),
        @intFromFloat((1 - (p[1] + 1) / 2) * height),
    };
}

// https://www.youtube.com/watch?v=qjWkNZ0SXfo
/// Maps 3D coordinates to 2D screen coordinates using perspective projection
/// x' = x / z, y' = y / z
fn project(v: Vec3) [2]f32 {
    if (v[2] == 0 or v[2] < 0.01) {
        return .{ -1, -1 };
    }
    return .{
        v[0] / v[2],
        v[1] / v[2],
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
fn multMat4(model: [4][4]f32, p: Vec3) Vec3 {
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
