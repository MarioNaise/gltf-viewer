pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Vec2 = struct {
    x: i32,
    y: i32,
};

pub fn project(p: Vec3, min: Vec3, max: Vec3, width: usize, height: usize) Vec2 {
    const sx = max.x - min.x;
    const sy = max.y - min.y;

    const scale = @max(sx, sy);
    const safe_scale = if (scale == 0) 1 else scale;

    const nx = (p.x - min.x) / safe_scale;
    const ny = (p.y - min.y) / safe_scale;

    const margin: f32 = 32;
    const fw: f32 = @floatFromInt(width);
    const fh: f32 = @floatFromInt(height);

    const x = margin + nx * (fw - margin * 2);
    const y = margin + ny * (fh - margin * 2);

    return .{
        .x = @intFromFloat(x),
        .y = @intFromFloat(fh - y),
    };
}
