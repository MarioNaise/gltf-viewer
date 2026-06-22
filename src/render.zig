const std = @import("std");
const Gltf = @import("zgltf");
const Framebuffer = @import("framebuffer.zig");
const Vec3 = [3]f32;

// https://www.youtube.com/watch?v=qjWkNZ0SXfo
pub fn renderGltf(
    gltf: *Gltf,
    fb: *Framebuffer,
    bin: []align(4) const u8,
    distance: f32,
    rotY: f32,
) !void {
    const w: f32 = @floatFromInt(fb.width);
    const h: f32 = @floatFromInt(fb.height);
    const light_green = .{ 100, 255, 100, 255 };
    for (gltf.data.meshes) |mesh| {
        for (mesh.primitives) |prim| {
            for (prim.attributes) |attr| {
                switch (attr) {
                    .position => |idx| {
                        const accessor = gltf.data.accessors[idx];
                        var iter = accessor.iterator(f32, gltf, bin);
                        while (iter.next()) |v| {
                            if (v.len != 3) {
                                continue;
                            }
                            const vt = rotateY(.{ v[0], v[1], v[2] }, rotY);
                            const pr = project(.{ vt[0], vt[1], vt[2] + distance });
                            const x: i32 = @intFromFloat((pr[0] + 1) / 2 * w);
                            const y: i32 = @intFromFloat((1 - (pr[1] + 1) / 2) * h);

                            fb.putFatPixel(.{ x, y }, light_green);
                        }
                    },
                    else => {},
                }
            }
        }
    }
}

fn project(v: Vec3) [2]f32 {
    if (v[2] == 0 or v[2] < 0.01) {
        return .{ -1, -1 };
    }
    return .{
        v[0] / v[2],
        v[1] / v[2],
    };
}

fn rotateY(v: Vec3, angle: f32) Vec3 {
    const cos_a = @cos(angle);
    const sin_a = @sin(angle);
    return .{
        v[0] * cos_a - v[2] * sin_a,
        v[1],
        v[0] * sin_a + v[2] * cos_a,
    };
}
