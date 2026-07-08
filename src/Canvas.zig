const std = @import("std");

const Vec3 = @import("zalgebra").Vec3;

const Color = @import("Color.zig");
const lerp = @import("helpers.zig").lerp;

const Canvas = @This();

width: usize,
height: usize,
rgba: []Color,

// Currently not used, but needed for depth buffering
pub const Coordinate = struct {
    x: f32,
    y: f32,
    z: f32,

    const Self = @This();

    // https://www.youtube.com/watch?v=qjWkNZ0SXfo
    /// Maps 3D coordinates to 2D screen coordinates using perspective projection
    /// x' = x / z, y' = y / z
    /// Does not check for z == 0
    /// Does not perform clipping
    pub fn fromVec3(v: Vec3) Self {
        return .{
            .x = v.x() / v.z(),
            .y = v.y() / v.z(),
            .z = v.z(),
        };
    }

    /// Maps normalized coordinates to screen coordinates
    /// -1, -1, 1, 1 -> -w/2, -h/2, w/2, h/2
    pub fn screen(self: Self, width: f32, height: f32) Pixel {
        return .{
            .x = @trunc(self.x * width >> 1),
            .y = @trunc(self.y * height >> 1),
        };
    }
};

pub const Pixel = struct {
    x: i32,
    y: i32,

    const Self = @This();

    /// Creates a Pixel from a Vec3 and the given *width* and *height*.
    pub fn fromVec3(v: Vec3, width: usize, height: usize) Pixel {
        const w: f32 = @floatFromInt(width);
        const h: f32 = @floatFromInt(height);

        return .{
            .x = @as(i32, @trunc(v.x() / v.z() * w)) >> 1,
            .y = @as(i32, @trunc(v.y() / v.z() * h)) >> 1,
        };
    }
};

/// Initializes a new Canvas with the given width and height.
/// Allocates an RGBA buffer and sets all pixels to transparent.
/// Minimum width and height is 2.
pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
    if (width < 2 or height < 2) return error.InvalidDimensions;

    const rgba = try allocator.alloc(Color, width * height);
    @memset(rgba, Color.transparent);

    return .{
        .width = width,
        .height = height,
        .rgba = rgba,
    };
}

/// Deinitializes the Canvas and frees the RGBA buffer.
pub fn deinit(self: *Canvas, allocator: std.mem.Allocator) void {
    std.debug.assert(self.rgba.len > 0);
    std.debug.assert(self.rgba.len == self.width * self.height);

    allocator.free(self.rgba);
}

/// Clears the Canvas by setting all pixels to transparent.
/// Does not deallocate the RGBA buffer.
pub fn clear(self: *Canvas) void {
    @memset(self.rgba, Color.transparent);
}

/// Checks if the given Pixel is within the bounds of the Canvas.
pub fn inBounds(self: Canvas, p: Pixel) bool {
    const max_width = @as(i32, @intCast(self.width >> 1));
    const max_height = @as(i32, @intCast(self.height >> 1));

    return (p.x < max_width and
        p.x >= -max_width and
        p.y <= max_height and
        p.y > -max_height);
}

/// Returns the RGBA buffer as a slice of bytes.
pub fn asBytes(self: Canvas) []u8 {
    return std.mem.sliceAsBytes(self.rgba);
}

pub fn drawTriangle(self: *Canvas, a: Pixel, b: Pixel, c: Pixel, color: Color) void {
    self.drawLine(a, b, color);
    self.drawLine(b, c, color);
    self.drawLine(c, a, color);
}

/// Draws a line from Pixel *a* to Pixel *b* with Color *c* using Bresenham's line algorithm.
pub fn drawLine(self: *Canvas, a: Pixel, b: Pixel, c: Color) void {
    var x0 = a.x;
    var y0 = a.y;

    const x1 = b.x;
    const y1 = b.y;

    const dx: i32 = @intCast(@abs(x1 - x0));
    const sx: i32 = if (x0 < x1) 1 else -1;

    const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
    const sy: i32 = if (y0 < y1) 1 else -1;

    var err = dx + dy;

    while (true) {
        self.putPixel(.{ .x = x0, .y = y0 }, c);

        const e2 = 2 * err;

        if (e2 >= dy) {
            if (x0 == x1) break;
            err += dy;
            x0 += sx;
        }

        if (e2 <= dx) {
            if (y0 == y1) break;
            err += dx;
            y0 += sy;
        }
    }
}

/// Writes Color *c* to the framebuffer at Pixel *a*.
/// min x = -width/2,     max x = width/2 - 1
/// min y = -heigt/2 + 1, max y = width/2
/// example: 10x10: x = -5..4, y = -4..5 with top left = -5,5
pub fn putPixel(self: *Canvas, p: Pixel, c: Color) void {
    if (!self.inBounds(p)) return;

    const max_width: i32 = @intCast(self.width >> 1);
    const max_height: i32 = @intCast(self.height >> 1);

    const idx = @as(usize, @intCast(max_height - p.y)) * self.width +
        @as(usize, @intCast(p.x + max_width));

    self.rgba[idx] = c;
}

/// Only for debugging, prints the canvas to stderr as a grid of u32 values
pub fn print(self: Canvas) void {
    for (0..self.height) |i| {
        for (i * self.width..(i + 1) * self.width) |j| {
            const col = std.mem.readInt(u32, &[_]u8{
                self.rgba[j].r,
                self.rgba[j].g,
                self.rgba[j].b,
                self.rgba[j].a,
            }, .big);
            std.debug.print("{x:0>8}, ", .{col});
        }
        std.debug.print("\n", .{});
    }
}

