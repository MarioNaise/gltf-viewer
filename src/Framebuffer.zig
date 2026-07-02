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
//
// /// Finds the interpolated value at position between (i_0, d0) and (i_1, d1).
// fn interPolateAt(i_0: i32, d0: i32, i_1: i32, d1: i32, position: i32) i32 {
//     if (i_0 == i_1) return d0;
//
//     const a = (@as(f32, @floatFromInt(d1 - d0))) / (@as(f32, @floatFromInt(i_1 - i_0)));
//     const d: f32 = @floatFromInt(d0);
//     return @round(d + a * @as(f32, @floatFromInt(position)));
// }
//
// // Finds the interpolated value at position between (i_0, d0) and (i_1, _) using the given slope a.
// fn interPolateAtWithSlope(i_0: i32, d0: i32, i_1: i32, position: i32, a: f32) i32 {
//     if (i_0 == i_1) return d0;
//
//     const d: f32 = @floatFromInt(d0);
//     return @round(d + a * @as(f32, @floatFromInt(position)));
// }
