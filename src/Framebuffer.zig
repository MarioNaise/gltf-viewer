const std = @import("std");

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
        if (@abs(x0) < self.width / 2 and @abs(y0) < self.height / 2)
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
/// Does not perform bounds checking!
pub fn putPixel(self: *Framebuffer, p: Pixel, c: Color) void {
    self.rgba[@as(usize, @intCast(@as(i32, @intCast(self.height / 2)) - 1 - p[1])) * self.width + @as(usize, @intCast(p[0] + @as(i32, @intCast(self.width / 2))))] = c;
}
