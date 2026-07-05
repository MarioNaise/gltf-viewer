const std = @import("std");
const Vec3 = @import("zalgebra").Vec3;

const Color = @import("Color.zig");
const interpolate = @import("interpolate.zig").interpolate;

const Framebuffer = @This();

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

    pub fn fromVec3(v: Vec3, width: usize, height: usize) Pixel {
        const w: f32 = @floatFromInt(width);
        const h: f32 = @floatFromInt(height);

        return .{
            .x = @as(i32, @trunc(v.x() / v.z() * w)) >> 1,
            .y = @as(i32, @trunc(v.y() / v.z() * h)) >> 1,
        };
    }
};

width: usize,
height: usize,
rgba: []Color,

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Framebuffer {
    if (width < 2 or height < 2) return error.InvalidDimensions;

    const rgba = try allocator.alloc(Color, width * height);
    @memset(rgba, Color.transparent());

    return .{
        .width = width,
        .height = height,
        .rgba = rgba,
    };
}

pub fn deinit(self: *Framebuffer, allocator: std.mem.Allocator) void {
    std.debug.assert(self.rgba.len > 0);
    std.debug.assert(self.rgba.len == self.width * self.height);

    allocator.free(self.rgba);
}

/// Clears the framebuffer by setting all pixels to transparent black (0, 0, 0, 0).
pub fn clear(self: *Framebuffer) void {
    @memset(self.rgba, Color.transparent());
}

pub fn asBytes(self: Framebuffer) []u8 {
    return std.mem.sliceAsBytes(self.rgba);
}

pub fn print(self: Framebuffer) void {
    for (0..self.height) |i| {
        for (i * self.width..(i + 1) * self.width) |j| {
            const col = std.mem.readInt(u32, &[_]u8{
                self.rgba[j].r,
                self.rgba[j].g,
                self.rgba[j].b,
                self.rgba[j].a,
            }, .big);
            std.debug.print("{x:0>4}, ", .{col});
        }
        std.debug.print("\n", .{});
    }
}

pub fn fillShadedTriangle(self: *Framebuffer, a: Pixel, b: Pixel, c: Pixel, color: Color) void {
    var ordered = [3]Pixel{ a, b, c };
    std.sort.block(Pixel, &ordered, {}, struct {
        pub fn lessThan(_: void, pa: Pixel, pb: Pixel) bool {
            return pa.y < pb.y;
        }
    }.lessThan);

    const p0 = ordered[0];
    const p1 = ordered[1];
    const p2 = ordered[2];

    var it_0 = interpolate(i32, p0.y, p0.x, p1.y, p1.x);
    var it_1 = interpolate(i32, p1.y, p1.x, p2.y, p2.x);
    var it_2 = interpolate(i32, p0.y, p0.x, p2.y, p2.x);

    // placeholder values
    var h_it_0 = interpolate(f32, p0.y, 1, p1.y, 1);
    var h_it_1 = interpolate(f32, p1.y, 1, p2.y, 1);
    var h_it_2 = interpolate(f32, p0.y, 1, p2.y, 1);

    var i: usize = 0;
    while (true) : (i += 1) {
        const x012 = blk: {
            if (it_0.peekAt(1) == null)
                break :blk it_1.next() orelse break;
            break :blk it_0.next() orelse break;
        };
        const x02 = it_2.next() orelse break;

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

        var h_segment = interpolate(
            f32,
            left,
            h_left,
            right,
            h_right,
        );

        while (left <= right) : (left += 1) {
            self.putPixel(.{ .x = left, .y = y }, color.mul(h_segment.next() orelse 1));
        }
    }
}

pub fn drawTriangle(self: *Framebuffer, a: Pixel, b: Pixel, c: Pixel, color: Color) void {
    self.drawLine(a, b, color);
    self.drawLine(b, c, color);
    self.drawLine(c, a, color);
}

