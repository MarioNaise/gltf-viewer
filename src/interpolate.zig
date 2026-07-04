const std = @import("std");

pub fn interpolate(comptime T: type, i_0: i32, d0: T, i_1: i32, d1: T) LerpIterator(T) {
    const is_float = comptime isFloat(T);

    const delta_i = @as(if (is_float) T else f32, @floatFromInt(i_1 - i_0));
    const delta_d = if (is_float) @as(T, d1 - d0) else @as(f32, @floatFromInt(d1 - d0));

    return .{
        .i0 = i_0,
        .d0 = d0,
        .i1 = i_1,
        .d1 = d1,
        .a = if (delta_i == 0) 0 else delta_d / delta_i,
        .max_count = @abs(i_0 - i_1),
        .index = 0,
    };
}

/// Performs linear interpolation between two values over a range of indices.
pub fn LerpIterator(comptime T: type) type {
    const is_float = comptime isFloat(T);

    return struct {
        i0: i32,
        d0: T,
        i1: i32,
        d1: T,
        a: if (is_float) T else f32,
        index: usize,
        max_count: usize,

        const Self = @This();

        pub fn peek(self: *Self) ?T {
            return self.peekAt(0);
        }

        pub fn peekAt(self: *Self, position: usize) ?T {
            if (self.index + position >
                self.max_count)
                return null;

            if (self.i0 == self.i1) {
                return self.d0;
            }

            const d = if (is_float) self.d0 else @as(f32, @floatFromInt(self.d0));
            const i = @as(if (is_float) T else f32, @floatFromInt(self.index + position));
            const value = if (is_float) @mulAdd(T, self.a, i, d) else @as(T, @round(@mulAdd(f32, self.a, i, d)));
            return value;
        }

        pub fn next(self: *Self) ?T {
            defer self.index += 1;
            return self.peekAt(0);
        }

        pub fn resetInit(self: *Self, i_0: i32, d0: T, i_1: i32, d1: T) void {
            const delta_i = if (is_float) i_1 - i_0 else @as(f32, @floatFromInt(i_1 - i_0));
            const delta_d = if (is_float) d1 - d0 else @as(f32, @floatFromInt(d1 - d0));
            self.i0 = i_0;
            self.d0 = d0;
            self.i1 = i_1;
            self.d1 = d1;
            self.a = if (delta_i == 0) 0 else delta_d / delta_i;
            self.max_count = @abs(i_0 - i_1);
            self.index = 0;
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }
    };
}

fn isFloat(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .int => false,
        .float => true,
        else => @compileError("Unsupported type for interpolation"),
    };
}

test "LerpIterator" {
    var it = interpolate(i32, 0, 0, 10, 100);
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

    var it2 = interpolate(f32, 0, 0, 5, 1);
    try std.testing.expectEqual(it2.next(), 0);
    try std.testing.expectEqual(it2.next(), 0.2);
    try std.testing.expectEqual(it2.next(), 0.4);
    try std.testing.expectEqual(it2.next(), 0.6);
    try std.testing.expectEqual(it2.next(), 0.8);
    try std.testing.expectEqual(it2.next(), 1.0);
    try std.testing.expectEqual(it2.next(), null);
}
