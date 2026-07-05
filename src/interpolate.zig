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
    const expectEql = @import("std").testing.expectEqual;
    var it = interpolate(i32, 0, 0, 10, 100);
    try expectEql(0, it.next());
    try expectEql(10, it.next());
    try expectEql(20, it.next());
    try expectEql(30, it.next());
    try expectEql(40, it.next());
    try expectEql(50, it.next());
    try expectEql(60, it.next());
    try expectEql(70, it.next());
    try expectEql(80, it.next());
    try expectEql(90, it.next());
    try expectEql(100, it.next());
    try expectEql(null, it.next());

    it.reset();
    try expectEql(0, it.peek());

    it.resetInit(5, 50, 15, 70);
    try expectEql(50, it.peek());
    try expectEql(50, it.next());
    try expectEql(52, it.next());

    it.resetInit(5, 50, 5, 70);
    try expectEql(50, it.next());
    try expectEql(null, it.next());

    var it2 = interpolate(f32, 0, 0, 5, 1);
    try expectEql(0, it2.next());
    try expectEql(0.2, it2.next());
    try expectEql(0.4, it2.next());
    try expectEql(0.6, it2.next());
    try expectEql(0.8, it2.next());
    try expectEql(1.0, it2.next());
    try expectEql(null, it2.next());
}
