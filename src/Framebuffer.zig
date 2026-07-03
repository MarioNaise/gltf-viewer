const std = @import("std");

const InterpolationIterator = @import("InterpolationIterator.zig");

const Framebuffer = @This();

pub const Pixel = [2]i32;
pub const Color = u32;

width: usize,
height: usize,
rgba: []Color,

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Framebuffer {
    if (width == 0 or height == 0) return error.InvalidDimensions;

    const rgba = try allocator.alloc(Color, width * height);
    @memset(rgba, 0);

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
    @memset(self.rgba, 0);
}

pub fn fillTriangle(self: *Framebuffer, a: Pixel, b: Pixel, c: Pixel, color: Color) void {
    var ordered = [3]Pixel{ a, b, c };
    std.sort.block(Pixel, &ordered, {}, struct {
        pub fn lessThan(_: void, pa: Pixel, pb: Pixel) bool {
            return pa[1] < pb[1];
        }
    }.lessThan);

    const p0 = ordered[0];
    const p1 = ordered[1];
    const p2 = ordered[2];

    var it_0: InterpolationIterator = .new(p0[1], p0[0], p1[1], p1[0]);
    var it_1: InterpolationIterator = .new(p1[1], p1[0], p2[1], p2[0]);
    var it_2: InterpolationIterator = .new(p0[1], p0[0], p2[1], p2[0]);

    var i: usize = 0;
    while (true) : (i += 1) {
        const x012 = blk: {
            if (it_0.peekAt(1) == null)
                break :blk it_1.next() orelse break;
            break :blk it_0.next() orelse break;
        };
        const x02 = it_2.next() orelse break;
        const y = p0[1] + @as(i32, @intCast(i));

        var left = @min(x02, x012);
        const right = @max(x02, x012);

        while (left <= right) : (left += 1) {
            self.putPixel(.{ left, y }, color);
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
    var x0 = a[0];
    var y0 = a[1];

    const x1 = b[0];
    const y1 = b[1];

    const dx: i32 = @intCast(@abs(x1 - x0));
    const sx: i32 = if (x0 < x1) 1 else -1;

    const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
    const sy: i32 = if (y0 < y1) 1 else -1;

    var err = dx + dy;

    while (true) {
        self.putPixel(.{ x0, y0 }, c);

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
    const half_width = @as(i32, @intCast(self.width / 2));
    const half_height = @as(i32, @intCast(self.height / 2));

    if (p[1] > half_height or p[1] <= -half_height or
        p[0] >= half_width or p[0] < -half_width) return;

    const idx = @as(usize, @intCast(@as(i32, @intCast(self.height / 2)) - p[1])) * self.width +
        @as(usize, @intCast(p[0] + @as(i32, @intCast(self.width / 2))));

    self.rgba[idx] = c;
}

test "fillTriangle" {
    var fb = Framebuffer.init(std.testing.allocator, 10, 10) catch unreachable;
    defer fb.deinit(std.testing.allocator);

    fb.fillTriangle(.{ -4, 3 }, .{ -4, -3 }, .{ 2, -3 }, 1);
    fb.fillTriangle(.{ -3, 4 }, .{ 3, 4 }, .{ 3, -2 }, 2);

    try std.testing.expect(std.mem.eql(u32, fb.rgba, &[_]u32{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 2, 2, 2, 2, 2, 2, 2, 0,
        0, 1, 0, 2, 2, 2, 2, 2, 2, 0,
        0, 1, 1, 0, 2, 2, 2, 2, 2, 0,
        0, 1, 1, 1, 0, 2, 2, 2, 2, 0,
        0, 1, 1, 1, 1, 0, 2, 2, 2, 0,
        0, 1, 1, 1, 1, 1, 0, 2, 2, 0,
        0, 1, 1, 1, 1, 1, 1, 0, 2, 0,
        0, 1, 1, 1, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    }));

    fb.clear();
    fb.fillTriangle(.{ -5, 5 }, .{ 4, 5 }, .{ 0, 0 }, 1);

    try std.testing.expect(std.mem.eql(u32, fb.rgba, &[_]u32{
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        0, 1, 1, 1, 1, 1, 1, 1, 1, 0,
        0, 0, 1, 1, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 1, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 0, 1, 1, 1, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    }));
}

test "drawTriangle" {
    var fb = Framebuffer.init(std.testing.allocator, 10, 10) catch unreachable;
    defer fb.deinit(std.testing.allocator);

    try std.testing.expect(fb.width == 10);
    try std.testing.expect(fb.height == 10);
    try std.testing.expect(fb.rgba.len == 100);

    fb.drawTriangle(.{ -5, 5 }, .{ -5, -4 }, .{ 4, -4 }, 1);
    fb.drawTriangle(.{ -4, 5 }, .{ 4, 5 }, .{ 4, -3 }, 2);
    try std.testing.expect(std.mem.eql(u32, fb.rgba, &[_]u32{
        1, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        1, 1, 2, 0, 0, 0, 0, 0, 0, 2,
        1, 0, 1, 2, 0, 0, 0, 0, 0, 2,
        1, 0, 0, 1, 2, 0, 0, 0, 0, 2,
        1, 0, 0, 0, 1, 2, 0, 0, 0, 2,
        1, 0, 0, 0, 0, 1, 2, 0, 0, 2,
        1, 0, 0, 0, 0, 0, 1, 2, 0, 2,
        1, 0, 0, 0, 0, 0, 0, 1, 2, 2,
        1, 0, 0, 0, 0, 0, 0, 0, 1, 2,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    }));
}

test "drawLine" {
    var fb = Framebuffer.init(std.testing.allocator, 10, 10) catch unreachable;
    defer fb.deinit(std.testing.allocator);
    fb.drawLine(.{ -5, 5 }, .{ 4, -4 }, 1);
    fb.drawLine(.{ 4, 5 }, .{ -5, -4 }, 1);
    fb.drawLine(.{ -5, 0 }, .{ 4, 0 }, 1);
    fb.drawLine(.{ 0, 5 }, .{ 0, -4 }, 1);
    try std.testing.expect(std.mem.eql(u32, fb.rgba, &[_]u32{
        1, 0, 0, 0, 0, 1, 0, 0, 0, 1,
        0, 1, 0, 0, 0, 1, 0, 0, 1, 0,
        0, 0, 1, 0, 0, 1, 0, 1, 0, 0,
        0, 0, 0, 1, 0, 1, 1, 0, 0, 0,
        0, 0, 0, 0, 1, 1, 0, 0, 0, 0,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        0, 0, 0, 1, 0, 1, 1, 0, 0, 0,
        0, 0, 1, 0, 0, 1, 0, 1, 0, 0,
        0, 1, 0, 0, 0, 1, 0, 0, 1, 0,
        1, 0, 0, 0, 0, 1, 0, 0, 0, 1,
    }));
}

// Alternative drawLine implementation using interpolation
// https://www.gabrielgambetta.com/computer-graphics-from-scratch/06-lines.html
// pub fn drawLine(self: *Framebuffer, a: Pixel, b: Pixel, c: Color) void {
//     const draw_x_axis = @abs(b[0] - a[0]) > @abs(b[1] - a[1]);
//     const swap = draw_x_axis and a[0] > b[0] or !draw_x_axis and a[1] > b[1];
//
//     const x0 = if (swap) b[0] else a[0];
//     const y0 = if (swap) b[1] else a[1];
//     const x1 = if (swap) a[0] else b[0];
//     const y1 = if (swap) a[1] else b[1];
//
//     var i: usize = 0;
//     if (draw_x_axis) {
//         const slope = (@as(f32, @floatFromInt(y1 - y0))) / (@as(f32, @floatFromInt(x1 - x0)));
//         while (x0 + @as(i32, @intCast(i)) <= x1) : (i += 1) {
//             if (@abs(x0 + @as(i32, @intCast(i))) >= self.width / 2) continue;
//
//             const val = interPolateAtWithSlope(x0, y0, x1, @intCast(i), slope);
//             if (val < self.height / 2)
//                 self.putPixel(.{ x0 + @as(i32, @intCast(i)), val }, c);
//         }
//     } else {
//         const slope = (@as(f32, @floatFromInt(x1 - x0))) / (@as(f32, @floatFromInt(y1 - y0)));
//         while (y0 + @as(i32, @intCast(i)) <= y1) : (i += 1) {
//             if (@abs(y0 + @as(i32, @intCast(i))) >= self.height / 2) continue;
//
//             const val = interPolateAtWithSlope(y0, x0, y1, @intCast(i), slope);
//             if (@abs(val) < self.width / 2)
//                 self.putPixel(.{ val, y0 + @as(i32, @intCast(i)) }, c);
//         }
//     }
// }