test "init" {
    try std.testing.expectError(error.InvalidDimensions, Canvas.init(std.testing.allocator, 1, 1));
}

test "drawTriangle" {
    const expect = std.testing.expect;

    var cv = Canvas.init(std.testing.allocator, 10, 10) catch unreachable;
    defer cv.deinit(std.testing.allocator);

    const c0 = Color.transparent;
    const c1 = Color.new(0, 0, 0, 1);
    const c2 = Color.new(0, 0, 0, 2);

    try expect(cv.width == 10);
    try expect(cv.height == 10);
    try expect(cv.rgba.len == 100);

    cv.drawTriangle(.{ .x = -5, .y = 5 }, .{ .x = -5, .y = -4 }, .{ .x = 4, .y = -4 }, c1);
    cv.drawTriangle(.{ .x = -4, .y = 5 }, .{ .x = 4, .y = 5 }, .{ .x = 4, .y = -3 }, c2);
    try std.testing.expectEqualSlices(u8, cv.asBytes(), std.mem.sliceAsBytes(&[_]Color{
        c1, c2, c2, c2, c2, c2, c2, c2, c2, c2,
        c1, c1, c2, c0, c0, c0, c0, c0, c0, c2,
        c1, c0, c1, c2, c0, c0, c0, c0, c0, c2,
        c1, c0, c0, c1, c2, c0, c0, c0, c0, c2,
        c1, c0, c0, c0, c1, c2, c0, c0, c0, c2,
        c1, c0, c0, c0, c0, c1, c2, c0, c0, c2,
        c1, c0, c0, c0, c0, c0, c1, c2, c0, c2,
        c1, c0, c0, c0, c0, c0, c0, c1, c2, c2,
        c1, c0, c0, c0, c0, c0, c0, c0, c1, c2,
        c1, c1, c1, c1, c1, c1, c1, c1, c1, c1,
    }));
}

test "drawLine" {
    var cv = Canvas.init(std.testing.allocator, 10, 10) catch unreachable;
    defer cv.deinit(std.testing.allocator);

    const c0 = Color.transparent;
    const c1 = Color.new(0, 0, 0, 1);
    cv.drawLine(.{ .x = -5, .y = 5 }, .{ .x = 4, .y = -4 }, c1);
    cv.drawLine(.{ .x = 4, .y = 5 }, .{ .x = -5, .y = -4 }, c1);
    cv.drawLine(.{ .x = -5, .y = 0 }, .{ .x = 4, .y = 0 }, c1);
    cv.drawLine(.{ .x = 0, .y = 5 }, .{ .x = 0, .y = -4 }, c1);
    try std.testing.expectEqualSlices(u8, cv.asBytes(), std.mem.sliceAsBytes(&[_]Color{
        c1, c0, c0, c0, c0, c1, c0, c0, c0, c1,
        c0, c1, c0, c0, c0, c1, c0, c0, c1, c0,
        c0, c0, c1, c0, c0, c1, c0, c1, c0, c0,
        c0, c0, c0, c1, c0, c1, c1, c0, c0, c0,
        c0, c0, c0, c0, c1, c1, c0, c0, c0, c0,
        c1, c1, c1, c1, c1, c1, c1, c1, c1, c1,
        c0, c0, c0, c1, c0, c1, c1, c0, c0, c0,
        c0, c0, c1, c0, c0, c1, c0, c1, c0, c0,
        c0, c1, c0, c0, c0, c1, c0, c0, c1, c0,
        c1, c0, c0, c0, c0, c1, c0, c0, c0, c1,
    }));
}

test "putPixel" {
    var cv = Canvas.init(std.testing.allocator, 6, 4) catch unreachable;
    defer cv.deinit(std.testing.allocator);
    const c0 = Color.transparent;
    const c1 = Color.new(0, 0, 0, 1);

    cv.putPixel(.{ .x = -3, .y = 2 }, c1);
    cv.putPixel(.{ .x = 2, .y = 2 }, c1);
    cv.putPixel(.{ .x = -3, .y = -1 }, c1);
    cv.putPixel(.{ .x = 2, .y = -1 }, c1);
    cv.putPixel(.{ .x = 0, .y = 0 }, c1);
    try std.testing.expectEqualSlices(u8, cv.asBytes(), std.mem.sliceAsBytes(&[_]Color{
        c1, c0, c0, c0, c0, c1,
        c0, c0, c0, c0, c0, c0,
        c0, c0, c0, c1, c0, c0,
        c1, c0, c0, c0, c0, c1,
    }));
}

test "asBytes" {
    var cv = Canvas.init(std.testing.allocator, 2, 2) catch unreachable;
    defer cv.deinit(std.testing.allocator);

    cv.putPixel(.{ .x = -1, .y = 1 }, Color.new(0xFF, 0x00, 0x00, 0xFF));
    cv.putPixel(.{ .x = 0, .y = 1 }, Color.new(0x00, 0xFF, 0x00, 0xFF));
    cv.putPixel(.{ .x = -1, .y = 0 }, Color.new(0x00, 0x00, 0xFF, 0xFF));
    cv.putPixel(.{ .x = 0, .y = 0 }, Color.new(0xFF, 0xFF, 0x00, 0x80));
    try std.testing.expectEqualSlices(u8, cv.asBytes(), &[_]u8{
        0xFF, 0x00, 0x00, 0xFF,
        0x00, 0xFF, 0x00, 0xFF,
        0x00, 0x00, 0xFF, 0xFF,
        0xFF, 0xFF, 0x00, 0x80,
    });
}
