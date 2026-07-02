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
    return .{
        .i0 = i_0,
        .d0 = d0,
        .i1 = i_1,
        .d1 = d1,
        .a = if (i_0 == i_1) 0 else (@as(f32, @floatFromInt(d1 - d0))) / (@as(f32, @floatFromInt(i_1 - i_0))),
        .index = 0,
    };
}

pub fn peek(self: *Iterator) ?i32 {
    if (self.index > @abs(self.i0 - self.i1)) return null;

    if (self.i0 == self.i1) {
        return self.d0;
    }

    const value = @as(i32, @round(@as(f32, @floatFromInt(self.d0)) + self.a * @as(f32, @floatFromInt(@as(i32, @intCast(self.index))))));
    return value;
}

pub fn next(self: *Iterator) ?i32 {
    const value = self.peek();
    self.index += 1;
    return value;
}

pub fn resetInit(self: *Iterator, i_0: i32, d0: i32, i_1: i32, d1: i32) void {
    self.i0 = i_0;
    self.d0 = d0;
    self.i1 = i_1;
    self.d1 = d1;
    self.a = if (i_0 == i_1) 0 else (@as(f32, @floatFromInt(d1 - d0))) / (@as(f32, @floatFromInt(i_1 - i_0)));
    self.index = 0;
}

pub fn reset(self: *Iterator) void {
    self.index = 0;
}

// not needed currently, but could be useful in the future.
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
