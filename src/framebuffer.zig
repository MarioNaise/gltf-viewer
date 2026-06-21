const std = @import("std");
const vec = @import("vector.zig");
const Framebuffer = @This();

width: usize,
height: usize,
rgba: []u8,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Framebuffer {
    const rgba = try allocator.alloc(u8, width * height * 4);
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

// https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
pub fn drawLine(self: *Framebuffer, a: vec.Vec2, b: vec.Vec2) void {
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
        self.putPixel(x0, y0, 0, 0, 0);

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

pub fn putPixel(self: *Framebuffer, x: i32, y: i32, r: u8, g: u8, b: u8) void {
    if (x < 0 or y < 0) return;

    const ux: usize = @intCast(x);
    const uy: usize = @intCast(y);

    if (ux >= self.width or uy >= self.height) return;

    const index = (uy * self.width + ux) * 4;
    self.rgba[index + 0] = r;
    self.rgba[index + 1] = g;
    self.rgba[index + 2] = b;
    self.rgba[index + 3] = 255;
}