// https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
/// Draws a line from pixel a to pixel b with color c.
pub fn drawLine(self: *Framebuffer, a: Pixel, b: Pixel, c: Color) void {
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

/// Writes Color c to the framebuffer at Pixel a.
pub fn putPixel(self: *Framebuffer, p: Pixel, c: Color) void {
    const max_width = @as(i32, @intCast(self.width >> 1));
    const max_height = @as(i32, @intCast(self.height >> 1));

    if (p.y > max_height or p.y <= -max_height or
        p.x >= max_width or p.x < -max_width) return;

    const idx = @as(usize, @intCast(max_height - p.y)) * self.width +
        @as(usize, @intCast(p.x + max_width));

    self.rgba[idx] = c;
}

test "init" {
    try std.testing.expectError(error.InvalidDimensions, Framebuffer.init(std.testing.allocator, 1, 1));
}

test "fillShadedTriangle" {
    var fb = Framebuffer.init(std.testing.allocator, 10, 10) catch unreachable;
    defer fb.deinit(std.testing.allocator);

    const c0 = Color.transparent();
    const c1 = Color.new(0, 0, 0, 1);
    const c2 = Color.new(0, 0, 0, 2);

    fb.fillShadedTriangle(.{ .x = -4, .y = 3 }, .{ .x = -4, .y = -3 }, .{ .x = 2, .y = -3 }, c1);
    fb.fillShadedTriangle(.{ .x = -3, .y = 4 }, .{ .x = 3, .y = 4 }, .{ .x = 3, .y = -2 }, c2);

    try std.testing.expect(std.mem.eql(u8, fb.asBytes(), std.mem.sliceAsBytes(&[_]Color{
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

    fb.clear();
    fb.fillShadedTriangle(.{ .x = -5, .y = 5 }, .{ .x = 4, .y = 5 }, .{ .x = 0, .y = 0 }, c1);
    fb.fillShadedTriangle(.{ .x = -5, .y = -4 }, .{ .x = 0, .y = -4 }, .{ .x = -3, .y = -2 }, c1);

    try std.testing.expect(std.mem.eql(u8, fb.asBytes(), std.mem.sliceAsBytes(&[_]Color{
        c1, c1, c1, c1, c1, c1, c1, c1, c1, c1,
        c0, c1, c1, c1, c1, c1, c1, c1, c1, c0,
        c0, c0, c1, c1, c1, c1, c1, c1, c0, c0,
        c0, c0, c0, c1, c1, c1, c1, c1, c0, c0,
        c0, c0, c0, c0, c1, c1, c1, c0, c0, c0,
        c0, c0, c0, c0, c0, c1, c0, c0, c0, c0,
        c0, c0, c0, c0, c0, c0, c0, c0, c0, c0,
        c0, c0, c1, c0, c0, c0, c0, c0, c0, c0,
        c0, c1, c1, c1, c0, c0, c0, c0, c0, c0,
        c1, c1, c1, c1, c1, c1, c0, c0, c0, c0,
    })));
}

test "drawTriangle" {
    const expect = std.testing.expect;

    var fb = Framebuffer.init(std.testing.allocator, 10, 10) catch unreachable;
    defer fb.deinit(std.testing.allocator);

    const c0 = Color.transparent();
    const c1 = Color.new(0, 0, 0, 1);
    const c2 = Color.new(0, 0, 0, 2);

    try expect(fb.width == 10);
    try expect(fb.height == 10);
    try expect(fb.rgba.len == 100);

    fb.drawTriangle(.{ .x = -5, .y = 5 }, .{ .x = -5, .y = -4 }, .{ .x = 4, .y = -4 }, c1);
    fb.drawTriangle(.{ .x = -4, .y = 5 }, .{ .x = 4, .y = 5 }, .{ .x = 4, .y = -3 }, c2);
    try expect(std.mem.eql(u8, fb.asBytes(), std.mem.sliceAsBytes(&[_]Color{
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
    })));
}

test "drawLine" {
    var fb = Framebuffer.init(std.testing.allocator, 10, 10) catch unreachable;
    defer fb.deinit(std.testing.allocator);

    const c0 = Color.transparent();
    const c1 = Color.new(0, 0, 0, 1);
    fb.drawLine(.{ .x = -5, .y = 5 }, .{ .x = 4, .y = -4 }, c1);
    fb.drawLine(.{ .x = 4, .y = 5 }, .{ .x = -5, .y = -4 }, c1);
    fb.drawLine(.{ .x = -5, .y = 0 }, .{ .x = 4, .y = 0 }, c1);
    fb.drawLine(.{ .x = 0, .y = 5 }, .{ .x = 0, .y = -4 }, c1);
    try std.testing.expect(std.mem.eql(u8, fb.asBytes(), std.mem.sliceAsBytes(&[_]Color{
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
    })));
}

test "putPixel" {
    var fb = Framebuffer.init(std.testing.allocator, 6, 4) catch unreachable;
    defer fb.deinit(std.testing.allocator);
    const c0 = Color.transparent();
    const c1 = Color.new(0, 0, 0, 1);

    fb.putPixel(.{ .x = -3, .y = 2 }, c1);
    fb.putPixel(.{ .x = 2, .y = 2 }, c1);
    fb.putPixel(.{ .x = -3, .y = -1 }, c1);
    fb.putPixel(.{ .x = 2, .y = -1 }, c1);
    fb.putPixel(.{ .x = 0, .y = 0 }, c1);
    try std.testing.expect(std.mem.eql(u8, fb.asBytes(), std.mem.sliceAsBytes(&[_]Color{
        c1, c0, c0, c0, c0, c1,
        c0, c0, c0, c0, c0, c0,
        c0, c0, c0, c1, c0, c0,
        c1, c0, c0, c0, c0, c1,
    })));
}

test "asBytes" {
    var fb = Framebuffer.init(std.testing.allocator, 2, 2) catch unreachable;
    defer fb.deinit(std.testing.allocator);

    fb.putPixel(.{ .x = -1, .y = 1 }, Color.new(0xFF, 0x00, 0x00, 0xFF));
    fb.putPixel(.{ .x = 0, .y = 1 }, Color.new(0x00, 0xFF, 0x00, 0xFF));
    fb.putPixel(.{ .x = -1, .y = 0 }, Color.new(0x00, 0x00, 0xFF, 0xFF));
    fb.putPixel(.{ .x = 0, .y = 0 }, Color.new(0xFF, 0xFF, 0x00, 0x80));
    try std.testing.expect(std.mem.eql(u8, fb.asBytes(), &[_]u8{
        0xFF, 0x00, 0x00, 0xFF,
        0x00, 0xFF, 0x00, 0xFF,
        0x00, 0x00, 0xFF, 0xFF,
        0xFF, 0xFF, 0x00, 0x80,
    }));
}
