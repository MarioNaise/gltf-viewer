const std = @import("std");

/// An iterator that interpolates between two values over a given range of indices.
const Iterator = @This();

i0: i32,
d0: i32,
i1: i32,
d1: i32,
a: f32,
index: usize,

pub fn new(i_0: i32, d0: i32, i_1: i32, d1: i32) Iterator {
    const delta_i: f32 = @floatFromInt(i_1 - i_0);
    const delta_d: f32 = @floatFromInt(d1 - d0);
    return .{
        .i0 = i_0,
        .d0 = d0,
        .i1 = i_1,
        .d1 = d1,
        .a = if (delta_i == 0) 0 else delta_d / delta_i,
        .index = 0,
    };
}

pub fn peek(self: *Iterator) ?i32 {
    return self.peekAt(0);
}

pub fn peekAt(self: *Iterator, position: usize) ?i32 {
    if (self.index + position > @abs(self.i0 - self.i1)) return null;

    if (self.i0 == self.i1) {
        return self.d0;
    }

    const d: f32 = @floatFromInt(self.d0);
    const i: f32 = @floatFromInt(self.index + position);
    const value = @as(i32, @round(d + self.a * i));
    return value;
}

pub fn next(self: *Iterator) ?i32 {
    const value = self.peek();
    self.index += 1;
    return value;
}

pub fn resetInit(self: *Iterator, i_0: i32, d0: i32, i_1: i32, d1: i32) void {
    const delta_i: f32 = @floatFromInt(i_1 - i_0);
    const delta_d: f32 = @floatFromInt(d1 - d0);
    self.i0 = i_0;
    self.d0 = d0;
    self.i1 = i_1;
    self.d1 = d1;
    self.a = if (delta_i == 0) 0 else delta_d / delta_i;
    self.index = 0;
}

pub fn reset(self: *Iterator) void {
    self.index = 0;
}

test "InterpolationIterator" {
    var it = Iterator.new(0, 0, 10, 100);
    try std.testing.expectEqual(it.next(), 0);
    try std.testing.expectEqual(it.next(), 10);
    try std.testing.expectEqual(it.next(), 20);
    try std.testing.expectEqual(it.next(), 30);
    try std.testing.expectEqual(it.next(), 40);
    try std.testing.expectEqual(it.next(), 50);
    try std.testing.expectEqual(it.next(), 60);
    try std.testing.expectEqual(it.next(), 70);
    try std.testing.expectEqual(it.next(), 80);
    try std.testing.expectEqual(it.next(), 90);
    try std.testing.expectEqual(it.next(), 100);
    try std.testing.expectEqual(it.next(), null);

    it.reset();
    try std.testing.expectEqual(it.peek(), 0);

    it.resetInit(5, 50, 15, 70);
    try std.testing.expectEqual(it.peek(), 50);
    try std.testing.expectEqual(it.next(), 50);
    try std.testing.expectEqual(it.next(), 52);

    it.resetInit(5, 50, 5, 70);
    try std.testing.expectEqual(it.next(), 50);
    try std.testing.expectEqual(it.next(), null);
}

// not needed currently
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
// /// Finds the interpolated value at position between (i_0, d0) and (i_1, _) using the given slope a.
// fn interPolateAtWithSlope(i_0: i32, d0: i32, i_1: i32, position: i32, a: f32) i32 {
//     if (i_0 == i_1) return d0;
//
//     const d: f32 = @floatFromInt(d0);
//     return @round(d + a * @as(f32, @floatFromInt(position)));
// }
