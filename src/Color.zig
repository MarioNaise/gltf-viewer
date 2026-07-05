const std = @import("std");
const clamp = std.math.clamp;

r: u8,
g: u8,
b: u8,
a: u8,

const Color = @This();

pub fn new(r: u8, g: u8, b: u8, a: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

pub fn transparent() Color {
    return new(0, 0, 0, 0);
}

pub fn white() Color {
    return new(0xFF, 0xFF, 0xFF, 0xFF);
}

/// Returns a new color.
/// Leaves the alpha value unchanged.
pub fn mul(self: Color, factor: f32) Color {
    return .{
        .r = @round(clamp(@as(f32, @floatFromInt(self.r)) * factor, 0, 0xFF)),
        .g = @round(clamp(@as(f32, @floatFromInt(self.g)) * factor, 0, 0xFF)),
        .b = @round(clamp(@as(f32, @floatFromInt(self.b)) * factor, 0, 0xFF)),
        .a = self.a,
    };
}

/// Returns a new color.
/// Leaves the RGB values unchanged.
pub fn opacity(self: Color, alpha: f32) Color {
    return .{
        .r = self.r,
        .g = self.g,
        .b = self.b,
        .a = @round(clamp(0xFF * alpha, 0, 0xFF)),
    };
}

test "Color" {
    const expectEql = std.testing.expectEqual;
    try expectEql(Color.new(0, 0, 0, 0), Color.transparent());
    try expectEql(Color.new(0xFF, 0xFF, 0xFF, 0xFF), Color.white());
    try expectEql(Color.new(0x80, 0x80, 0x80, 0xFF), Color.white().mul(0.5));
    try expectEql(Color.new(0x00, 0x00, 0x00, 0xFF), Color.white().mul(-0.5));
    try expectEql(Color.new(0xFF, 0xFF, 0xFF, 0x80), Color.white().opacity(0.5));
    try expectEql(Color.new(0xFF, 0xFF, 0xFF, 0x00), Color.white().opacity(-0.5));
}
