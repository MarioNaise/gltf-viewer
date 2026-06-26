const std = @import("std");
const Framebuffer = @This();

pub const Pixel = [2]i32;
pub const Color = [4]u8;

width: usize,
height: usize,
rgba: []u8,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Framebuffer {
    const size = width * height * 4;
    if (size == 0) return error.InvalidDimensions;

    const rgba = try allocator.alloc(u8, size);
    @memset(rgba, 0);

    return .{
        .width = width,
        .height = height,
        .rgba = rgba,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Framebuffer) void {
    std.debug.assert(self.rgba.len > 0);
    std.debug.assert(self.rgba.len == self.width * self.height * 4);

    self.allocator.free(self.rgba);
}

pub fn clear(self: *Framebuffer) void {
    @memset(self.rgba, 0);
}

// https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
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

pub fn putPixel(self: *Framebuffer, p: Pixel, c: Color) void {
    if (p[0] < 0 or p[1] < 0) return;

    const ux: usize = @intCast(p[0]);
    const uy: usize = @intCast(p[1]);

    if (ux >= self.width or uy >= self.height) return;

    const index = (uy * self.width + ux) * 4;
    self.rgba[index + 0] = c[0];
    self.rgba[index + 1] = c[1];
    self.rgba[index + 2] = c[2];
    self.rgba[index + 3] = c[3];
}

pub fn putFatPixel(self: *Framebuffer, p: Pixel, c: Color) void {
    self.putPixel(.{ p[0], p[1] }, c);
    self.putPixel(.{ p[0], p[1] - 1 }, c);
    self.putPixel(.{ p[0], p[1] + 1 }, c);
    self.putPixel(.{ p[0] - 1, p[1] }, c);
    self.putPixel(.{ p[0] - 1, p[1] - 1 }, c);
    self.putPixel(.{ p[0] - 1, p[1] + 1 }, c);
    self.putPixel(.{ p[0] + 1, p[1] }, c);
    self.putPixel(.{ p[0] + 1, p[1] - 1 }, c);
    self.putPixel(.{ p[0] + 1, p[1] + 1 }, c);
}
