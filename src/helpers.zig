const std = @import("std");

const Gltf = @import("zgltf");
const zalgebra = @import("zalgebra");
const Vec2 = zalgebra.Vec2;
const Vec3 = zalgebra.Vec3;
const zigimg = @import("zigimg");

const Renderer = @import("Renderer.zig");
const Image = Renderer.Texture.Image;
const Context = Renderer.Context;

pub fn getAttributes(allocator: std.mem.Allocator, ctx: Context, attributes: []Gltf.Attribute) !struct {
    positions: []Vec3,
    texcoords: []Vec2,
} {
    var positions = std.ArrayList(Vec3).empty;
    var texcoords = std.ArrayList(Vec2).empty;

    const gltf = ctx.gltf;
    for (attributes) |attr| {
        switch (attr) {
            .position => |idx| {
                const accessor = gltf.data.accessors[idx];
                var raw_positions_it = accessor.iterator(f32, gltf, ctx.bin);
                while (raw_positions_it.next()) |pos| {
                    try positions.append(allocator, ctx.world.mulByVec3(.fromSlice(pos[0..3])));
                }
            },
            .texcoord => |idx| {
                const accessor = gltf.data.accessors[idx];
                var texc_it = accessor.iterator(f32, gltf, ctx.bin);
                while (texc_it.next()) |texc| {
                    try texcoords.append(allocator, .new(texc[0], texc[1]));
                }
            },
            else => {},
        }
    }
    return .{
        .positions = try positions.toOwnedSlice(allocator),
        .texcoords = try texcoords.toOwnedSlice(allocator),
    };
}

pub fn getImage(allocator: std.mem.Allocator, gltf: *Gltf, idx: usize) !?Image {
    const img = gltf.data.images[idx];
    var image = if (img.data) |data| try zigimg.Image.fromMemory(allocator, data) else return null;

    defer image.deinit(allocator);

    var pixels = std.ArrayList(zigimg.color.Colorf32).empty;

    var imit = image.iterator();
    while (imit.next()) |col| {
        try pixels.append(allocator, col);
    }

    return Image{
        .width = image.width,
        .height = image.height,
        .pixels = try pixels.toOwnedSlice(allocator),
    };
}

/// Linear interpolation between two values based on indices *i_0* and *i_1*.
/// Returns the interpolated value at *position*.
pub fn interpolate(comptime T: type, i_0: i32, d0: T, i_1: i32, d1: T, position: i32) T {
    const is_float = comptime switch (@typeInfo(T)) {
        .int => false,
        .float => true,
        else => @compileError("Unsupported type for interpolation"),
    };

    if (i_0 == i_1) {
        return d0;
    }

    const delta_i = @as(if (is_float) T else f32, @floatFromInt(i_1 - i_0));
    const delta_d = if (is_float) @as(T, d1 - d0) else @as(f32, @floatFromInt(d1 - d0));
    const offset = @as(if (is_float) T else f32, @floatFromInt(position - i_0));
    const d = if (is_float) d0 else @as(f32, @floatFromInt(d0));
    const a = delta_d / delta_i;

    return if (is_float) @mulAdd(T, a, offset, d) else @as(T, @round(@mulAdd(f32, a, offset, d)));
}

test "interpolate" {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(@as(i32, 0), interpolate(i32, 0, 0, 10, 100, 0));
    try expectEqual(@as(i32, 50), interpolate(i32, 0, 0, 10, 100, 5));
    try expectEqual(@as(i32, 100), interpolate(i32, 0, 0, 10, 100, 10));

    try expectEqual(@as(f32, 0.0), interpolate(f32, 0, 0.0, 5, 1.0, 0));
    try expectEqual(@as(f32, 0.4), interpolate(f32, 0, 0.0, 5, 1.0, 2));
    try expectEqual(@as(f32, 1.0), interpolate(f32, 0, 0.0, 5, 1.0, 5));
}
